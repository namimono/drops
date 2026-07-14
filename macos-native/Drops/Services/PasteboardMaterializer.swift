import AppKit
import Foundation
import UniformTypeIdentifiers

/// Turns pasteboard / drag payloads into standardized `ShelfItemDraft` values.
/// File URLs stay as external references; non-file content is written into `ManagedTemporaryFileStore`.
/// Newly created managed files are not referenced until the caller commits them (see `acceptContent`).
final class PasteboardMaterializer {
    /// Private type carrying a managed temporary-file record ID across shelf-to-shelf drags.
    static let managedTemporaryFileType = NSPasteboard.PasteboardType("click.shakepin.macos.managed-temporary-file-id")

    private let temporaryStore: ManagedTemporaryFileStore
    private let fileManager: FileManager

    init(temporaryStore: ManagedTemporaryFileStore, fileManager: FileManager = .default) {
        self.temporaryStore = temporaryStore
        self.fileManager = fileManager
    }

    /// Pasteboard types the shelf window registers as a drop destination.
    static let registeredDragTypes: [NSPasteboard.PasteboardType] = [
        managedTemporaryFileType,
        .fileURL,
        .URL,
        .png,
        .tiff,
        .string,
        .rtf,
        .rtfd,
        .html,
        .pdf,
        .tabularText,
        .sound,
        NSPasteboard.PasteboardType("public.file-url"),
        NSPasteboard.PasteboardType(UTType.fileURL.identifier),
        NSPasteboard.PasteboardType(UTType.url.identifier),
    ]

    struct Result: Equatable {
        let drafts: [ShelfItemDraft]
        /// Records created in this batch; discard on failure before content is accepted.
        let newlyCreatedTemporaryFileIDs: [UUID]
    }

    func materialize(from pasteboard: NSPasteboard, shelfID: ShelfID) throws -> Result {
        // shelfID is reserved for callers that scope materialization; references are committed later.
        _ = shelfID
        var drafts: [ShelfItemDraft] = []
        var newlyCreated: [UUID] = []
        var usedNames = Set<String>()

        do {
            for item in pasteboard.pasteboardItems ?? [] {
                let outcome = try materialize(item: item, usedNames: &usedNames)
                guard let outcome else { continue }
                drafts.append(outcome.draft)
                if let created = outcome.newlyCreatedID {
                    newlyCreated.append(created)
                }
            }
            return Result(drafts: drafts, newlyCreatedTemporaryFileIDs: newlyCreated)
        } catch {
            temporaryStore.discardCreatedFiles(ids: newlyCreated)
            throw error
        }
    }

    // MARK: - Private

    private struct ItemOutcome {
        let draft: ShelfItemDraft
        let newlyCreatedID: UUID?
    }

    private func materialize(
        item: NSPasteboardItem,
        usedNames: inout Set<String>
    ) throws -> ItemOutcome? {
        // 1) Explicit managed identity from another Drops shelf.
        if let managed = resolveManagedIdentity(from: item) {
            return ItemOutcome(draft: managed, newlyCreatedID: nil)
        }

        // 2) Local file URL before image previews — Finder often provides both.
        if let fileURL = fileURL(from: item) {
            if let managed = temporaryStore.managedDraft(forFileURL: fileURL) {
                return ItemOutcome(draft: managed, newlyCreatedID: nil)
            }
            var isDir: ObjCBool = false
            _ = fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDir)
            return ItemOutcome(
                draft: .file(url: fileURL, isDirectory: isDir.boolValue),
                newlyCreatedID: nil
            )
        }

        if let urlString = item.string(forType: .URL), let url = URL(string: urlString) {
            if url.isFileURL {
                if let managed = temporaryStore.managedDraft(forFileURL: url) {
                    return ItemOutcome(draft: managed, newlyCreatedID: nil)
                }
                var isDir: ObjCBool = false
                _ = fileManager.fileExists(atPath: url.path, isDirectory: &isDir)
                return ItemOutcome(
                    draft: .file(url: url, isDirectory: isDir.boolValue),
                    newlyCreatedID: nil
                )
            }
            return ItemOutcome(draft: .link(url: url), newlyCreatedID: nil)
        }

