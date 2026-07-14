import Foundation

enum ShelfItemKind: String, Codable, Sendable, Equatable {
    case file
    case folder
    case link
    case text
    case image
    case rtf
    case html
    case pdf
    case sound
    case other
}

/// Draft produced by pasteboard / drag materialization before domain insert.
struct ShelfItemDraft: Equatable, Sendable {
    let identityKey: String
    let displayName: String
    let kind: ShelfItemKind
    /// Local file or managed temporary file URL. Nil for web links.
    let fileURL: URL?
    /// Web / remote URL when `kind == .link`.
    let linkURL: URL?
    let managedTemporaryFileID: UUID?

    static func file(url: URL, isDirectory: Bool) -> ShelfItemDraft {
        let standardized = url.standardizedFileURL
        return ShelfItemDraft(
            identityKey: standardized.path,
            displayName: standardized.lastPathComponent,
            kind: isDirectory ? .folder : .file,
            fileURL: standardized,
            linkURL: nil,
            managedTemporaryFileID: nil
        )
    }

    static func link(url: URL) -> ShelfItemDraft {
        ShelfItemDraft(
            identityKey: url.absoluteString,
            displayName: url.absoluteString,
            kind: .link,
            fileURL: nil,
            linkURL: url,
            managedTemporaryFileID: nil
        )
    }

    static func managed(
        url: URL,
        displayName: String,
        kind: ShelfItemKind,
        temporaryFileID: UUID
    ) -> ShelfItemDraft {
        let standardized = url.standardizedFileURL
        return ShelfItemDraft(
            identityKey: standardized.path,
            displayName: displayName,
            kind: kind,
            fileURL: standardized,
            linkURL: nil,
            managedTemporaryFileID: temporaryFileID
        )
    }
}
