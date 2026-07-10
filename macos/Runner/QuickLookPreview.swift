import AppKit
import QuickLookUI

/// Owns the URLs shown in the shared `QLPreviewPanel` and acts as its
/// data source / delegate. `MainFlutterWindow` accepts panel control and
/// forwards begin/end to this singleton.
final class QuickLookPreviewController: NSObject, QLPreviewPanelDataSource,
    QLPreviewPanelDelegate
{
    static let shared = QuickLookPreviewController()

    private var urls: [NSURL] = []

    private override init() {
        super.init()
    }

    /// Replaces the preview item list. Call before showing the panel.
    func update(urls: [URL]) {
        self.urls = urls.map { $0 as NSURL }
    }

    /// Toggles Quick Look for the given file paths (Finder-style Space).
    /// Returns whether the panel ended up visible.
    @discardableResult
    func toggle(paths: [String]) -> Bool {
        let fileURLs = paths.compactMap { path -> URL? in
            let url = URL(fileURLWithPath: path)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }

        guard !fileURLs.isEmpty else { return false }
        guard let panel = QLPreviewPanel.shared() else { return false }

        if panel.isVisible {
            panel.close()
            return false
        }

        update(urls: fileURLs)
        panel.makeKeyAndOrderFront(nil)
        return true
    }

    // MARK: - QLPreviewPanelDataSource

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        urls.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int)
        -> (any QLPreviewItem)?
    {
        urls[index]
    }
}
