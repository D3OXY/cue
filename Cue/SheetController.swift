import AppKit
import SwiftUI

/// Borderless panels can't become key by default; typing in the sheet needs key
/// status (without activating the app — .nonactivatingPanel handles that part).
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// The app's single surface: a full-height, right-anchored, non-activating panel.
/// It floats above everything (including fullscreen apps) and never steals focus
/// from the frontmost app.
@MainActor
final class SheetController {
    static let width: CGFloat = 380
    private static let slideDuration: TimeInterval = 0.22

    let model = SheetModel()

    private lazy var panel: NSPanel = makePanel()
    private var clickAwayMonitor: Any?

    init() {
        model.requestClose = { [weak self] in self?.hide() }
    }

    func toggle() {
        panel.isVisible ? hide() : show()
    }

    func show() {
        // Anchor to the screen the cursor is on, not necessarily the main one.
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }

        let final = NSRect(x: frame.maxX - Self.width, y: frame.minY, width: Self.width, height: frame.height)
        let offscreen = final.offsetBy(dx: Self.width, dy: 0)

        panel.setFrame(offscreen, display: false)
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.slideDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(final, display: true)
        }

        model.presentation += 1
        installClickAwayMonitor()
    }

    func hide() {
        removeClickAwayMonitor()
        let offscreen = panel.frame.offsetBy(dx: Self.width, dy: 0)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.slideDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(offscreen, display: true)
        } completionHandler: { [panel] in
            // NSAnimationContext completion fires on the main thread.
            MainActor.assumeIsolated { panel.orderOut(nil) }
        }
    }

    // Clicks in other apps only reach a global monitor, so any event here means
    // the user clicked outside the sheet.
    private func installClickAwayMonitor() {
        guard clickAwayMonitor == nil else { return }
        clickAwayMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.panel.isVisible, !self.model.pinned else { return }
                self.hide()
            }
        }
    }

    private func removeClickAwayMonitor() {
        if let clickAwayMonitor {
            NSEvent.removeMonitor(clickAwayMonitor)
            self.clickAwayMonitor = nil
        }
    }

    private func makePanel() -> NSPanel {
        let panel = KeyablePanel(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.isMovableByWindowBackground = false
        panel.contentView = NSHostingView(rootView: SheetView(model: model))
        return panel
    }
}
