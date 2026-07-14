import Foundation

enum TextMergeError: Error, Equatable, LocalizedError {
    case insufficientPlainTextItems
    case readFailed(String)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .insufficientPlainTextItems:
            return "At least two plain text (.txt) items are required to merge."
        case .readFailed(let path):
            return "Unable to read text file: \(path)"
        case .writeFailed(let message):
            return "Unable to write merged text: \(message)"
        }
    }
}

/// Merges plain-text shelf items into a new managed temporary `.txt` file.
struct TextMergeService {
    static let separator = "\n\n"
    static let defaultMergedFileName = "Merged Text.txt"

    private let temporaryStore: ManagedTemporaryFileStore
    private let fileManager: FileManager

    init(
        temporaryStore: ManagedTemporaryFileStore,
        fileManager: FileManager = .default
    ) {
        self.temporaryStore = temporaryStore
        self.fileManager = fileManager
    }

    /// Menu merge: join selected texts in shelf visual order with blank-line separators.
    func mergeMenuSelection(
        _ items: [ShelfItem],
        displayName: String = Self.defaultMergedFileName
    ) throws -> ShelfItemDraft {
        let plain = items.filter(\.isPlainTextForMerge)
        guard plain.count >= 2 else { throw TextMergeError.insufficientPlainTextItems }
        let contents = try plain.map { try readText(of: $0) }
        return try writeMergedDraft(contents: contents, displayName: displayName)
    }

    /// Drag-merge: target text first, then remaining selected sources in shelf order.
    func mergeDragAppend(
        target: ShelfItem,
        sources: [ShelfItem],
        displayName: String = Self.defaultMergedFileName
    ) throws -> ShelfItemDraft {
        guard target.isPlainTextForMerge else { throw TextMergeError.insufficientPlainTextItems }
        let plainSources = sources.filter { $0.id != target.id && $0.isPlainTextForMerge }
        guard !plainSources.isEmpty else { throw TextMergeError.insufficientPlainTextItems }
        var contents = [try readText(of: target)]
        contents.append(contentsOf: try plainSources.map { try readText(of: $0) })
        return try writeMergedDraft(contents: contents, displayName: displayName)
    }

    // MARK: - Private

    private func readText(of item: ShelfItem) throws -> String {
        guard let url = item.fileURL else {
            throw TextMergeError.readFailed(item.displayName)
        }
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw TextMergeError.readFailed(url.path)
        }
    }

    private func writeMergedDraft(contents: [String], displayName: String) throws -> ShelfItemDraft {
        let joined = contents.joined(separator: Self.separator)
        guard let data = joined.data(using: .utf8) else {
            throw TextMergeError.writeFailed("UTF-8 encoding failed")
        }
        do {
            let created = try temporaryStore.createTemporaryFile(
                named: displayName,
                data: data,
                referencedBy: nil
            )
            return .managed(
                url: created.url,
                displayName: displayName,
                kind: .text,
                temporaryFileID: created.record.id
            )
        } catch {
            throw TextMergeError.writeFailed(error.localizedDescription)
        }
    }
}
