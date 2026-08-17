import AppKit
import SwiftUI

/// The app's single surface: a full-height, right-anchored, non-activating panel.
/// It floats above everything (including fullscreen apps) and never steals focus.
@MainActor
final class SheetController {
    static let width: CGFloat = 380

    private lazy var panel: NSPanel = makePanel()

    func toggle() {
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            show()
        }
    }

    private func show() {
        // Anchor to the screen the cursor is on, not necessarily the main one.
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        panel.setFrame(
            NSRect(x: frame.maxX - Self.width, y: frame.minY, width: Self.width, height: frame.height),
            display: true
        )
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
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
        panel.contentView = NSHostingView(rootView: SheetView())
        return panel
    }
}
