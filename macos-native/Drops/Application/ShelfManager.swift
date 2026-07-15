import AppKit

/// Owns shelf domain instances and their windows. Does not draw UI itself.
@MainActor
final class ShelfManager {
    static let maxShelves = ShelfLifecycleStore.maxShelves

    private let store = ShelfLifecycleStore()
    private var windows: [ShelfID: ShelfWindowController] = [:]

    private let temporaryStore: ManagedTemporaryFileStore?
    private let materializer: PasteboardMaterializer?
    private let settings: SettingsStore
    private let itemActions: ItemActionService
    private var textMerge: TextMergeService?
    private(set) var retentionScheduler: RetentionScheduler?
    /// True when Application Support managed storage could not be initialized.
    private(set) var isTemporaryStoreUnavailable = false

    var activeCount: Int { store.activeCount }
    var hasActiveExternalDrag: Bool { store.dragSession != nil }
    var currentDragSessionId: DragSessionID? { store.dragSession?.id }
    var displayMode: ShelfDisplayMode { settings.displayMode }
    /// Shared preferences used by Settings UI and shelf windows.
    var settingsStore: SettingsStore { settings }

    /// Non-blocking user feedback for open/reveal failures (title, message). Override in tests.
    var onUserFacingError: ((String, String) -> Void)?

