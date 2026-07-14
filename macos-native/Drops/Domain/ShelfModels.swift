import Foundation

enum ShelfOpenSource: String, Codable, Sendable, Equatable {
    case hotkey
    case menu
    case shake
}

enum ShelfLifecycle: String, Codable, Sendable, Equatable {
    case creating
    case transient
    case persistent
    case closing
    case closed

    var isActive: Bool {
        self != .closing && self != .closed
    }
}

/// Presentation is independent of lifecycle (README §6.2).
enum ShelfPresentation: String, Codable, Sendable, Equatable {
    case empty
    case collapsed
    case expanded
}

struct ShelfItemID: Hashable, Codable, Sendable {
    let rawValue: UUID

    init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

struct ShelfItem: Identifiable, Equatable, Sendable {
    let id: ShelfItemID
    /// Stable dedup key: standardized file path or link absoluteString.
    let identityKey: String
    var displayName: String
    var kind: ShelfItemKind
    var fileURL: URL?
    var linkURL: URL?
    var managedTemporaryFileID: UUID?

    init(
        id: ShelfItemID = ShelfItemID(),
        identityKey: String,
        displayName: String,
        kind: ShelfItemKind,
        fileURL: URL? = nil,
        linkURL: URL? = nil,
        managedTemporaryFileID: UUID? = nil
    ) {
        self.id = id
        self.identityKey = identityKey
        self.displayName = displayName
        self.kind = kind
        self.fileURL = fileURL
        self.linkURL = linkURL
        self.managedTemporaryFileID = managedTemporaryFileID
    }

    /// Pasteboard / Finder path used for drag-out writers.
    var dragOutPath: String? {
        if let fileURL { return fileURL.path }
        if let linkURL { return linkURL.absoluteString }
        return nil
    }

    init(from draft: ShelfItemDraft, id: ShelfItemID = ShelfItemID()) {
        self.init(
            id: id,
            identityKey: draft.identityKey,
            displayName: draft.displayName,
            kind: draft.kind,
            fileURL: draft.fileURL,
            linkURL: draft.linkURL,
            managedTemporaryFileID: draft.managedTemporaryFileID
        )
    }
}

enum DragSessionState: String, Codable, Sendable, Equatable {
    case idle
    case dragging
    case finishing
    case finished
}

struct DragSessionID: Hashable, Codable, Sendable {
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

struct DragSessionRecord: Equatable, Sendable {
    let id: DragSessionID
    var state: DragSessionState
    var shakeShelfId: ShelfID?
    let startedAt: Date

    init(id: DragSessionID, startedAt: Date = Date()) {
        self.id = id
        self.state = .dragging
        self.shakeShelfId = nil
        self.startedAt = startedAt
    }
}

/// Per-shelf domain aggregate. Window chrome must not own this state.
final class Shelf: @unchecked Sendable {
    let id: ShelfID
    let source: ShelfOpenSource
    let createdAt: Date

    private(set) var lifecycle: ShelfLifecycle
    private(set) var presentation: ShelfPresentation
    private(set) var items: [ShelfItem]
    private(set) var selection: Set<ShelfItemID>
    private(set) var associatedDragSessionId: DragSessionID?
    private(set) var acceptedDrop: Bool

    init(
        id: ShelfID = ShelfID(),
        source: ShelfOpenSource,
        lifecycle: ShelfLifecycle,
        presentation: ShelfPresentation = .empty,
        associatedDragSessionId: DragSessionID? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.source = source
        self.lifecycle = lifecycle
        self.presentation = presentation
        self.items = []
        self.selection = []
        self.associatedDragSessionId = associatedDragSessionId
        self.acceptedDrop = false
        self.createdAt = createdAt
    }

    var isActive: Bool { lifecycle.isActive }

    var isEmpty: Bool { items.isEmpty }

    func setLifecycle(_ next: ShelfLifecycle) {
        lifecycle = next
    }

    func setPresentation(_ next: ShelfPresentation) {
        presentation = next
    }

    /// Stage 1/tests: simulated insert without pasteboard.
    @discardableResult
    func insertSimulatedItem(named name: String) -> ShelfItem {
        let draft = ShelfItemDraft(
            identityKey: "simulated:\(name):\(UUID().uuidString)",
            displayName: name,
            kind: .other,
            fileURL: nil,
            linkURL: nil,
            managedTemporaryFileID: nil
        )
        return insertItems([draft]).first!
    }

