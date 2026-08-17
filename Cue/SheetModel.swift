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

    /// A file waiting in the composer to be attached to the next added item.
    struct Staged: Identifiable {
        let id: String
        let sourceURL: URL
        let originalName: String
        let uti: String
        /// Pasted images live in a temp file we own and clean up on unstage.
        let temporary: Bool
    }

    private struct DeleteBatch {
        let entries: [(item: ItemRecord, attachments: [AttachmentRecord])]
        let purgeID: String
    }

    private static let archiveAfter: TimeInterval = 7 * 86_400
    private static let activeSectionKey = "activeSectionID"

    private let db = Database.open()

    private(set) var sections: [SectionRecord] = []
    private(set) var items: [ItemRecord] = []
    private(set) var hits: [SearchHit] = []
    private(set) var attachmentsByItem: [String: [AttachmentRecord]] = [:]
    private(set) var staged: [Staged] = []

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

    // Deletes are undoable, so their files purge deferred: each batch parks its
    // file URLs here, undo reclaims them, and whatever remains is removed at quit.
    private var undoStack: [DeleteBatch] = []
    private var pendingPurge: [String: [URL]] = [:]

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

        // `# Name` creates-or-switches a section instead of adding an item.
        if trimmed.hasPrefix("#") {
            let name = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { createOrSwitchSection(named: name) }
            return
        }

        // Attachment-only items are fine; empty-and-fileless is not.
        guard !trimmed.isEmpty || !staged.isEmpty else { return }

        let itemID = UUID().uuidString
        let outgoing = staged
        staged = []

        try? db.queue.write { [activeSectionID] db in
            let maxOrder = try Int.fetchOne(
                db, sql: "SELECT IFNULL(MAX(sortOrder), -1) FROM item WHERE sectionId = ?",
                arguments: [activeSectionID]
            ) ?? -1
            try ItemRecord(
                id: itemID,
                sectionId: activeSectionID,
                text: trimmed,
                done: false,
                doneAt: nil,
                createdAt: Date().timeIntervalSince1970,
                sortOrder: maxOrder + 1
            ).insert(db)
            for file in outgoing {
                try AttachmentRecord(
                    id: file.id,
                    itemId: itemID,
                    originalName: file.originalName,
                    uti: file.uti,
                    createdAt: Date().timeIntervalSince1970
                ).insert(db)
            }
        }
        for file in outgoing {
            try? AttachmentStore.adopt(file.sourceURL, as: file.id)
            if file.temporary {
                try? FileManager.default.removeItem(at: file.sourceURL)
            }
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

    /// Copies the selection to the pasteboard: text (single item raw, several as a
    /// numbered list) plus every attached file, so one paste carries both.
    /// Returns how many items were copied.
    func copySelection() -> Int {
        let selected = displayedItems.filter { selection.contains($0.id) }
        guard !selected.isEmpty else { return 0 }

        let withText = selected.filter { !$0.text.isEmpty }
        let text = withText.count == 1
            ? withText[0].text
            : withText.enumerated()
                .map { "\($0.offset + 1). \($0.element.text)" }
                .joined(separator: "\n")

        let files = selected
            .flatMap { attachmentsByItem[$0.id] ?? [] }
            .map { AttachmentStore.fileURL(for: $0.id) as NSURL }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        var objects: [NSPasteboardWriting] = files
        if !text.isEmpty { objects.insert(text as NSString, at: 0) }
        pasteboard.writeObjects(objects)
        return selected.count
    }

    func deleteSelection() {
        let removed = displayedItems.filter { selection.contains($0.id) }
        guard !removed.isEmpty else { return }

        let entries = removed.map { (item: $0, attachments: attachmentsByItem[$0.id] ?? []) }
        try? db.queue.write { db in
            for entry in entries {
                _ = try ItemRecord.deleteOne(db, key: entry.item.id) // attachments cascade
            }
        }

        let purgeID = UUID().uuidString
        pendingPurge[purgeID] = entries.flatMap(\.attachments).map { AttachmentStore.fileURL(for: $0.id) }
        undoStack.append(DeleteBatch(entries: entries, purgeID: purgeID))

        selection.removeAll()
        reloadItems()
        refreshSearch()
    }

    func undoDelete() {
        guard let batch = undoStack.popLast() else { return }
        try? db.queue.write { db in
            for entry in batch.entries {
                try entry.item.insert(db)
                for attachment in entry.attachments {
                    try attachment.insert(db)
                }
            }
        }
        pendingPurge.removeValue(forKey: batch.purgeID)
        reloadItems()
        refreshSearch()
    }

    /// Called at quit: removes files for deletes that were never undone.
    func purgePendingFiles() {
        for url in pendingPurge.values.flatMap({ $0 }) {
            try? FileManager.default.removeItem(at: url)
        }
        pendingPurge.removeAll()
    }

    // MARK: - Staging (composer attachments)

    func stage(urls: [URL]) {
        let files = urls.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false }
        guard !files.isEmpty else { return }
        staged += files.map {
            Staged(
                id: UUID().uuidString,
                sourceURL: $0,
                originalName: $0.lastPathComponent,
                uti: AttachmentStore.contentType(of: $0),
                temporary: false
            )
        }
        ToastPresenter.shared.show(
            files.count == 1 ? "Attached 1 file" : "Attached \(files.count) files",
            systemImage: "paperclip"
        )
    }

    /// Stages pasteboard contents if they're files or an image.
    /// Returns false when it's ordinary text (so the paste proceeds normally).
    func stagePasteboard() -> Bool {
        let pasteboard = NSPasteboard.general
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty {
            stage(urls: urls)
            return true
        }
        if pasteboard.string(forType: .string) == nil,
           let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff),
           let url = AttachmentStore.writeTempImage(data) {
            staged.append(Staged(
                id: UUID().uuidString,
                sourceURL: url,
                originalName: "Pasted image.png",
                uti: "public.png",
                temporary: true
            ))
            ToastPresenter.shared.show("Attached image", systemImage: "paperclip")
            return true
        }
        return false
    }

    func unstage(_ id: String) {
        guard let index = staged.firstIndex(where: { $0.id == id }) else { return }
        let file = staged.remove(at: index)
        if file.temporary {
            try? FileManager.default.removeItem(at: file.sourceURL)
        }
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
        reloadAttachments(for: items.map(\.id))
    }

    private func reloadAttachments(for ids: [String]) {
        guard !ids.isEmpty else {
            attachmentsByItem = [:]
            return
        }
        let all = (try? db.queue.read { db in
            try AttachmentRecord.fetchAll(
                db,
                sql: "SELECT * FROM attachment WHERE itemId IN (\(ids.map { _ in "?" }.joined(separator: ","))) ORDER BY createdAt",
                arguments: .init(ids)
            )
        }) ?? []
        attachmentsByItem = Dictionary(grouping: all, by: \.itemId)
    }

    private func refreshSearch() {
        guard searching, let match = Self.ftsMatch(for: query) else {
            hits = []
            if !searching { reloadAttachments(for: items.map(\.id)) }
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
        reloadAttachments(for: (items + hits.map(\.item)).map(\.id))
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
