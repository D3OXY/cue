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

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()

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
        menu.addItem(withTitle: "Quit Cue", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu

        statusItem = item
    }

    @objc private func toggleSheet() {
        sheet.toggle()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Deleted items' files purge only now, so ⌘Z stayed possible all session.
        sheet.model.purgePendingFiles()
    }
}
