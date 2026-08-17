import AppKit

// MultitouchSupport private-framework types (layout from open-source MT
// consumers). File-scope because @convention(c) signatures can't reference
// class-nested types.
private struct MTPoint { var x: Float; var y: Float }
private struct MTReadout { var pos: MTPoint; var vel: MTPoint }
private struct MTTouch {
    var frame: Int32
    var timestamp: Double
    var identifier: Int32
    var state: Int32
    var fingerID: Int32
    var handID: Int32
    var normalized: MTReadout   // pos in [0,1], origin bottom-left
    var zTotal: Float
    var field9: Int32
    var angle: Float
    var majorAxis: Float
    var minorAxis: Float
    var absoluteVector: MTReadout
    var field14: Int32
    var field15: Int32
    var zDensity: Float
}

private typealias MTDeviceRef = UnsafeMutableRawPointer
// Touches arrive as a raw pointer (custom structs aren't allowed in
// @convention(c) signatures); handleFrame binds it to MTTouch.
private typealias MTFrameCallback = @convention(c) (
    UnsafeMutableRawPointer?, UnsafeRawPointer?, Int32, Double, Int32
) -> Int32
private typealias MTCreateListFn = @convention(c) () -> Unmanaged<CFArray>?
private typealias MTRegisterFn = @convention(c) (MTDeviceRef, MTFrameCallback?) -> Void
private typealias MTStartFn = @convention(c) (MTDeviceRef, Int32) -> Int32
private typealias MTStopFn = @convention(c) (MTDeviceRef) -> Int32

/// Two-finger swipe from the right trackpad edge → summon the sheet.
///
/// Reads raw touches from the private MultitouchSupport framework (the
/// BetterTouchTool/Swish technique). Being private API, everything is defensive:
/// if the framework or any symbol is missing, `available` is false and the
/// feature is a silent no-op. Devices are only started while enabled, so the
/// cost when disabled is zero.
final class EdgeSwipeMonitor: @unchecked Sendable {
    /// The MT frame callback carries no context pointer, hence a singleton.
    static let shared = EdgeSwipeMonitor()

    /// Called on the main actor when the gesture fires.
    var onSwipe: (@MainActor () -> Void)?

    private let createList: MTCreateListFn?
    private let register: MTRegisterFn?
    private let unregister: MTRegisterFn?
    private let startDevice: MTStartFn?
    private let stopDevice: MTStopFn?

    let available: Bool

    private var devices: [MTDeviceRef] = []

    // Gesture state; only touched from MT callback threads, under the lock.
    private let lock = NSLock()
    private var tracking = false
    private var trackStart: Double = 0
    private var trackStartX: Float = 0
    private var lastFire: Double = 0

    private init() {
        let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
        let lib = dlopen(path, RTLD_NOW)

        func load<T>(_ name: String, as type: T.Type) -> T? {
            guard let lib, let sym = dlsym(lib, name) else { return nil }
            return unsafeBitCast(sym, to: type)
        }

        createList = load("MTDeviceCreateList", as: MTCreateListFn.self)
        register = load("MTRegisterContactFrameCallback", as: MTRegisterFn.self)
        unregister = load("MTUnregisterContactFrameCallback", as: MTRegisterFn.self)
        startDevice = load("MTDeviceStart", as: MTStartFn.self)
        stopDevice = load("MTDeviceStop", as: MTStopFn.self)
        available = createList != nil && register != nil && unregister != nil
            && startDevice != nil && stopDevice != nil
    }

    func enable() {
        guard available, devices.isEmpty,
              let list = createList?()?.takeRetainedValue() else { return }
        for i in 0..<CFArrayGetCount(list) {
            guard let ptr = CFArrayGetValueAtIndex(list, i) else { continue }
            let device = MTDeviceRef(mutating: ptr)
            register?(device, edgeSwipeFrameCallback)
            _ = startDevice?(device, 0)
            devices.append(device)
        }
    }

    func disable() {
        let noCallback: MTFrameCallback? = nil
        for device in devices {
            _ = stopDevice?(device)
            unregister?(device, noCallback)
        }
        devices.removeAll()
    }

    // Two fingers appearing at the far right edge, then moving left within half
    // a second: that's the Notification Center-style edge swipe.
    fileprivate func handleFrame(_ raw: UnsafeRawPointer?, count: Int32, timestamp: Double) {
        lock.lock()
        defer { lock.unlock() }

        guard let raw, count == 2 else {
            tracking = false
            return
        }
        let touches = raw.assumingMemoryBound(to: MTTouch.self)
        let minX = min(touches[0].normalized.pos.x, touches[1].normalized.pos.x)

        if !tracking {
            if minX > 0.985 {
                tracking = true
                trackStart = timestamp
                trackStartX = minX
            }
            return
        }
        if timestamp - trackStart > 0.5 {
            tracking = false
            return
        }
        if trackStartX - minX > 0.08, timestamp - lastFire > 0.7 {
            tracking = false
            lastFire = timestamp
            let callback = onSwipe
            DispatchQueue.main.async {
                MainActor.assumeIsolated { callback?() }
            }
        }
    }
}

private func edgeSwipeFrameCallback(
    _ device: UnsafeMutableRawPointer?,
    _ touches: UnsafeRawPointer?,
    _ count: Int32,
    _ timestamp: Double,
    _ frame: Int32
) -> Int32 {
    EdgeSwipeMonitor.shared.handleFrame(touches, count: count, timestamp: timestamp)
    return 0
}
