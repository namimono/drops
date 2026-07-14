import AppKit
import QuickLookUI

/// Owns URLs for the shared in-process `QLPreviewPanel`.
///
/// Data source/delegate must only be assigned from `beginPreviewPanelControl`
/// (via a responder in the shelf chain). Setting them earlier triggers QLError
/// and lets Space fall through to whichever app is active (often Finder).
final class QuickLookPreviewController: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookPreviewController()

    private var urls: [NSURL] = []
    private let fileManager: FileManager
    private let lock = NSLock()

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        super.init()
    }

    var hasPreviewItems: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !urls.isEmpty
    }

    /// Applies S3-04 decision, then toggles Quick Look or opens the first link.
    /// - Parameter becomeActive: Called before opening QL so Space is not delivered to Finder.
    @MainActor
    @discardableResult
    func preview(
        orderedSelection: [ShelfItem],
        becomeActive: (() -> Void)? = nil,
        openLink: (URL) -> Void
    ) -> Bool {
        switch ShelfPreviewDecision.decide(for: orderedSelection) {
        case .quickLookLocalFiles(let candidates):
            let existing = candidates.filter { fileManager.fileExists(atPath: $0.path) }
            guard !existing.isEmpty else { return false }
            return toggle(urls: existing, becomeActive: becomeActive)
        case .openFirstLink(let url):
            openLink(url)
            return true
        case .none:
            return false
        }
    }

    /// Updates preview URLs used when this process becomes the panel controller.
    func setPreviewURLs(_ fileURLs: [URL]) {
        lock.lock()
        urls = fileURLs.map { $0 as NSURL }
        lock.unlock()
    }

    @MainActor
    @discardableResult
    func toggle(urls fileURLs: [URL], becomeActive: (() -> Void)? = nil) -> Bool {
        guard !fileURLs.isEmpty else { return false }
        guard let panel = QLPreviewPanel.shared() else { return false }

        setPreviewURLs(fileURLs)

        // Closing our visible panel (Space toggle).
        if panel.isVisible, panel.dataSource === self {
            panel.close()
            return false
        }

        // Claim app focus before updateController walks the responder chain.
        becomeActive?()
        panel.updateController()
        if panel.isVisible {
            panel.reloadData()
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
        return true
    }

    /// Attach as data source only while a shelf responder controls the panel.
    func attach(to panel: QLPreviewPanel) {
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
    }

    func detach(from panel: QLPreviewPanel) {
        if panel.dataSource === self {
            panel.dataSource = nil
        }
        if panel.delegate === self {
            panel.delegate = nil
        }
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