    /// Inserts drafts newest-first with path/URL identity dedup. Existing matches move to front.
    /// Newly inserted or moved items join the selection set (PRD 5.4.1).
    @discardableResult
    func insertItems(_ drafts: [ShelfItemDraft]) -> [ShelfItem] {
        guard !drafts.isEmpty else { return [] }

        var seenKeys = Set<String>()
        var uniqueDrafts: [ShelfItemDraft] = []
        for draft in drafts {
            if seenKeys.insert(draft.identityKey).inserted {
                uniqueDrafts.append(draft)
            }
        }

        var existingByKey = Dictionary(uniqueKeysWithValues: items.map { ($0.identityKey, $0) })
        var front: [ShelfItem] = []
        for draft in uniqueDrafts {
            if let existing = existingByKey.removeValue(forKey: draft.identityKey) {
                front.append(existing)
            } else {
                front.append(ShelfItem(from: draft))
            }
        }

        let frontKeys = Set(front.map(\.identityKey))
        let rest = items.filter { !frontKeys.contains($0.identityKey) }
        items = front + rest
        selection.formUnion(Set(front.map(\.id)))
        if presentation == .empty {
            presentation = .collapsed
        }
        return front
    }

    @discardableResult
    func removeItems(ids: Set<ShelfItemID>) -> [ShelfItem] {
        guard !ids.isEmpty else { return [] }
        let removed = items.filter { ids.contains($0.id) }
        items.removeAll { ids.contains($0.id) }
        selection.subtract(ids)
        if items.isEmpty {
            presentation = .empty
            selection.removeAll()
        }
        return removed
    }

    @discardableResult
    func removeItems(identityKeys: Set<String>) -> [ShelfItem] {
        let ids = Set(items.filter { identityKeys.contains($0.identityKey) }.map(\.id))
        return removeItems(ids: ids)
    }

    @discardableResult
    func clearItems() -> [ShelfItem] {
        let removed = items
        items.removeAll()
        selection.removeAll()
        presentation = .empty
        return removed
    }

    func setSelection(_ ids: Set<ShelfItemID>) {
        selection = ids.intersection(Set(items.map(\.id)))
    }

    /// Click: replace selection. Command: toggle. Shift: range from anchor.
    func applySelectionClick(itemID: ShelfItemID, modifiers: SelectionModifiers, anchorID: ShelfItemID?) {
        guard items.contains(where: { $0.id == itemID }) else { return }
        switch modifiers {
        case .replace:
            selection = [itemID]
        case .toggle:
            if selection.contains(itemID) {
                selection.remove(itemID)
            } else {
                selection.insert(itemID)
            }
        case .range:
            let anchor = anchorID.flatMap { id in items.firstIndex(where: { $0.id == id }) }
                ?? items.firstIndex(where: { $0.id == itemID })!
            let target = items.firstIndex(where: { $0.id == itemID })!
            let lower = min(anchor, target)
            let upper = max(anchor, target)
            selection = Set(items[lower...upper].map(\.id))
        }
    }

    func orderedSelection() -> [ShelfItem] {
        items.filter { selection.contains($0.id) }
    }

    /// Drag-out payload: unselected single → that item; selected → all selected; collapsed stack → all.
    func itemsForDragOut(primaryItemID: ShelfItemID?, draggingCollapsedStack: Bool) -> [ShelfItem] {
        if draggingCollapsedStack {
            return items
        }
        guard let primaryItemID else { return orderedSelection() }
        if selection.contains(primaryItemID) {
            return orderedSelection()
        }
        return items.filter { $0.id == primaryItemID }
    }

    func markAcceptedDrop() {
        acceptedDrop = true
        if lifecycle == .transient {
            lifecycle = .persistent
            associatedDragSessionId = nil
        }
    }
}

enum SelectionModifiers: Equatable, Sendable {
    case replace
    case toggle
    case range
}

enum ShelfCreateRejection: String, Equatable, Sendable {
    case maxShelvesReached = "max_shelves_reached"
    case noActiveDragSession = "no_active_drag_session"
    case shakeShelfAlreadyExists = "shake_shelf_already_exists"
    case dragSessionNotActive = "drag_session_not_active"
}

struct ShelfCreateResult {
    let shelf: Shelf?
    let rejection: ShelfCreateRejection?

    var isSuccess: Bool { shelf != nil }

    static func success(_ shelf: Shelf) -> ShelfCreateResult {
        ShelfCreateResult(shelf: shelf, rejection: nil)
    }

    static func rejected(_ reason: ShelfCreateRejection) -> ShelfCreateResult {
        ShelfCreateResult(shelf: nil, rejection: reason)
    }
}
