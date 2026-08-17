import AppKit
import SwiftUI

/// Transient glass pill ("Captured", "Copied 3 items") at the bottom center of
/// the active screen. Non-activating, click-through, auto-dismisses.
@MainActor
final class ToastPresenter {
    static let shared = ToastPresenter()

    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?

    func show(_ text: String, systemImage: String = "checkmark.circle.fill") {
        dismissTask?.cancel()
        panel?.orderOut(nil)

        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true

        // NSHostingView's fitting size is unreliable for measuring the pill, so the
        // panel is a fixed click-through strip and the pill centers itself inside.
        let size = NSSize(width: 480, height: 72)
        panel.setContentSize(size)
        panel.contentView = NSHostingView(rootView: ToastView(text: text, systemImage: systemImage))

        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(
                x: frame.midX - size.width / 2,
                y: frame.minY + 40
            ))
        }

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.animator().alphaValue = 1
        self.panel = panel

        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            self?.fadeOut()
        }
    }

    private func fadeOut() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            panel.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated { panel.orderOut(nil) }
        }
        self.panel = nil
    }
}

private struct ToastView: View {
    let text: String
    let systemImage: String
    @State private var appeared = false

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.callout.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .fixedSize()
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: .capsule)
            .scaleEffect(appeared ? 1 : 0.85)
            .opacity(appeared ? 1 : 0)
            .onAppear {
                withAnimation(.spring(duration: 0.3, bounce: 0.35)) { appeared = true }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
