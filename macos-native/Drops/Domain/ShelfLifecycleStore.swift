import Foundation

/// Pure lifecycle registry — no AppKit / window dependencies.
final class ShelfLifecycleStore {
    static let maxShelves = 20

    private var shelves: [ShelfID: Shelf] = [:]
    private(set) var dragSession: DragSessionRecord?

    var activeCount: Int {
        shelves.values.filter(\.isActive).count
    }

    func shelf(id: ShelfID) -> Shelf? {
        shelves[id]
    }

    func allShelves() -> [Shelf] {
        Array(shelves.values)
    }

    @discardableResult
    func createShelf(source: ShelfOpenSource, dragSessionId: DragSessionID? = nil) -> ShelfCreateResult {
        if activeCount >= Self.maxShelves {
            return .rejected(.maxShelvesReached)
        }

        if source == .shake {
            guard let drag = dragSession, drag.id == dragSessionId else {
                return .rejected(.noActiveDragSession)
            }
            if drag.shakeShelfId != nil {
                return .rejected(.shakeShelfAlreadyExists)
            }
            if drag.state != .dragging {
                return .rejected(.dragSessionNotActive)
            }
        }

        let lifecycle: ShelfLifecycle = source == .shake ? .transient : .persistent
        let shelf = Shelf(
            source: source,
            lifecycle: lifecycle,
            presentation: .empty,
            associatedDragSessionId: source == .shake ? dragSessionId : nil
        )
        shelves[shelf.id] = shelf

        if source == .shake {
            dragSession?.shakeShelfId = shelf.id
        }

        return .success(shelf)
    }

    func beginExternalDrag(dragSessionId: DragSessionID) {
        dragSession = DragSessionRecord(id: dragSessionId)
    }

    @discardableResult
    func markDropAccepted(shelfId: ShelfID, dragSessionId: DragSessionID? = nil) -> Bool {
        _ = dragSessionId
        guard let shelf = shelves[shelfId], shelf.isActive else { return false }
        shelf.markAcceptedDrop()
        return true
    }

    /// Returns shelf ids that should close because transient + no drop.
    func endExternalDrag(dragSessionId: DragSessionID) -> [ShelfID] {
        guard var drag = dragSession, drag.id == dragSessionId else { return [] }
        drag.state = .finished
        var toClose: [ShelfID] = []
        if let shakeId = drag.shakeShelfId,
           let shelf = shelves[shakeId],
           shelf.lifecycle == .transient,
           !shelf.acceptedDrop {
            toClose.append(shakeId)
        }
        dragSession = nil
        return toClose
    }

    @discardableResult
    func beginClose(shelfId: ShelfID) -> Bool {
        guard let shelf = shelves[shelfId] else { return false }
        if shelf.lifecycle == .closed { return false }
        if shelf.lifecycle == .closing { return true }
        shelf.setLifecycle(.closing)
        return true
    }

    func markClosed(shelfId: ShelfID) {
        shelves.removeValue(forKey: shelfId)
    }

    func shouldIgnoreEvent(shelfId: ShelfID) -> Bool {
        guard let shelf = shelves[shelfId] else { return true }
        return shelf.lifecycle == .closing || shelf.lifecycle == .closed
    }

    @discardableResult
    func setPresentation(shelfId: ShelfID, presentation: ShelfPresentation) -> Bool {
        guard let shelf = shelves[shelfId], shelf.isActive else { return false }
        shelf.setPresentation(presentation)
        return true
    }

    /// Simulated content receive for Stage 1 lifecycle / presentation tests.
    @discardableResult
    func simulateReceiveContent(shelfId: ShelfID, named name: String = "Item") -> Bool {
        guard let shelf = shelves[shelfId], shelf.isActive else { return false }
        shelf.insertSimulatedItem(named: name)
        if shelf.lifecycle == .transient {
            shelf.markAcceptedDrop()
        }
        return true
    }
}
