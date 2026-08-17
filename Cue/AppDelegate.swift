import AppKit
import Sparkle

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let sheet = SheetController()
    private let shiftMonitor = ShiftTapMonitor()
    // Silent auto-update (configured in Info.plist); menu item for manual checks.
    private let updater = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil
    )
    private lazy var onboarding = PermissionOnboarding { [weak self] in
        self?.shiftMonitor.start()
    }

    private static let edgeSwipeKey = "edgeSwipeEnabled"

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()

        EdgeSwipeMonitor.shared.onSwipeIn = { [weak self] in
            self?.sheet.show()
        }
        EdgeSwipeMonitor.shared.onSwipeOut = { [weak self] in
            self?.sheet.hide()
        }
        if UserDefaults.standard.bool(forKey: Self.edgeSwipeKey) {
            EdgeSwipeMonitor.shared.enable()
        }

        shiftMonitor.onDoubleShift = { [weak self] in
            guard let self else { return }
            // With a selection in another app: capture instantly, leave the sheet
            // alone. When Cue itself has focus (typing in the composer), any AX
            // selection is stale — fall through to toggle.
            if !sheet.isKey, let text = SelectionReader.frontmostSelectedText() {
                sheet.model.add(text)
                ToastPresenter.shared.show("Captured")
            } else {
                sheet.toggle()
            }
        }
        if PermissionOnboarding.isTrusted {
            shiftMonitor.start()
        } else {
            onboarding.showIfNeeded()
        }
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "list.bullet.rectangle",
            accessibilityDescription: "Cue"
        )

        let menu = NSMenu()
        let open = NSMenuItem(title: "Open Cue", action: #selector(toggleSheet), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())
        let update = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
            keyEquivalent: ""
        )
        update.target = updater
        menu.addItem(update)
        menu.addItem(.separator())
        let swipe = NSMenuItem(
            title: "Edge Swipe to Open",
            action: #selector(toggleEdgeSwipe(_:)),
            keyEquivalent: ""
        )
        swipe.target = self
        swipe.isEnabled = EdgeSwipeMonitor.shared.available
        swipe.state = UserDefaults.standard.bool(forKey: Self.edgeSwipeKey) ? .on : .off
        menu.addItem(swipe)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Cue", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu

        statusItem = item
    }

    @objc private func toggleSheet() {
        sheet.toggle()
    }

    @objc private func toggleEdgeSwipe(_ sender: NSMenuItem) {
        let enabling = sender.state == .off
        UserDefaults.standard.set(enabling, forKey: Self.edgeSwipeKey)
        sender.state = enabling ? .on : .off

        if enabling {
            EdgeSwipeMonitor.shared.enable()
            // Cue can't consume the system's gesture — the user must turn the
            // Notification Center swipe off or both will fire.
            let alert = NSAlert()
            alert.messageText = "One more step"
            alert.informativeText = """
            Turn off "Notification Center" under System Settings › Trackpad › \
            More Gestures, so the swipe opens Cue instead of Notification Center.
            """
            alert.addButton(withTitle: "Open Trackpad Settings")
            alert.addButton(withTitle: "Done Already")
            NSApp.activate()
            if alert.runModal() == .alertFirstButtonReturn,
               let url = URL(string: "x-apple.systempreferences:com.apple.Trackpad-Settings.extension") {
                NSWorkspace.shared.open(url)
            }
        } else {
            EdgeSwipeMonitor.shared.disable()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Deleted items' files purge only now, so ⌘Z stayed possible all session.
        sheet.model.purgePendingFiles()
    }
}
