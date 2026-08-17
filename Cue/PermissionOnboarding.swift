import AppKit
import SwiftUI

/// First-run Accessibility onboarding: explains why the permission is needed,
/// deep-links to System Settings, and polls until granted. The app still works
/// without it (status-item open), just without double-Shift and selection capture.
@MainActor
final class PermissionOnboarding {
    private var window: NSWindow?
    private var pollTimer: Timer?
    private let onGranted: () -> Void

    init(onGranted: @escaping () -> Void) {
        self.onGranted = onGranted
    }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    func showIfNeeded() {
        guard !Self.isTrusted, window == nil else { return }

        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: OnboardingView(
            openSettings: { Self.openAccessibilitySettings() },
            dismiss: { [weak self] in self?.close() }
        ))
        window.setContentSize(NSSize(width: 420, height: 240))
        window.center()
        self.window = window

        NSApp.activate()
        window.makeKeyAndOrderFront(nil)

        pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor [weak self] in
                guard let self, Self.isTrusted else { return }
                self.close()
                self.onGranted()
            }
        }
    }

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    private func close() {
        pollTimer?.invalidate()
        pollTimer = nil
        window?.close()
        window = nil
    }
}

private struct OnboardingView: View {
    let openSettings: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Cue needs Accessibility access", systemImage: "hand.raised")
                .font(.title3.bold())
            Text("""
            Accessibility access lets Cue detect the double-Shift shortcut anywhere \
            and capture your text selection. Nothing is logged or sent anywhere — \
            everything stays on your Mac.
            """)
            .foregroundStyle(.secondary)
            Spacer()
            HStack {
                Spacer()
                Button("Later", action: dismiss)
                Button("Open System Settings", action: openSettings)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420, height: 240)
    }
}
