import Foundation
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

    /// Incremented each time the sheet is presented; the view uses it to refocus the composer.
    var presentation = 0

    /// Set by SheetController; Esc / click-away route through here.
    var requestClose: (() -> Void)?

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
}
