import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let sheet = SheetController()
    private let shiftMonitor = ShiftTapMonitor()
    private lazy var onboarding = PermissionOnboarding { [weak self] in
        self?.shiftMonitor.start()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()

        shiftMonitor.onDoubleShift = { [weak self] in
            self?.sheet.toggle()
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
        menu.addItem(withTitle: "Quit Cue", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu

        statusItem = item
    }

    @objc private func toggleSheet() {
        sheet.toggle()
    }
}
