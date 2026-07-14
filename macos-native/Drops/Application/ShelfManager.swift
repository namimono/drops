import AppKit

/// Owns shelf domain instances and their windows. Does not draw UI itself.
@MainActor
final class ShelfManager {
    static let maxShelves = ShelfLifecycleStore.maxShelves

    private let store = ShelfLifecycleStore()
    private var windows: [ShelfID: ShelfWindowController] = [:]

    var activeCount: Int { store.activeCount }
    var hasActiveExternalDrag: Bool { store.dragSession != nil }

    func shelf(id: ShelfID) -> Shelf? {
        store.shelf(id: id)
    }

    func shouldIgnore(shelfId: ShelfID) -> Bool {
        store.shouldIgnoreEvent(shelfId: shelfId)
    }

    @discardableResult
    func createShelf(
        source: ShelfOpenSource,
        nearMouse: Bool = true,
        mouseOffset: NSPoint = .zero,
        onMilestone: ((ShelfShowMilestone) -> Void)? = nil
    ) -> ShelfID? {
        let dragId = store.dragSession?.id
        let result = store.createShelf(source: source, dragSessionId: dragId)
        guard let shelf = result.shelf else {
            NSLog("[Shelf] create rejected reason=%@", result.rejection?.rawValue ?? "unknown")
            if result.rejection == .maxShelvesReached {
                NSSound.beep()
            }
            return nil
        }

        let controller = ShelfWindowController(shelfID: shelf.id, openSource: source)
        // Unit tests create many shelves; skip chrome animation noise and latency.
        #if DEBUG
        if NSClassFromString("XCTestCase") != nil {
            controller.animatesPresentationChanges = false
        }
        #endif
        wire(controller)
        windows[shelf.id] = controller
        controller.apply(shelf: shelf)
        if nearMouse {
            controller.positionNearMouse(offset: mouseOffset)
        }
        controller.show(onMilestone: onMilestone)
        return shelf.id
    }

    func beginExternalDrag(dragSessionId: DragSessionID) {
        store.beginExternalDrag(dragSessionId: dragSessionId)
    }

    func markDropAccepted(shelfId: ShelfID) {
        guard !store.shouldIgnoreEvent(shelfId: shelfId) else { return }
        let dragId = store.dragSession?.id
        _ = store.markDropAccepted(shelfId: shelfId, dragSessionId: dragId)
        refreshWindow(shelfId: shelfId)
    }

    func endExternalDrag(dragSessionId: DragSessionID) {
        let toClose = store.endExternalDrag(dragSessionId: dragSessionId)
        for id in toClose {
            closeShelf(id: id)
        }
    }

    /// Stage 1: simulate content receive / transient promotion without real pasteboard.
    @discardableResult
    func simulateReceiveContent(shelfId: ShelfID) -> Bool {
        guard !store.shouldIgnoreEvent(shelfId: shelfId) else { return false }
        let ok = store.simulateReceiveContent(shelfId: shelfId)
        if ok { refreshWindow(shelfId: shelfId) }
        return ok
    }

    @discardableResult
    func setPresentation(shelfId: ShelfID, presentation: ShelfPresentation) -> Bool {
        guard !store.shouldIgnoreEvent(shelfId: shelfId) else { return false }
        let ok = store.setPresentation(shelfId: shelfId, presentation: presentation)
        if ok { refreshWindow(shelfId: shelfId) }
        return ok
    }

    func toggleExpand(shelfId: ShelfID) {
        guard let shelf = store.shelf(id: shelfId), shelf.isActive else { return }
        let next: ShelfPresentation
        switch shelf.presentation {
        case .empty:
            next = shelf.isEmpty ? .empty : .expanded
        case .collapsed:
            next = .expanded
        case .expanded:
            next = .collapsed
        }
        _ = setPresentation(shelfId: shelfId, presentation: next)
    }

    func collapse(shelfId: ShelfID) {
        guard let shelf = store.shelf(id: shelfId), !shelf.isEmpty else { return }
        _ = setPresentation(shelfId: shelfId, presentation: .collapsed)
    }

    func closeShelf(id: ShelfID) {
        guard store.beginClose(shelfId: id) else { return }
        if let window = windows.removeValue(forKey: id) {
            window.onClose = nil
            window.close()
        }
        store.markClosed(shelfId: id)
    }

    func closeAll() {
        for id in Array(windows.keys) {
            closeShelf(id: id)
        }
    }

    /// Handles late UI events after the user already closed the window.
    func handleLateEvent(shelfId: ShelfID, _ work: () -> Void) {
        guard !shouldIgnore(shelfId: shelfId) else {
            NSLog("[Shelf] ignored late event for %@", shelfId.rawValue.uuidString)
            return
        }
        work()
    }

    // MARK: - Private

    private func wire(_ controller: ShelfWindowController) {
        let id = controller.shelfID
        controller.onClose = { [weak self] in
            self?.closeShelf(id: id)
        }
        controller.onToggleExpand = { [weak self] in
            self?.handleLateEvent(shelfId: id) {
                self?.toggleExpand(shelfId: id)
            }
        }
        controller.onCollapse = { [weak self] in
            self?.handleLateEvent(shelfId: id) {
                self?.collapse(shelfId: id)
            }
        }
        controller.onSimulateReceive = { [weak self] in
            self?.handleLateEvent(shelfId: id) {
                _ = self?.simulateReceiveContent(shelfId: id)
            }
        }
    }

    private func refreshWindow(shelfId: ShelfID) {
        guard let shelf = store.shelf(id: shelfId),
              let window = windows[shelfId] else { return }
        window.apply(shelf: shelf)
    }
}
