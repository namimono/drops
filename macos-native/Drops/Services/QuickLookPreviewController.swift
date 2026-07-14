import AppKit
import QuickLookUI

/// Owns URLs shown in the shared `QLPreviewPanel` (Finder-style Space preview).
final class QuickLookPreviewController: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookPreviewController()

    private var urls: [NSURL] = []
    private let fileManager: FileManager
    private let lock = NSLock()

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        super.init()
    }

    /// Applies S3-04 decision, then toggles Quick Look or opens the first link.
    @MainActor
    @discardableResult
    func preview(orderedSelection: [ShelfItem], openLink: (URL) -> Void) -> Bool {
        switch ShelfPreviewDecision.decide(for: orderedSelection) {
        case .quickLookLocalFiles(let candidates):
            let existing = candidates.filter { fileManager.fileExists(atPath: $0.path) }
            guard !existing.isEmpty else { return false }
            return toggle(urls: existing)
        case .openFirstLink(let url):
            openLink(url)
            return true
        case .none:
            return false
        }
    }

    @MainActor
    @discardableResult
    func toggle(urls fileURLs: [URL]) -> Bool {
        guard !fileURLs.isEmpty else { return false }
        guard let panel = QLPreviewPanel.shared() else { return false }

        if panel.isVisible {
            panel.close()
            return false
        }

        lock.lock()
        urls = fileURLs.map { $0 as NSURL }
        lock.unlock()
        if panel.dataSource !== self {
            panel.dataSource = self
            panel.delegate = self
        }
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
        return true
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return urls.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)? {
        lock.lock()
        defer { lock.unlock() }
        guard urls.indices.contains(index) else { return nil }
        return urls[index]
    }
}
