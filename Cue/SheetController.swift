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
    private var keyMonitor: Any?

    init() {
        model.requestClose = { [weak self] in self?.hide() }
        installKeyMonitor()
    }

    /// True while the sheet itself has key focus (e.g. typing in the composer).
    var isKey: Bool { panel.isKeyWindow }

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

    // No menu bar (LSUIElement) means no Edit-menu key equivalents, so ⌘C/⌘Z on
    // the item list are handled here. Text fields keep their own copy/undo: when
    // the first responder is a field editor the event passes through untouched.
    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // NSEvent isn't Sendable; pull out what we need before the actor hop.
            let key = event.charactersIgnoringModifiers
            let command = event.modifierFlags.contains(.command)
            let shiftReturn = event.keyCode == 36 && event.modifierFlags.contains(.shift)
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, self.panel.isKeyWindow else { return false }

                // Shift+Enter inserts a newline in whichever text field is editing.
                if shiftReturn, let editor = self.panel.firstResponder as? NSTextView {
                    editor.insertNewlineIgnoringFieldEditor(nil)
                    return true
                }
                guard command else { return false }

                // ⌘K works even mid-typing; ⌘C/⌘Z defer to the focused text field.
                if key == "k" {
                    self.model.switcherShown.toggle()
                    return true
                }
                guard !(self.panel.firstResponder is NSTextView) else { return false }

                switch key {
                case "c":
                    let count = self.model.copySelection()
                    guard count > 0 else { return false }
                    ToastPresenter.shared.show(count == 1 ? "Copied" : "Copied \(count) items")
                    return true
                case "z":
                    self.model.undoDelete()
                    return true
                default:
                    return false
                }
            }
            return handled ? nil : event
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
        // The glass shape draws its own edge; the window shadow would outline the
        // full panel rect and read as a second border around it.
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        panel.contentView = NSHostingView(rootView: SheetView(model: model))
        return panel
    }
}
