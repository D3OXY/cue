import AppKit
import Observation

/// Sheet state backed by SQLite. All reads/writes are synchronous — the dataset
/// is scratchpad-sized by design (archive keeps the main list short).
@Observable
@MainActor
final class SheetModel {
    /// A search result: search is global (all sections + archive), so each hit
    /// carries where it lives and whether it's archived.
    struct SearchHit: Identifiable {
        let item: ItemRecord
        let sectionName: String
        let archived: Bool
        var id: String { item.id }
    }

    private static let archiveAfter: TimeInterval = 7 * 86_400
    private static let activeSectionKey = "activeSectionID"

    private let db = Database.open()

    private(set) var sections: [SectionRecord] = []
    private(set) var items: [ItemRecord] = []
    private(set) var hits: [SearchHit] = []

    var query = "" {
        didSet { refreshSearch() }
    }
    var pinned = false
    var switcherShown = false
    var selection = Set<String>()

    /// Incremented each time the sheet is presented; the view uses it to refocus the composer.
    var presentation = 0

    /// Set by SheetController; Esc / click-away route through here.
    var requestClose: (() -> Void)?

    // Each entry is one delete operation (the removed records), for ⌘Z.
    private var undoStack: [[ItemRecord]] = []

    var activeSectionID: String {
        didSet {
            UserDefaults.standard.set(activeSectionID, forKey: Self.activeSectionKey)
            reloadItems()
        }
    }

    var activeSection: SectionRecord? { sections.first { $0.id == activeSectionID } }
    var searching: Bool { !query.isEmpty }

    /// The items currently on screen, in display order (list or search results).
    var displayedItems: [ItemRecord] { searching ? hits.map(\.item) : items }

    init() {
        activeSectionID = UserDefaults.standard.string(forKey: Self.activeSectionKey) ?? Database.inboxID
        reloadSections()
        if !sections.contains(where: { $0.id == activeSectionID }) {
            activeSectionID = Database.inboxID
        }
        reloadItems()
    }

    private var archiveCutoff: Double { Date().timeIntervalSince1970 - Self.archiveAfter }

    // MARK: - Items

    func add(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // `# Name` creates-or-switches a section instead of adding an item.
        if trimmed.hasPrefix("#") {
            let name = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { createOrSwitchSection(named: name) }
            return
        }

        try? db.queue.write { [activeSectionID] db in
            let maxOrder = try Int.fetchOne(
                db, sql: "SELECT IFNULL(MAX(sortOrder), -1) FROM item WHERE sectionId = ?",
                arguments: [activeSectionID]
            ) ?? -1
            try ItemRecord(
                id: UUID().uuidString,
                sectionId: activeSectionID,
                text: trimmed,
                done: false,
                doneAt: nil,
                createdAt: Date().timeIntervalSince1970,
                sortOrder: maxOrder + 1
            ).insert(db)
        }
        reloadItems()
    }

    func toggle(_ id: String) {
        try? db.queue.write { db in
            guard var item = try ItemRecord.fetchOne(db, key: id) else { return }
            item.done.toggle()
            item.doneAt = item.done ? Date().timeIntervalSince1970 : nil
            try item.update(db)
        }
        reloadItems()
        refreshSearch()
    }

    // Reorder is only offered on the unfiltered list, so indexes match `items`.
    func move(from source: IndexSet, to destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
        try? db.queue.write { [items] db in
            for (index, item) in items.enumerated() where item.sortOrder != index {
                try db.execute(
                    sql: "UPDATE item SET sortOrder = ? WHERE id = ?",
                    arguments: [index, item.id]
                )
            }
        }
        reloadItems()
    }

    /// Copies the selection to the pasteboard: single item as raw text, several as
    /// a numbered list (the prompt-routing flow). Returns how many were copied.
    func copySelection() -> Int {
        let selected = displayedItems.filter { selection.contains($0.id) }
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
        let removed = displayedItems.filter { selection.contains($0.id) }
        guard !removed.isEmpty else { return }

        try? db.queue.write { db in
            for item in removed {
                _ = try ItemRecord.deleteOne(db, key: item.id)
            }
        }
        selection.removeAll()
        undoStack.append(removed)
        reloadItems()
        refreshSearch()
    }

    func undoDelete() {
        guard let batch = undoStack.popLast() else { return }
        try? db.queue.write { db in
            for item in batch {
                try item.insert(db)
            }
        }
        reloadItems()
        refreshSearch()
    }

    // MARK: - Sections

    func createOrSwitchSection(named name: String) {
        if let existing = sections.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            activeSectionID = existing.id
        } else {
            let section = SectionRecord(id: UUID().uuidString, name: name, createdAt: Date().timeIntervalSince1970)
            try? db.queue.write { try section.insert($0) }
            reloadSections()
            activeSectionID = section.id
        }
        switcherShown = false
    }

    func switchSection(_ id: String) {
        activeSectionID = id
        switcherShown = false
    }

    func renameActiveSection(to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, activeSectionID != Database.inboxID else { return }
        try? db.queue.write { [activeSectionID] db in
            try db.execute(sql: "UPDATE section SET name = ? WHERE id = ?", arguments: [trimmed, activeSectionID])
        }
        reloadSections()
    }

    /// Non-destructive: the section's items move to Inbox.
    func deleteSection(_ id: String) {
        guard id != Database.inboxID else { return }
        try? db.queue.write { db in
            try db.execute(sql: "UPDATE item SET sectionId = ? WHERE sectionId = ?", arguments: [Database.inboxID, id])
            _ = try SectionRecord.deleteOne(db, key: id)
        }
        reloadSections()
        if activeSectionID == id {
            activeSectionID = Database.inboxID
        } else {
            reloadItems()
        }
    }

    // MARK: - Loading

    private func reloadSections() {
        sections = (try? db.queue.read {
            try SectionRecord.fetchAll($0, sql: "SELECT * FROM section ORDER BY createdAt")
        }) ?? []
    }

    private func reloadItems() {
        items = (try? db.queue.read { [activeSectionID, archiveCutoff] db in
            try ItemRecord.fetchAll(
                db,
                sql: """
                    SELECT * FROM item
                    WHERE sectionId = ? AND (done = 0 OR doneAt IS NULL OR doneAt > ?)
                    ORDER BY sortOrder
                    """,
                arguments: [activeSectionID, archiveCutoff]
            )
        }) ?? []
    }

    private func refreshSearch() {
        guard searching, let match = Self.ftsMatch(for: query) else {
            hits = []
            return
        }
        let cutoff = archiveCutoff
        hits = (try? db.queue.read { db in
            try ItemRecord
                .fetchAll(
                    db,
                    sql: """
                        SELECT item.* FROM item
                        JOIN item_fts ON item_fts.rowid = item.rowid
                        WHERE item_fts MATCH ?
                        ORDER BY item.createdAt DESC
                        """,
                    arguments: [match]
                )
                .map { item in
                    let name = try? String.fetchOne(
                        db, sql: "SELECT name FROM section WHERE id = ?", arguments: [item.sectionId]
                    )
                    return SearchHit(
                        item: item,
                        sectionName: name ?? "Inbox",
                        archived: item.done && (item.doneAt ?? .infinity) <= cutoff
                    )
                }
        }) ?? []
    }

    /// Builds a prefix-matching FTS5 query, quoting tokens so user input can't
    /// hit FTS syntax errors. Returns nil when nothing searchable remains.
    private static func ftsMatch(for query: String) -> String? {
        let tokens = query
            .components(separatedBy: .alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .map { "\"\($0)\"*" }
        return tokens.isEmpty ? nil : tokens.joined(separator: " ")
    }
}