    init(
        temporaryStore: ManagedTemporaryFileStore? = nil,
        settings: SettingsStore = SettingsStore(),
        itemActions: ItemActionService = ItemActionService()
    ) {
        self.settings = settings
        self.itemActions = itemActions
        if let temporaryStore {
            self.temporaryStore = temporaryStore
            self.materializer = PasteboardMaterializer(temporaryStore: temporaryStore)
            self.textMerge = TextMergeService(temporaryStore: temporaryStore)
            self.retentionScheduler = RetentionScheduler(temporaryStore: temporaryStore)
            self.isTemporaryStoreUnavailable = false
        } else {
            do {
                let created = try ManagedTemporaryFileStore(retentionDays: settings.retentionDays)
                // Drop stale process-local refs left by unclean prior exits.
                created.clearAllShelfReferences()
                self.temporaryStore = created
                self.materializer = PasteboardMaterializer(temporaryStore: created)
                self.textMerge = TextMergeService(temporaryStore: created)
                self.retentionScheduler = RetentionScheduler(temporaryStore: created)
                self.isTemporaryStoreUnavailable = false
            } catch {
                self.temporaryStore = nil
                self.materializer = nil
                self.textMerge = nil
                self.retentionScheduler = nil
                self.isTemporaryStoreUnavailable = true
                NSLog(
                    "[ShelfManager] temporary store init failed; managed paste disabled: %@",
                    "\(error)"
                )
            }
        }
    }

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
        mouseLocation: NSPoint? = nil,
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
        #if DEBUG
        if NSClassFromString("XCTestCase") != nil {
            controller.animatesPresentationChanges = false
        }
        #endif
        wire(controller)
        windows[shelf.id] = controller
        controller.apply(shelf: shelf, displayMode: settings.displayMode)
        if nearMouse {
            controller.positionNearMouse(offset: mouseOffset, mouseLocation: mouseLocation)
        }
        controller.show(onMilestone: onMilestone)
        return shelf.id
    }

    func beginExternalDrag(dragSessionId: DragSessionID) {
        let toClose = store.beginExternalDrag(dragSessionId: dragSessionId)
        for id in toClose {
            closeShelf(id: id)
        }
    }

    func handleShake(at location: NSPoint, dragSessionId: DragSessionID) {
        guard store.dragSession?.id == dragSessionId else { return }
        guard store.dragSession?.shakeShelfId == nil else { return }
        _ = createShelf(
            source: .shake,
            nearMouse: true,
            mouseLocation: location
        )
    }

    func markDropAccepted(shelfId: ShelfID, dragSessionId: DragSessionID? = nil) {
        guard !store.shouldIgnoreEvent(shelfId: shelfId) else { return }
        let dragId = dragSessionId ?? store.dragSession?.id
        _ = store.markDropAccepted(shelfId: shelfId, dragSessionId: dragId)
        refreshWindow(shelfId: shelfId)
    }

    func windowFrame(shelfId: ShelfID) -> NSRect? {
        windows[shelfId]?.frame
    }

    func setAnimatesPresentationChanges(_ enabled: Bool, for shelfId: ShelfID) {
        windows[shelfId]?.animatesPresentationChanges = enabled
    }

    func endExternalDrag(dragSessionId: DragSessionID) {
        let toClose = store.endExternalDrag(dragSessionId: dragSessionId)
        for id in toClose {
            closeShelf(id: id)
        }
    }

    /// Inserts materialized drafts; promotes transient shelves when content arrives.
    /// Commits managed-file references only after a successful insert.
    @discardableResult
    func acceptContent(shelfId: ShelfID, drafts: [ShelfItemDraft]) -> Bool {
        guard !store.shouldIgnoreEvent(shelfId: shelfId),
              let shelf = store.shelf(id: shelfId),
              shelf.isActive,
              !drafts.isEmpty else { return false }

        if shelf.lifecycle == .transient {
            guard let associated = shelf.associatedDragSessionId,
                  let drag = store.dragSession,
                  drag.id == associated,
                  drag.state == .dragging else {
                return false
            }
        }

        let inserted = shelf.insertItems(drafts)
        if shelf.lifecycle == .transient {
            shelf.markAcceptedDrop()
        }
        commitManagedReferences(for: inserted, shelfID: shelfId)
        refreshWindow(shelfId: shelfId)
        return true
    }

    @discardableResult
    func acceptPasteboard(shelfId: ShelfID, pasteboard: NSPasteboard) -> Bool {
        guard !store.shouldIgnoreEvent(shelfId: shelfId) else { return false }
        guard let materializer, let temporaryStore else {
            NSLog("[Shelf] pasteboard accept rejected: temporary store unavailable")
            return false
        }
        do {
            let result = try materializer.materialize(from: pasteboard, shelfID: shelfId)
            let accepted = acceptContent(shelfId: shelfId, drafts: result.drafts)
            if !accepted {
                temporaryStore.discardCreatedFiles(ids: result.newlyCreatedTemporaryFileIDs)
            }
            return accepted
        } catch {
            NSLog("[Shelf] pasteboard materialize failed: %@", "\(error)")
            return false
        }
    }

    @discardableResult
    func removeItems(shelfId: ShelfID, ids: Set<ShelfItemID>) -> Bool {
        guard !store.shouldIgnoreEvent(shelfId: shelfId),
              let shelf = store.shelf(id: shelfId),
              shelf.isActive else { return false }
        let removed = shelf.removeItems(ids: ids)
        releaseReferences(removed, shelfID: shelfId)
        refreshWindow(shelfId: shelfId)
        return !removed.isEmpty
    }

    func applySelection(
        shelfId: ShelfID,
        itemID: ShelfItemID,
        modifiers: SelectionModifiers,
        anchorID: ShelfItemID?
    ) {
        guard !store.shouldIgnoreEvent(shelfId: shelfId),
              let shelf = store.shelf(id: shelfId),
              shelf.isActive else { return }
        shelf.applySelectionClick(itemID: itemID, modifiers: modifiers, anchorID: anchorID)
        // Selection-only: full refresh would reload grid cells and jump itemSize.
        windows[shelfId]?.syncSelection(from: shelf)
    }

    func handleDragOutEnded(
        shelfId: ShelfID,
        itemIDs: Set<ShelfItemID>,
        operation: NSDragOperation
    ) {
        guard !store.shouldIgnoreEvent(shelfId: shelfId) else { return }
        if operation.contains(.move) {
            _ = removeItems(shelfId: shelfId, ids: itemIDs)
        } else {
            // Copy / cancel / other: keep content and selection.
            refreshWindow(shelfId: shelfId)
        }
    }

    func setDisplayMode(_ mode: ShelfDisplayMode) {
        settings.setDisplayMode(mode)
        for id in windows.keys {
            refreshWindow(shelfId: id)
        }
    }

    @discardableResult
    func openSelection(shelfId: ShelfID) -> Bool {
        guard let shelf = activeShelf(id: shelfId) else { return false }
        let targets = shelf.orderedSelection()
        guard let first = targets.first else { return false }
        return open(item: first)
    }

    @discardableResult
    func openItem(shelfId: ShelfID, itemID: ShelfItemID) -> Bool {
        guard let shelf = activeShelf(id: shelfId),
              let item = shelf.items.first(where: { $0.id == itemID }) else { return false }
        return open(item: item)
    }

    @discardableResult
    func revealSelectionInFinder(shelfId: ShelfID) -> Bool {
        guard let shelf = activeShelf(id: shelfId) else { return false }
        let locals = shelf.orderedSelection().filter(\.isLocalFile)
        guard !locals.isEmpty else {
            reportUserFacingError(title: L10n.unableToReveal, message: L10n.revealNeedsLocal)
            return false
        }
        do {
            _ = try itemActions.revealInFinder(locals)
            return true
        } catch {
            let sample = locals.first!
            NSLog("[Shelf] reveal failed: %@", "\(error)")
            reportUserFacingError(
                title: L10n.unableToReveal,
                message: """
                \(L10n.couldNotReveal(sample.displayName))

                \(ItemActionService.recoverySuggestion(for: sample, error: error))
                """
            )
            return false
        }
    }

    private func open(item: ShelfItem) -> Bool {
        do {
            try itemActions.open(item)
            return true
        } catch {
            NSLog("[Shelf] open failed: %@", "\(error)")
            reportUserFacingError(
                title: L10n.unableToOpen,
                message: """
                \(L10n.couldNotOpen(item.displayName))

                \(ItemActionService.recoverySuggestion(for: item, error: error))
                """
            )
            return false
        }
    }

    private func reportUserFacingError(title: String, message: String) {
        NSSound.beep()
        if let onUserFacingError {
            onUserFacingError(title, message)
        } else {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: L10n.ok)
            alert.runModal()
        }
    }

    @discardableResult
    func previewSelection(shelfId: ShelfID) -> Bool {
        guard let shelf = activeShelf(id: shelfId) else { return false }
        let ordered = shelf.orderedSelection()
        return QuickLookPreviewController.shared.preview(
            orderedSelection: ordered,
            becomeActive: { [weak self] in
                self?.windows[shelfId]?.claimKeyFocus()
            }
        ) { [weak self] url in
            do {
                try self?.itemActions.open(
                    ShelfItem(
                        identityKey: url.absoluteString,
                        displayName: url.absoluteString,
                        kind: .link,
                        linkURL: url
                    )
                )
            } catch {
                NSLog("[Shelf] link preview open failed: %@", "\(error)")
                NSSound.beep()
            }
        }
    }

    @discardableResult
    func removeSelection(shelfId: ShelfID) -> Bool {
        guard let shelf = activeShelf(id: shelfId) else { return false }
        let ids = shelf.selection
        guard !ids.isEmpty else { return false }
        return removeItems(shelfId: shelfId, ids: ids)
    }

    /// Menu merge of selected plain-text items (PRD 5.5.1).
    @discardableResult
    func mergeSelectedText(shelfId: ShelfID) -> Bool {
        guard let shelf = activeShelf(id: shelfId), let textMerge else { return false }
        let ordered = shelf.orderedSelection().filter(\.isPlainTextForMerge)
        guard ordered.count >= 2, let anchor = ordered.first else { return false }
        do {
            let draft = try textMerge.mergeMenuSelection(
                ordered,
                displayName: L10n.mergedTextFileName
            )
            let result = shelf.replaceItems(
                removing: Set(ordered.map(\.id)),
                inserting: draft,
                atAnchorID: anchor.id
            )
            releaseReferences(result.removed, shelfID: shelfId)
            commitManagedReferences(for: [result.inserted], shelfID: shelfId)
            refreshWindow(shelfId: shelfId)
            return true
        } catch {
            NSLog("[Shelf] text merge failed: %@", "\(error)")
            NSSound.beep()
            return false
        }
    }

    /// Drag-append merge onto `targetID` (PRD 5.5.2).
    /// `sourceIDs` are the items actually being dragged (not the current selection).
    @discardableResult
    func mergeTextByDrag(
        shelfId: ShelfID,
        targetID: ShelfItemID,
        sourceIDs: Set<ShelfItemID>
    ) -> Bool {
        guard let shelf = activeShelf(id: shelfId), let textMerge else { return false }
        guard let target = shelf.items.first(where: { $0.id == targetID }),
              target.isPlainTextForMerge else { return false }
        let sources = shelf.items.filter {
            sourceIDs.contains($0.id) && $0.id != targetID && $0.isPlainTextForMerge
        }
        guard !sources.isEmpty else { return false }
        do {
            let draft = try textMerge.mergeDragAppend(
                target: target,
                sources: sources,
                displayName: L10n.mergedTextFileName
            )
            var removing = Set(sources.map(\.id))
            removing.insert(target.id)
            let result = shelf.replaceItems(
                removing: removing,
                inserting: draft,
                atAnchorID: target.id
            )
            releaseReferences(result.removed, shelfID: shelfId)
            commitManagedReferences(for: [result.inserted], shelfID: shelfId)
            refreshWindow(shelfId: shelfId)
            return true
        } catch {
            NSLog("[Shelf] drag text merge failed: %@", "\(error)")
            NSSound.beep()
            return false
        }
    }

    func canMergeSelectedText(shelfId: ShelfID) -> Bool {
        guard let shelf = activeShelf(id: shelfId) else { return false }
        let plain = shelf.orderedSelection().filter(\.isPlainTextForMerge)
        return plain.count >= 2
    }

    private func activeShelf(id: ShelfID) -> Shelf? {
        guard !store.shouldIgnoreEvent(shelfId: id),
              let shelf = store.shelf(id: id),
              shelf.isActive else { return nil }
        return shelf
    }

    /// Stage 1 compat: simulate content receive / transient promotion without real pasteboard.
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
        if let shelf = store.shelf(id: id) {
            releaseReferences(shelf.items, shelfID: id)
        }
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

    /// Releases window-owned shelf references before process exit.
    func prepareForTermination() {
        closeAll()
        temporaryStore?.clearAllShelfReferences()
        retentionScheduler?.stop()
    }

    /// Handles late UI events after the user already closed the window.
    func handleLateEvent(shelfId: ShelfID, _ work: () -> Void) {
        guard !shouldIgnore(shelfId: shelfId) else {
            NSLog("[Shelf] ignored late event for %@", shelfId.rawValue.uuidString)
            return
        }
        work()
    }

    @discardableResult
    func updateRetentionDays(_ days: Int) throws -> Int {
        guard let temporaryStore else {
            throw ManagedTemporaryFileStoreError.invalidRetentionDays(days)
        }
        let applied = try settings.setRetentionDays(days)
        try temporaryStore.updateRetentionDays(applied)
        return applied
    }

    var retentionDays: Int { settings.retentionDays }

    @discardableResult
    func cleanupTemporaryFilesNow() throws -> (deleted: [UUID], skippedReferenced: Int) {
        guard let retentionScheduler else {
            throw ManagedTemporaryFileStoreError.deleteFailed(
                URL(fileURLWithPath: "/"),
                "Temporary store unavailable"
            )
        }
        return try retentionScheduler.cleanupNow()
    }

    var managedTemporaryStoreForTesting: ManagedTemporaryFileStore {
        guard let temporaryStore else {
            fatalError("managed temporary store unavailable in this ShelfManager instance")
        }
        return temporaryStore
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
        controller.onPasteboardDrop = { [weak self] pasteboard in
            guard let self else { return false }
            var accepted = false
            self.handleLateEvent(shelfId: id) {
                accepted = self.acceptPasteboard(shelfId: id, pasteboard: pasteboard)
            }
            return accepted
        }
        controller.onPasteRequested = { [weak self] in
            self?.handleLateEvent(shelfId: id) {
                _ = self?.acceptPasteboard(shelfId: id, pasteboard: .general)
            }
        }
        controller.onSelectionClick = { [weak self] itemID, modifiers, anchor in
            self?.handleLateEvent(shelfId: id) {
                self?.applySelection(
                    shelfId: id,
                    itemID: itemID,
                    modifiers: modifiers,
                    anchorID: anchor
                )
            }
        }
        controller.onDragOutEnded = { [weak self] itemIDs, operation in
            self?.handleLateEvent(shelfId: id) {
                self?.handleDragOutEnded(shelfId: id, itemIDs: itemIDs, operation: operation)
            }
        }
        controller.onOpenItem = { [weak self] itemID in
            self?.handleLateEvent(shelfId: id) {
                _ = self?.openItem(shelfId: id, itemID: itemID)
            }
        }
        controller.onPreviewSelection = { [weak self] in
            self?.handleLateEvent(shelfId: id) {
                _ = self?.previewSelection(shelfId: id)
            }
        }
        controller.onRevealSelection = { [weak self] in
            self?.handleLateEvent(shelfId: id) {
                _ = self?.revealSelectionInFinder(shelfId: id)
            }
        }
        controller.onRemoveSelection = { [weak self] in
            self?.handleLateEvent(shelfId: id) {
                _ = self?.removeSelection(shelfId: id)
            }
        }
        controller.onMergeSelection = { [weak self] in
            self?.handleLateEvent(shelfId: id) {
                _ = self?.mergeSelectedText(shelfId: id)
            }
        }
        controller.onMergeDrag = { [weak self] targetID, sourceIDs in
            guard let self else { return false }
            var merged = false
            self.handleLateEvent(shelfId: id) {
                merged = self.mergeTextByDrag(
                    shelfId: id,
                    targetID: targetID,
                    sourceIDs: sourceIDs
                )
            }
            return merged
        }
        controller.onCanMergeSelection = { [weak self] in
            self?.canMergeSelectedText(shelfId: id) ?? false
        }
        controller.onDisplayModeChange = { [weak self] mode in
            self?.setDisplayMode(mode)
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
        window.apply(shelf: shelf, displayMode: settings.displayMode)
    }

    private func commitManagedReferences(for items: [ShelfItem], shelfID: ShelfID) {
        guard let temporaryStore else { return }
        for item in items {
            if let tempID = item.managedTemporaryFileID {
                temporaryStore.addReference(id: tempID, shelfID: shelfID)
            }
        }
    }

    private func releaseReferences(_ items: [ShelfItem], shelfID: ShelfID) {
        guard let temporaryStore else { return }
        for item in items {
            if let tempID = item.managedTemporaryFileID {
                temporaryStore.removeReference(id: tempID, shelfID: shelfID)
            }
        }
    }
}
