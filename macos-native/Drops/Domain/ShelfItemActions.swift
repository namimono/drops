import Foundation

#if canImport(AppKit)
import AppKit
#endif

extension ShelfItem {
    /// Plain-text merge eligibility: local `.txt` (or pasteboard text kind) with a file URL.
    var isPlainTextForMerge: Bool {
        guard linkURL == nil, let fileURL else { return false }
        if kind == .text { return true }
        return fileURL.pathExtension.lowercased() == "txt"
    }

    var isLocalFile: Bool {
        fileURL != nil && linkURL == nil
    }

    var isLink: Bool {
        linkURL != nil
    }
}

/// Pure decision for Space / preview (S3-04): mixed selection prefers local Quick Look.
enum ShelfPreviewDecision: Equatable, Sendable {
    case quickLookLocalFiles([URL])
    case openFirstLink(URL)
    case none

    static func decide(for orderedSelection: [ShelfItem]) -> ShelfPreviewDecision {
        let localURLs = orderedSelection.compactMap(\.fileURL)
        if !localURLs.isEmpty {
            return .quickLookLocalFiles(localURLs)
        }
        if let link = orderedSelection.first(where: { $0.linkURL != nil })?.linkURL {
            return .openFirstLink(link)
        }
        return .none
    }
}

enum ShelfDisplayMode: String, Codable, Sendable, Equatable {
    case grid
    case list
}

/// Right-click selection rule (S3-05): keep multi-select when hitting inside it; otherwise select hit only.
enum ShelfContextMenuSelection {
    static func resolved(hitID: ShelfItemID?, current: Set<ShelfItemID>) -> Set<ShelfItemID>? {
        guard let hitID else { return nil }
        if current.contains(hitID) { return current }
        return [hitID]
    }
}

/// Prefer the concrete click index over an unordered `Set` of collection-view index paths.
enum ShelfCollectionClickTarget {
    static func resolve(clickedIndex: Int?, fallbackIndexPaths: Set<IndexPath>) -> Int? {
        if let clickedIndex { return clickedIndex }
        if fallbackIndexPaths.count == 1 { return fallbackIndexPaths.first?.item }
        return nil
    }
}
