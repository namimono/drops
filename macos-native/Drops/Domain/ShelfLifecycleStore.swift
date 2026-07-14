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

    /// Starts a drag session. Same-ID begin is idempotent. A different ID preempts the
    /// previous session and returns any unaccepted transient shelf that must close.
    @discardableResult
    func beginExternalDrag(dragSessionId: DragSessionID) -> [ShelfID] {
        if let existing = dragSession {
            if existing.id == dragSessionId {
                return []
            }
            let orphaned = unacceptedTransientIDs(for: existing)
            dragSession = DragSessionRecord(id: dragSessionId)
            return orphaned
        }
        dragSession = DragSessionRecord(id: dragSessionId)
        return []
    }

    /// Promotes a transient shelf only when `dragSessionId` matches the shelf association
    /// and the current session is still `.dragging`. Persistent shelves use content APIs instead.
    @discardableResult
    func markDropAccepted(shelfId: ShelfID, dragSessionId: DragSessionID? = nil) -> Bool {
        guard let shelf = shelves[shelfId], shelf.isActive else { return false }
        guard shelf.lifecycle == .transient else { return false }
        guard let dragSessionId,
              shelf.associatedDragSessionId == dragSessionId,
              let drag = dragSession,
              drag.id == dragSessionId,
              drag.state == .dragging else {
            return false
        }
        shelf.markAcceptedDrop()
        return true
    }

    /// Returns shelf ids that should close because transient + no drop.
    func endExternalDrag(dragSessionId: DragSessionID) -> [ShelfID] {
        guard let drag = dragSession, drag.id == dragSessionId else { return [] }
        let toClose = unacceptedTransientIDs(for: drag)
        dragSession = nil
        return toClose
    }

    private func unacceptedTransientIDs(for drag: DragSessionRecord) -> [ShelfID] {
        guard let shakeId = drag.shakeShelfId,
              let shelf = shelves[shakeId],
              shelf.lifecycle == .transient,
              !shelf.acceptedDrop else {
            return []
        }
        return [shakeId]
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
        if shelf.lifecycle == .transient {
            guard let associated = shelf.associatedDragSessionId,
                  let drag = dragSession,
                  drag.id == associated,
                  drag.state == .dragging else {
                return false
            }
        }
        shelf.insertSimulatedItem(named: name)
        if shelf.lifecycle == .transient {
            shelf.markAcceptedDrop()
        }
        return true
    }
}
