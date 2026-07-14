import AppKit
import QuickLookThumbnailing

/// Resolves file icons / SF Symbols for shelf items. Thumbnails are filled asynchronously.
@MainActor
enum ShelfItemIconProvider {
    static func icon(for item: ShelfItem, size: CGFloat) -> NSImage {
        if item.isLink {
            return symbol("link", size: size) ?? fallback(size: size)
        }
        if let fileURL = item.fileURL {
            let image = NSWorkspace.shared.icon(forFile: fileURL.path)
            image.size = NSSize(width: size, height: size)
            return image
        }
        switch item.kind {
        case .folder:
            return symbol("folder.fill", size: size) ?? fallback(size: size)
        case .image:
            return symbol("photo", size: size) ?? fallback(size: size)
        case .text, .rtf, .html:
            return symbol("doc.text", size: size) ?? fallback(size: size)
        case .pdf:
            return symbol("doc.richtext", size: size) ?? fallback(size: size)
        case .sound:
            return symbol("speaker.wave.2.fill", size: size) ?? fallback(size: size)
        default:
            return symbol("doc", size: size) ?? fallback(size: size)
        }
    }

    static func requestThumbnail(
        for item: ShelfItem,
        size: CGFloat,
        completion: @escaping (NSImage?) -> Void
    ) {
        guard let fileURL = item.fileURL, item.kind == .image || item.kind == .pdf else {
            completion(nil)
            return
        }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(
            fileAt: fileURL,
            size: CGSize(width: size, height: size),
            scale: scale,
            representationTypes: .thumbnail
        )
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
            DispatchQueue.main.async {
                completion(representation?.nsImage)
            }
        }
    }

    private static func symbol(_ name: String, size: CGFloat) -> NSImage? {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else {
            return nil
        }
        let config = NSImage.SymbolConfiguration(pointSize: size * 0.72, weight: .regular)
        let configured = image.withSymbolConfiguration(config) ?? image
        configured.size = NSSize(width: size, height: size)
        return configured
    }

    private static func fallback(size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        NSColor.secondaryLabelColor.setFill()
        NSBezierPath(roundedRect: NSRect(x: 2, y: 2, width: size - 4, height: size - 4), xRadius: 4, yRadius: 4).fill()
        image.unlockFocus()
        return image
    }
}
