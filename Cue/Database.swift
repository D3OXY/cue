import Foundation
import GRDB

/// SQLite storage: schema v1 (sections, items, attachments, FTS5) and recovery.
/// DB lives under Application Support/<bundle id>/ so dev and release builds
/// keep separate data.
struct Database {
    /// Fixed UUID so the Inbox section is addressable without a lookup.
    static let inboxID = "00000000-0000-0000-0000-000000000000"

    let queue: DatabaseQueue

    /// Opens the database, migrating as needed. A corrupt or unmigratable file is
    /// moved aside to `cue.sqlite.bak` and a fresh database takes its place.
    static func open() -> Database {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "Cue", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("cue.sqlite")

        do {
            return try Database(path: url.path)
        } catch {
            NSLog("Cue: database unusable (\(error)); moving aside and starting fresh")
            let backup = dir.appendingPathComponent("cue.sqlite.bak")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: url, to: backup)
            return try! Database(path: url.path)
        }
    }

    private init(path: String) throws {
        queue = try DatabaseQueue(path: path)
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.execute(sql: """
                CREATE TABLE section (
                  id TEXT PRIMARY KEY,
                  name TEXT NOT NULL UNIQUE COLLATE NOCASE,
                  createdAt DOUBLE NOT NULL
                );
                CREATE TABLE item (
                  id TEXT PRIMARY KEY,
                  sectionId TEXT NOT NULL REFERENCES section(id),
                  text TEXT NOT NULL,
                  done INTEGER NOT NULL DEFAULT 0,
                  doneAt DOUBLE,
                  createdAt DOUBLE NOT NULL,
                  sortOrder INTEGER NOT NULL
                );
                CREATE TABLE attachment (
                  id TEXT PRIMARY KEY,
                  itemId TEXT NOT NULL REFERENCES item(id) ON DELETE CASCADE,
                  originalName TEXT NOT NULL,
                  uti TEXT NOT NULL,
                  createdAt DOUBLE NOT NULL
                );
                CREATE VIRTUAL TABLE item_fts USING fts5(text, content='item', content_rowid='rowid');
                CREATE TRIGGER item_ai AFTER INSERT ON item BEGIN
                  INSERT INTO item_fts(rowid, text) VALUES (new.rowid, new.text);
                END;
                CREATE TRIGGER item_ad AFTER DELETE ON item BEGIN
                  INSERT INTO item_fts(item_fts, rowid, text) VALUES ('delete', old.rowid, old.text);
                END;
                CREATE TRIGGER item_au AFTER UPDATE OF text ON item BEGIN
                  INSERT INTO item_fts(item_fts, rowid, text) VALUES ('delete', old.rowid, old.text);
                  INSERT INTO item_fts(rowid, text) VALUES (new.rowid, new.text);
                END;
                """)
            try db.execute(
                sql: "INSERT INTO section (id, name, createdAt) VALUES (?, ?, ?)",
                arguments: [Database.inboxID, "Inbox", Date().timeIntervalSince1970]
            )
        }
        try migrator.migrate(queue)
    }
}

struct SectionRecord: Codable, Identifiable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "section"
    var id: String
    var name: String
    var createdAt: Double
}

struct ItemRecord: Codable, Identifiable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "item"
    var id: String
    var sectionId: String
    var text: String
    var done: Bool
    var doneAt: Double?
    var createdAt: Double
    var sortOrder: Int
}

struct AttachmentRecord: Codable, Identifiable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "attachment"
    var id: String
    var itemId: String
    var originalName: String
    var uti: String
    var createdAt: Double
}
