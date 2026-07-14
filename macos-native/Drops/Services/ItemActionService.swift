import AppKit

enum ItemActionError: Error, Equatable, LocalizedError {
    case missingTarget
    case fileMissing(String)
    case openFailed(String)
    case revealFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingTarget:
            return "Nothing to open."
        case .fileMissing(let path):
            return "The file is missing: \(path)"
        case .openFailed(let detail):
            return "Unable to open: \(detail)"
        case .revealFailed(let detail):
            return "Unable to reveal in Finder: \(detail)"
        }
    }
}

/// Opens items with the system default app / browser and reveals local files in Finder.
struct ItemActionService {
    private let workspace: NSWorkspace
    private let fileManager: FileManager

    init(workspace: NSWorkspace = .shared, fileManager: FileManager = .default) {
        self.workspace = workspace
        self.fileManager = fileManager
    }

    func open(_ item: ShelfItem) throws {
        if let fileURL = item.fileURL {
            guard fileManager.fileExists(atPath: fileURL.path) else {
                throw ItemActionError.fileMissing(fileURL.path)
            }
            let ok = workspace.open(fileURL)
            if !ok {
                throw ItemActionError.openFailed(fileURL.path)
            }
            return
        }
        if let linkURL = item.linkURL {
            let ok = workspace.open(linkURL)
            if !ok {
                throw ItemActionError.openFailed(linkURL.absoluteString)
            }
            return
        }
        throw ItemActionError.missingTarget
    }

    func openFirst(of items: [ShelfItem]) throws {
        guard let first = items.first else { throw ItemActionError.missingTarget }
        try open(first)
    }

    /// Reveals local file/folder items in Finder. Links are skipped.
    @discardableResult
    func revealInFinder(_ items: [ShelfItem]) throws -> Int {
        let urls = items.compactMap(\.fileURL).filter { fileManager.fileExists(atPath: $0.path) }
        guard !urls.isEmpty else {
            if items.contains(where: \.isLocalFile) {
                throw ItemActionError.fileMissing(items.compactMap(\.fileURL).first?.path ?? "")
            }
            throw ItemActionError.missingTarget
        }
        workspace.activateFileViewerSelecting(urls)
        return urls.count
    }

    /// User-facing recovery hint for open/reveal failures (S3-03).
    static func recoverySuggestion(for item: ShelfItem, error: Error) -> String {
        if let actionError = error as? ItemActionError {
            switch actionError {
            case .fileMissing:
                return L10n.recoveryFileMissing
            case .missingTarget:
                return L10n.recoveryNoTarget
            case .openFailed where item.isLink:
                return L10n.recoveryLink
            case .openFailed:
                return L10n.recoveryDefaultApp
            case .revealFailed:
                return L10n.recoveryReveal
            }
        }
        return L10n.recoveryGeneric
    }
}
