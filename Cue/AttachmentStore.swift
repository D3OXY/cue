import AppKit
import QuickLookThumbnailing
import UniformTypeIdentifiers

/// File side of attachments. Managed copies live under Application Support/
/// <bundle id>/attachments/<attachment id>; DB rows are the source of truth.
/// Files are only ever removed by the deferred purge (delete ≠ archive).
enum AttachmentStore {
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "Cue", isDirectory: true)
            .appendingPathComponent("attachments", isDirectory: true)
    }

    static func fileURL(for id: String) -> URL {
        directory.appendingPathComponent(id)
    }

    /// Copies a source file into the store under the attachment's id.
    static func adopt(_ source: URL, as id: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: fileURL(for: id))
    }

    static func contentType(of url: URL) -> String {
        (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType?.identifier)
            .flatMap { $0 } ?? UTType.data.identifier
    }

    /// Writes pasted image bytes to a temp file so they can be staged like a file.
    static func writeTempImage(_ data: Data) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cue-pasted-\(UUID().uuidString).png")
        guard let bitmap = NSBitmapImageRep(data: data),
              let png = bitmap.representation(using: .png, properties: [:]) else { return nil }
        do {
            try png.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    static func thumbnail(for url: URL, side: CGFloat = 88) async -> NSImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: side, height: side),
            scale: 2,
            representationTypes: .all
        )
        return try? await QLThumbnailGenerator.shared
            .generateBestRepresentation(for: request)
            .nsImage
    }
}
