import AppKit
import Observation

/// In-memory sheet state. SQLite persistence replaces the item array in ticket 8;
/// the search filter becomes FTS5 in ticket 11.
@Observable
@MainActor
final class SheetModel {
    struct Item: Identifiable {
        let id = UUID()
        var text: String
        var done = false
        let createdAt = Date()
    }

    var items: [Item] = []
    var query = ""
    var pinned = false
    var selection = Set<Item.ID>()

    /// Incremented each time the sheet is presented; the view uses it to refocus the composer.
    var presentation = 0

    /// Set by SheetController; Esc / click-away route through here.
    var requestClose: (() -> Void)?

    // Each entry is one delete operation: the removed items with their original indexes.
    private var undoStack: [[(index: Int, item: Item)]] = []

    var visibleItems: [Item] {
        guard !query.isEmpty else { return items }
        return items.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    func add(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        items.append(Item(text: trimmed))
    }

    func toggle(_ id: Item.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].done.toggle()
    }

    // Reorder is only offered while unfiltered, so visible indexes == item indexes.
    func move(from source: IndexSet, to destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
    }

    /// Copies the selection to the pasteboard: single item as raw text, several as
    /// a numbered list (the prompt-routing flow). Returns how many were copied.
    func copySelection() -> Int {
        let selected = visibleItems.filter { selection.contains($0.id) }
        guard !selected.isEmpty else { return 0 }

        let text = selected.count == 1
            ? selected[0].text
            : selected.enumerated()
                .map { "\($0.offset + 1). \($0.element.text)" }
                .joined(separator: "\n")

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        return selected.count
    }

    func deleteSelection() {
        let removed = items.enumerated()
            .filter { selection.contains($0.element.id) }
            .map { (index: $0.offset, item: $0.element) }
        guard !removed.isEmpty else { return }

        items.removeAll { selection.contains($0.id) }
        selection.removeAll()
        undoStack.append(removed)
    }

    func undoDelete() {
        guard let batch = undoStack.popLast() else { return }
        for entry in batch.sorted(by: { $0.index < $1.index }) {
            items.insert(entry.item, at: min(entry.index, items.count))
        }
    }
}
