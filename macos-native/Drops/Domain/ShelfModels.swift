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

/// Stage 1 placeholder content item. Stage 2 fills real file / pasteboard payloads.
struct ShelfItem: Identifiable, Equatable, Sendable {
    let id: ShelfItemID
    var displayName: String
    var fileURL: URL?

    init(id: ShelfItemID = ShelfItemID(), displayName: String, fileURL: URL? = nil) {
        self.id = id
        self.displayName = displayName
        self.fileURL = fileURL
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

    /// Stage 1 allows simulated inserts so presentation transitions are testable without drag.
    @discardableResult
    func insertSimulatedItem(named name: String) -> ShelfItem {
        let item = ShelfItem(displayName: name)
        items.insert(item, at: 0)
        if presentation == .empty {
            presentation = .collapsed
        }
        return item
    }

    func clearItems() {
        items.removeAll()
        selection.removeAll()
        presentation = .empty
    }

    func setSelection(_ ids: Set<ShelfItemID>) {
        selection = ids.intersection(Set(items.map(\.id)))
    }

    func markAcceptedDrop() {
        acceptedDrop = true
        if lifecycle == .transient {
            lifecycle = .persistent
            associatedDragSessionId = nil
        }
    }
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
