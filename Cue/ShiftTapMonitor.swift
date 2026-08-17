import AppKit

/// System-wide double-Shift detector via a listen-only CGEventTap.
/// Requires Accessibility trust — call `start()` only once `AXIsProcessTrusted()`.
///
/// Double-tap = Shift press, release, press within `window`, with no other key
/// or modifier in between. Any intervening event resets the state machine, so
/// SHIFT-heavy typing never false-triggers.
@MainActor
final class ShiftTapMonitor {
    var onDoubleShift: (() -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private let window: TimeInterval = 0.3
    private var lastPress: TimeInterval = 0
    private var shiftDown = false
    private var awaitingSecondPress = false

    var isRunning: Bool { tap != nil }

    func start() {
        guard tap == nil else { return }
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: shiftTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    fileprivate func handle(type: CGEventType, flags: CGEventFlags) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .keyDown:
            reset()
        case .flagsChanged:
            handleFlags(flags)
        default:
            break
        }
    }

    private func handleFlags(_ flags: CGEventFlags) {
        let otherModifiers: CGEventFlags = [.maskControl, .maskCommand, .maskAlternate, .maskSecondaryFn]
        guard flags.intersection(otherModifiers).isEmpty else {
            reset()
            return
        }

        let now = ProcessInfo.processInfo.systemUptime
        let isDown = flags.contains(.maskShift)
        defer { shiftDown = isDown }

        if isDown, !shiftDown {
            if awaitingSecondPress, now - lastPress < window {
                reset()
                onDoubleShift?()
            } else {
                lastPress = now
                awaitingSecondPress = false
            }
        } else if !isDown, shiftDown {
            awaitingSecondPress = now - lastPress < window
        }
    }

    private func reset() {
        awaitingSecondPress = false
        lastPress = 0
    }
}

private func shiftTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if let refcon {
        let flags = event.flags
        let monitor = Unmanaged<ShiftTapMonitor>.fromOpaque(refcon).takeUnretainedValue()
        // The tap's run loop source lives on the main run loop.
        MainActor.assumeIsolated {
            monitor.handle(type: type, flags: flags)
        }
    }
    return Unmanaged.passUnretained(event)
}