        if let imageData = item.data(forType: .tiff) {
            return try writeManaged(
                data: imageData,
                preferredName: uniqueName("Image.tiff", usedNames: &usedNames),
                kind: .image
            )
        }
        if let imageData = item.data(forType: .png) {
            return try writeManaged(
                data: imageData,
                preferredName: uniqueName("Image.png", usedNames: &usedNames),
                kind: .image
            )
        }
        // Prefer explicit RTF/RTFD over AppKit-synthesized plain text.
        if let rtfData = item.data(forType: .rtf) {
            return try writeManaged(
                data: rtfData,
                preferredName: uniqueName("RichText.rtf", usedNames: &usedNames),
                kind: .rtf
            )
        }
        if let rtfdData = item.data(forType: .rtfd) {
            return try writeManaged(
                data: rtfdData,
                preferredName: uniqueName("RichText.rtfd", usedNames: &usedNames),
                kind: .rtf
            )
        }
        // Prefer plain text over HTML — browsers often provide both.
        if let string = item.string(forType: .string) {
            let name = uniqueName(
                Self.fileNameFromText(string, fallback: "Text"),
                usedNames: &usedNames
            )
            return try writeManaged(
                data: Data(string.utf8),
                preferredName: name,
                kind: .text
            )
        }
        if let htmlData = item.data(forType: .html) {
            return try writeManaged(
                data: htmlData,
                preferredName: uniqueName("Page.html", usedNames: &usedNames),
                kind: .html
            )
        }
        if let pdfData = item.data(forType: .pdf) {
            return try writeManaged(
                data: pdfData,
                preferredName: uniqueName("Document.pdf", usedNames: &usedNames),
                kind: .pdf
            )
        }
        if let tabularText = item.string(forType: .tabularText) {
            let name = uniqueName(
                Self.fileNameFromText(tabularText, fallback: "Table"),
                usedNames: &usedNames
            )
            return try writeManaged(
                data: Data(tabularText.utf8),
                preferredName: name,
                kind: .text
            )
        }
        if let soundData = item.data(forType: .sound) {
            return try writeManaged(
                data: soundData,
                preferredName: uniqueName("Sound.aiff", usedNames: &usedNames),
                kind: .sound
            )
        }
        if let fileContents = item.data(forType: .fileContents) {
            return try writeManaged(
                data: fileContents,
                preferredName: uniqueName("File.dat", usedNames: &usedNames),
                kind: .other
            )
        }
        return nil
    }

    private func resolveManagedIdentity(from item: NSPasteboardItem) -> ShelfItemDraft? {
        guard let idString = item.string(forType: Self.managedTemporaryFileType),
              let id = UUID(uuidString: idString),
              let record = temporaryStore.record(for: id) else {
            return nil
        }
        let url = temporaryStore.absoluteURL(for: record)
        return .managed(
            url: url,
            displayName: url.lastPathComponent,
            kind: Self.kind(forFileName: url.lastPathComponent),
            temporaryFileID: id
        )
    }

    private func fileURL(from item: NSPasteboardItem) -> URL? {
        guard let urlString = item.string(forType: .fileURL) else { return nil }
        if let parsed = URL(string: urlString), parsed.isFileURL {
            return parsed
        }
        return URL(fileURLWithPath: urlString)
    }

    private func writeManaged(
        data: Data,
        preferredName: String,
        kind: ShelfItemKind
    ) throws -> ItemOutcome {
        let (url, record) = try temporaryStore.createTemporaryFile(
            named: preferredName,
            data: data,
            referencedBy: nil
        )
        return ItemOutcome(
            draft: .managed(
                url: url,
                displayName: preferredName,
                kind: kind,
                temporaryFileID: record.id
            ),
            newlyCreatedID: record.id
        )
    }

    private func uniqueName(_ preferred: String, usedNames: inout Set<String>) -> String {
        if usedNames.insert(preferred).inserted {
            return preferred
        }
        let base = (preferred as NSString).deletingPathExtension
        let ext = (preferred as NSString).pathExtension
        var index = 2
        while true {
            let candidate = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            if usedNames.insert(candidate).inserted {
                return candidate
            }
            index += 1
        }
    }

    static func fileNameFromText(_ string: String, fallback: String, ext: String = "txt") -> String {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = String(trimmed.prefix(15))

        var sanitized = ""
        for scalar in prefix.unicodeScalars {
            if scalar == "/" || scalar == "\\" || scalar == ":" || scalar.value < 32 {
                continue
            }
            switch scalar {
            case "*", "?", "\"", "<", ">", "|":
                continue
            default:
                sanitized.unicodeScalars.append(scalar)
            }
        }

        let cleaned = sanitized
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let base = cleaned.isEmpty ? fallback : cleaned
        return "\(base).\(ext)"
    }

    static func kind(forFileName name: String) -> ShelfItemKind {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "png", "jpg", "jpeg", "gif", "tiff", "tif", "heic", "webp", "bmp":
            return .image
        case "txt", "text", "md", "csv":
            return .text
        case "rtf", "rtfd":
            return .rtf
        case "html", "htm":
            return .html
        case "pdf":
            return .pdf
        case "aiff", "aif", "wav", "mp3", "m4a":
            return .sound
        default:
            return .file
        }
    }
}
