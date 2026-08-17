import AppKit
import ApplicationServices

/// Reads the focused element's selected text via the Accessibility API.
/// AX path only, by design: no ⌘C simulation, so capture never touches the
/// user's clipboard. Apps without AX text support simply return nil.
enum SelectionReader {
    @MainActor
    static func frontmostSelectedText() -> String? {
        let system = AXUIElementCreateSystemWide()

        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            system, kAXFocusedUIElementAttribute as CFString, &focusedRef
        ) == .success, let focusedRef, CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else {
            return nil
        }
        let focused = focusedRef as! AXUIElement

        var selectionRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focused, kAXSelectedTextAttribute as CFString, &selectionRef
        ) == .success, let text = selectionRef as? String else {
            return nil
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
