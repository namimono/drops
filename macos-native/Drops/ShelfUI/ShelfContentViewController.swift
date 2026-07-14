import AppKit

/// Empty / collapsed / expanded content with Stage 2 drag + Stage 3 browse/actions.
@MainActor
final class ShelfContentViewController: NSViewController, NSDraggingSource {
    var onCloseRequested: (() -> Void)?
    var onToggleExpand: (() -> Void)?
    var onCollapse: (() -> Void)?
    var onPasteboardDrop: ((NSPasteboard) -> Bool)?
    var onPasteRequested: (() -> Void)?
    var onSelectionClick: ((ShelfItemID, SelectionModifiers, ShelfItemID?) -> Void)?
    var onDragOutEnded: ((Set<ShelfItemID>, NSDragOperation) -> Void)?
    var onOpenItem: ((ShelfItemID) -> Void)?
    var onPreviewSelection: (() -> Void)?
    var onRevealSelection: (() -> Void)?
    var onRemoveSelection: (() -> Void)?
    var onMergeSelection: (() -> Void)?
    var onMergeDrag: ((ShelfItemID) -> Bool)?
    var onCanMergeSelection: (() -> Bool)?
    var onDisplayModeChange: ((ShelfDisplayMode) -> Void)?
    /// Debug hook retained for Stage 1 demo menu.
    var onSimulateReceive: (() -> Void)?

    private let titleLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let emptyLabel = NSTextField(wrappingLabelWithString: "")
    private let expandButton = NSButton(title: "Expand", target: nil, action: nil)
    private let collapseButton = NSButton(title: "Collapse", target: nil, action: nil)
    private let closeButton = NSButton(title: "Close", target: nil, action: nil)
    private let gridModeButton = NSButton(title: "Grid", target: nil, action: nil)
    private let listModeButton = NSButton(title: "List", target: nil, action: nil)

    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private var collectionView: NSCollectionView!
    private let collapsedStackView = CollapsedStackView()
    private let stackDragHandle = CollapsedStackDragButton(title: "Drag all", target: nil, action: nil)
    private var languageObserver: NSObjectProtocol?

    private var shelfID: ShelfID?
    private(set) var presentation: ShelfPresentation = .empty
    private var lifecycle: ShelfLifecycle = .persistent
    private(set) var items: [ShelfItem] = []
    private var selection: Set<ShelfItemID> = []
    private var selectionAnchor: ShelfItemID?
    private var displayMode: ShelfDisplayMode = .grid
    private var isReceivingDrag = false
    private var dragOutItemIDs: Set<ShelfItemID> = []

    /// Drag-merge arming (PRD 5.5.2): ~0.45s hover on another plain-text item.
    private var mergeHoverTargetID: ShelfItemID?
    private var mergeArmed = false
    private var mergeHoverTimer: Timer?
    private var dragMonitorTimer: Timer?
    private static let mergeHoverDelay: TimeInterval = 0.45

    override func loadView() {
        let root = DropHostingView(frame: NSRect(x: 0, y: 0, width: 280, height: 220))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.clear.cgColor
        root.owner = self
        view = root
        root.registerForDraggedTypes(PasteboardMaterializer.registeredDragTypes)

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        emptyLabel.font = .systemFont(ofSize: 12)
        emptyLabel.textColor = .labelColor
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        configure(button: closeButton, action: #selector(closeTapped))
        configure(button: expandButton, action: #selector(expandTapped))
        configure(button: collapseButton, action: #selector(collapseTapped))
        configure(button: gridModeButton, action: #selector(gridModeTapped))
        configure(button: listModeButton, action: #selector(listModeTapped))
        configure(button: stackDragHandle, action: nil)
        stackDragHandle.onBeginDrag = { [weak self] event in
            self?.beginCollapsedStackDrag(with: event)
        }
        collapsedStackView.translatesAutoresizingMaskIntoConstraints = false
        collapsedStackView.onBeginDrag = { [weak self] event in
            self?.beginCollapsedStackDrag(with: event)
        }
        collapsedStackView.onExpand = { [weak self] in
            self?.onToggleExpand?()
        }

        configureTable()
        configureCollection()
        applyLocalizedChrome()

        // REV-S3-001: disable autoresizing-mask translation before the view enters the hierarchy.
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.documentView = tableView

        let modeRow = NSStackView(views: [gridModeButton, listModeButton])
        modeRow.orientation = .horizontal
        modeRow.spacing = 4
        modeRow.translatesAutoresizingMaskIntoConstraints = false

        let buttonRow = NSStackView(views: [expandButton, collapseButton, stackDragHandle, modeRow])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8
        buttonRow.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(titleLabel)
        root.addSubview(closeButton)
        root.addSubview(statusLabel)
        root.addSubview(emptyLabel)
        root.addSubview(scrollView)
        root.addSubview(collapsedStackView)
        root.addSubview(buttonRow)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 14),
            titleLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -8),

            closeButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),

            statusLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            statusLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),

            emptyLabel.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: root.centerYAnchor, constant: -8),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: root.leadingAnchor, constant: 20),
            emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -20),

            scrollView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8),
            scrollView.bottomAnchor.constraint(equalTo: buttonRow.topAnchor, constant: -8),

            collapsedStackView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
            collapsedStackView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            collapsedStackView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            collapsedStackView.bottomAnchor.constraint(equalTo: buttonRow.topAnchor, constant: -8),
            collapsedStackView.heightAnchor.constraint(greaterThanOrEqualToConstant: 64),

            buttonRow.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            buttonRow.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -14),
            buttonRow.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -14),
        ])

        languageObserver = NotificationCenter.default.addObserver(
            forName: .dropsLanguageDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyLocalizedChrome()
            self?.refreshLabels()
        }
    }

    deinit {
        if let languageObserver {
            NotificationCenter.default.removeObserver(languageObserver)
        }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        // Persistent shelves take key focus; shake/transient panels stay non-activating.
        if view.window?.styleMask.contains(.nonactivatingPanel) != true {
            view.window?.makeFirstResponder(view)
        }
    }

    func apply(shelf: Shelf, displayMode: ShelfDisplayMode = .grid) {
        shelfID = shelf.id
        presentation = shelf.presentation
        lifecycle = shelf.lifecycle
        items = shelf.items
        selection = shelf.selection
        self.displayMode = displayMode
        // Keep a stable Shift-range anchor across manager→view refreshes.
        if let anchor = selectionAnchor, items.contains(where: { $0.id == anchor }) {
            // keep
        } else if let first = shelf.orderedSelection().first {
            selectionAnchor = first.id
        } else {
            selectionAnchor = nil
        }
        refreshLabels()
        reloadContentViews()
        syncSelectionToViews()
    }

    /// Test seam for selection-anchor stability across `apply(shelf:)`.
    var selectionAnchorForTesting: ShelfItemID? {
        get { selectionAnchor }
        set { selectionAnchor = newValue }
    }

    var hasRegisteredDragTypes: Bool {
        !view.registeredDraggedTypes.isEmpty
    }

    // MARK: - Drag destination

    func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard canAccept(sender) else { return [] }
        isReceivingDrag = true
        view.needsDisplay = true
        return .copy
    }

    func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        canAccept(sender) ? .copy : []
    }

    func draggingExited(_ sender: NSDraggingInfo?) {
        isReceivingDrag = false
        view.needsDisplay = true
    }

    func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        canAccept(sender)
    }

    func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isReceivingDrag = false
        view.needsDisplay = true
        return onPasteboardDrop?(sender.draggingPasteboard) ?? false
    }

    func concludeDragOperation(_ sender: NSDraggingInfo?) {
        isReceivingDrag = false
        view.needsDisplay = true
    }

    func drawDragHighlight(in dirtyRect: NSRect) {
        guard isReceivingDrag else { return }
        NSColor.systemBlue.withAlphaComponent(0.22).setFill()
        dirtyRect.fill()
        NSColor.systemBlue.setStroke()
        let path = NSBezierPath(
            roundedRect: view.bounds.insetBy(dx: 2, dy: 2),
            xRadius: 12,
            yRadius: 12
        )
        path.lineWidth = 2
        path.stroke()
    }

    // MARK: - Drag source

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        [.copy, .move]
    }

    func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
        updateMergeHover(at: screenPoint)
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        stopDragMonitor()
        let insideWindow = view.window?.frame.contains(screenPoint) == true
        if mergeArmed, let target = mergeHoverTargetID, insideWindow {
            let merged = onMergeDrag?(target) ?? false
            clearMergeHover()
            dragOutItemIDs = []
            if merged { return }
        }
        clearMergeHover()
        finishDragOut(operation: operation)
    }

    // MARK: - Paste / keyboard

    @objc func paste(_ sender: Any?) {
        onPasteRequested?()
    }

    override func responds(to aSelector: Selector!) -> Bool {
        if aSelector == #selector(paste(_:)) {
            return true
        }
        return super.responds(to: aSelector)
    }

    func handleKeyDown(_ event: NSEvent) -> Bool {
        guard !items.isEmpty else { return false }
        switch event.keyCode {
        case 49: // Space
            onPreviewSelection?()
            return true
        case 51, 117: // Delete / Forward Delete
            onRemoveSelection?()
            return true
        case 53: // Escape
            if presentation == .expanded {
                onCollapse?()
                return true
            }
            return false
        default:
            return false
        }
    }

    // MARK: - Private

    private func configureTable() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        column.title = "Items"
        column.width = 360
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.delegate = self
        tableView.dataSource = self
        tableView.rowHeight = 28
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .regular
        tableView.allowsMultipleSelection = true
        tableView.setDraggingSourceOperationMask([.copy, .move], forLocal: false)
        tableView.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        tableView.target = self
        tableView.action = #selector(tableClicked)
        tableView.doubleAction = #selector(tableDoubleClicked)
        tableView.menu = NSMenu()
        tableView.menu?.delegate = self
    }

    private func configureCollection() {
        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 120, height: 110)
        layout.minimumInteritemSpacing = 8
        layout.minimumLineSpacing = 8
        layout.sectionInset = NSEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)

        collectionView = NSCollectionView()
        collectionView.collectionViewLayout = layout
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.backgroundColors = [.clear]
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = true
        collectionView.register(
            ShelfGridItemView.self,
            forItemWithIdentifier: ShelfGridItemView.identifier
        )
        collectionView.setDraggingSourceOperationMask([.copy, .move], forLocal: false)
        collectionView.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        collectionView.menu = NSMenu()
        collectionView.menu?.delegate = self
    }

    private func applyLocalizedChrome() {
        expandButton.title = L10n.expand
        collapseButton.title = L10n.collapse
        closeButton.title = L10n.close
        gridModeButton.title = L10n.grid
        listModeButton.title = L10n.list
        stackDragHandle.title = L10n.dragAll
        emptyLabel.stringValue = L10n.emptyDrop

        expandButton.setAccessibilityLabel(L10n.expand)
        collapseButton.setAccessibilityLabel(L10n.collapse)
        closeButton.setAccessibilityLabel(L10n.close)
        gridModeButton.setAccessibilityLabel(L10n.grid)
        listModeButton.setAccessibilityLabel(L10n.list)
        stackDragHandle.setAccessibilityLabel(L10n.dragAll)
        tableView.setAccessibilityLabel(L10n.a11yItemList)
        collectionView?.setAccessibilityLabel(L10n.a11yItemGrid)
        view.setAccessibilityLabel(L10n.a11yShelfWindow)
    }

    private func refreshLabels() {
        let shortID = shelfID.map { String($0.rawValue.uuidString.prefix(8)) } ?? "—"
        titleLabel.stringValue = L10n.shelfTitle(shortID: shortID)
        statusLabel.stringValue = L10n.shelfStatus(
            lifecycle: lifecycle.rawValue,
            presentation: presentation.rawValue,
            count: items.count
        )

        let hasItems = !items.isEmpty
        let isExpanded = presentation == .expanded
        let isCollapsed = presentation == .collapsed
        stackDragHandle.isHidden = !isCollapsed || !hasItems
        gridModeButton.isHidden = !isExpanded
        listModeButton.isHidden = !isExpanded
        gridModeButton.state = displayMode == .grid ? .on : .off
        listModeButton.state = displayMode == .list ? .on : .off

        switch presentation {
        case .empty:
            expandButton.isEnabled = hasItems
            collapseButton.isEnabled = false
            scrollView.isHidden = true
            collapsedStackView.isHidden = true
            emptyLabel.isHidden = false
        case .collapsed:
            expandButton.isEnabled = true
            collapseButton.isEnabled = false
            scrollView.isHidden = true
            collapsedStackView.isHidden = !hasItems
            emptyLabel.isHidden = hasItems
            if hasItems {
                collapsedStackView.apply(items: items)
            }
        case .expanded:
            expandButton.isEnabled = false
            collapseButton.isEnabled = true
            scrollView.isHidden = false
            collapsedStackView.isHidden = true
            emptyLabel.isHidden = true
        }
    }

    private func reloadContentViews() {
        guard presentation == .expanded else { return }
        let useGrid = displayMode == .grid
        if useGrid {
            if scrollView.documentView !== collectionView {
                scrollView.documentView = collectionView
            }
            if let layout = collectionView.collectionViewLayout as? NSCollectionViewFlowLayout {
                // PRD 5.3.2: at most 3 items per row in expanded grid.
                let available = max(scrollView.bounds.width - 16, 280)
                let spacing = layout.minimumInteritemSpacing
                let width = floor((available - spacing * 2) / 3)
                layout.itemSize = NSSize(width: width, height: width + 28)
            }
            collectionView.reloadData()
        } else {
            if scrollView.documentView !== tableView {
                scrollView.documentView = tableView
            }
            tableView.reloadData()
        }
    }

    private func syncSelectionToViews() {
        if scrollView.documentView === tableView {
            tableView.deselectAll(nil)
            for (index, item) in items.enumerated() where selection.contains(item.id) {
                tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: true)
            }
        } else {
            var indexPaths = Set<IndexPath>()
            for (index, item) in items.enumerated() where selection.contains(item.id) {
                indexPaths.insert(IndexPath(item: index, section: 0))
            }
            collectionView.selectionIndexPaths = indexPaths
        }
    }

    private func canAccept(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard
        if pb.canReadObject(forClasses: [NSURL.self], options: nil) { return true }
        for type in PasteboardMaterializer.registeredDragTypes {
            if pb.availableType(from: [type]) != nil { return true }
        }
        return false
    }

    private func configure(button: NSButton, action: Selector?) {
        button.bezelStyle = .inline
        button.font = .systemFont(ofSize: 11, weight: .medium)
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    private func modifiers(from flags: NSEvent.ModifierFlags) -> SelectionModifiers {
        if flags.contains(.shift) { return .range }
        if flags.contains(.command) { return .toggle }
        return .replace
    }

    private func dragPayload(primary: ShelfItem) -> [ShelfItem] {
        if selection.contains(primary.id) {
            return items.filter { selection.contains($0.id) }
        }
        return [primary]
    }

    private func writers(for payload: [ShelfItem]) -> [NSPasteboardWriting] {
        payload.compactMap { pasteboardWriter(for: $0) }
    }

    private func pasteboardWriter(for item: ShelfItem) -> NSPasteboardWriting? {
        if let fileURL = item.fileURL {
            let pbItem = NSPasteboardItem()
            pbItem.setString(fileURL.absoluteString, forType: .fileURL)
            if let managedID = item.managedTemporaryFileID {
                pbItem.setString(
                    managedID.uuidString,
                    forType: PasteboardMaterializer.managedTemporaryFileType
                )
            }
            return pbItem
        }
        if let linkURL = item.linkURL {
            return linkURL as NSURL
        }
        return nil
    }

    private func finishDragOut(operation: NSDragOperation) {
        let ids = dragOutItemIDs
        dragOutItemIDs = []
        onDragOutEnded?(ids, operation)
    }

    private func updateMergeHover(at screenPoint: NSPoint) {
        guard presentation == .expanded,
              let window = view.window,
              window.frame.contains(screenPoint),
              dragOutItemIDs.allSatisfy({ id in items.first(where: { $0.id == id })?.isPlainTextForMerge == true })
        else {
            clearMergeHover()
            return
        }

        let windowPoint = window.convertPoint(fromScreen: screenPoint)
        let local = view.convert(windowPoint, from: nil)
        guard let targetID = itemID(at: local),
              !dragOutItemIDs.contains(targetID),
              items.first(where: { $0.id == targetID })?.isPlainTextForMerge == true
        else {
            clearMergeHover()
            return
        }

        if mergeHoverTargetID == targetID { return }
        mergeHoverTimer?.invalidate()
        mergeHoverTargetID = targetID
        mergeArmed = false
        mergeHoverTimer = Timer.scheduledTimer(withTimeInterval: Self.mergeHoverDelay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.mergeHoverTargetID == targetID else { return }
                self.mergeArmed = true
            }
        }
    }

    private func clearMergeHover() {
        mergeHoverTimer?.invalidate()
        mergeHoverTimer = nil
        mergeHoverTargetID = nil
        mergeArmed = false
    }

    private func startDragMonitor() {
        stopDragMonitor()
        dragMonitorTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateMergeHover(at: NSEvent.mouseLocation)
            }
        }
    }

    private func stopDragMonitor() {
        dragMonitorTimer?.invalidate()
        dragMonitorTimer = nil
    }

    private func itemID(at localPoint: NSPoint) -> ShelfItemID? {
        if scrollView.documentView === tableView {
            let tablePoint = tableView.convert(localPoint, from: view)
            let row = tableView.row(at: tablePoint)
            guard items.indices.contains(row) else { return nil }
            return items[row].id
        }
        let collectionPoint = collectionView.convert(localPoint, from: view)
        if let indexPath = collectionView.indexPathForItem(at: collectionPoint),
           items.indices.contains(indexPath.item) {
            return items[indexPath.item].id
        }
        return nil
    }

    private func selectItem(at index: Int, modifiers mods: SelectionModifiers) {
        guard items.indices.contains(index) else { return }
        let item = items[index]
        if mods != .range {
            selectionAnchor = item.id
        }
        onSelectionClick?(item.id, mods, selectionAnchor)
    }

    /// Index under the current mouse event in the grid; avoids unordered `Set.first` for Shift range.
    private func clickedCollectionIndex() -> Int? {
        guard let event = NSApp.currentEvent else { return nil }
        let location = collectionView.convert(event.locationInWindow, from: nil)
        guard let path = collectionView.indexPathForItem(at: location),
              items.indices.contains(path.item) else { return nil }
        return path.item
    }

    private func contextMenuHitItemID() -> ShelfItemID? {
        if scrollView.documentView === tableView {
            let row = tableView.clickedRow
            guard items.indices.contains(row) else { return nil }
            return items[row].id
        }
        guard let event = NSApp.currentEvent else { return nil }
        let location = collectionView.convert(event.locationInWindow, from: nil)
        if let path = collectionView.indexPathForItem(at: location), items.indices.contains(path.item) {
            return items[path.item].id
        }
        return nil
    }

    /// Applies Finder-style right-click selection before the menu is built (REV-S3-003).
    func prepareContextMenuSelectionForTesting(hitID: ShelfItemID?) {
        prepareContextMenuSelection(hitID: hitID)
    }

    private func prepareContextMenuSelection(hitID: ShelfItemID? = nil) {
        let resolvedHit = hitID ?? contextMenuHitItemID()
        guard let next = ShelfContextMenuSelection.resolved(hitID: resolvedHit, current: selection) else {
            return
        }
        guard next != selection else { return }
        selection = next
        if let only = next.first, next.count == 1 {
            selectionAnchor = only
            onSelectionClick?(only, .replace, only)
        }
    }

    @objc private func closeTapped() { onCloseRequested?() }
    @objc private func expandTapped() { onToggleExpand?() }
    @objc private func collapseTapped() { onCollapse?() }
    @objc private func gridModeTapped() { onDisplayModeChange?(.grid) }
    @objc private func listModeTapped() { onDisplayModeChange?(.list) }

    @objc private func tableClicked() {
        let row = tableView.clickedRow
        guard items.indices.contains(row) else { return }
        selectItem(at: row, modifiers: modifiers(from: NSApp.currentEvent?.modifierFlags ?? []))
    }

    @objc private func tableDoubleClicked() {
        let row = tableView.clickedRow
        guard items.indices.contains(row) else { return }
        onOpenItem?(items[row].id)
    }

    private func beginCollapsedStackDrag(with event: NSEvent) {
        guard presentation == .collapsed, !items.isEmpty else { return }
        let payload = items
        dragOutItemIDs = Set(payload.map(\.id))
        let draggingItems: [NSDraggingItem] = payload.compactMap { item in
            guard let writer = pasteboardWriter(for: item) else { return nil }
            let draggingItem = NSDraggingItem(pasteboardWriter: writer)
            draggingItem.setDraggingFrame(
                NSRect(origin: .zero, size: NSSize(width: 64, height: 64)),
                contents: ShelfItemIconProvider.icon(for: item, size: 48)
            )
            return draggingItem
        }
        guard !draggingItems.isEmpty else { return }
        let session = view.beginDraggingSession(with: draggingItems, event: event, source: self)
        session.draggingFormation = .stack
    }

    private func buildContextMenu() -> NSMenu {
        prepareContextMenuSelection()
        let menu = NSMenu(title: L10n.itemMenu)
        menu.addItem(withTitle: L10n.open, action: #selector(contextOpen), keyEquivalent: "")
        let reveal = menu.addItem(withTitle: L10n.revealInFinder, action: #selector(contextReveal), keyEquivalent: "")
        reveal.isEnabled = selection.contains(where: { id in items.first(where: { $0.id == id })?.isLocalFile == true })
        let canMerge = selection.filter { id in
            items.first(where: { $0.id == id })?.isPlainTextForMerge == true
        }.count >= 2
        if canMerge {
            menu.addItem(withTitle: L10n.mergeText, action: #selector(contextMerge), keyEquivalent: "")
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.remove, action: #selector(contextRemove), keyEquivalent: "")
        for item in menu.items {
            item.target = self
        }
        return menu
    }

    @objc private func contextOpen() {
        if let first = items.first(where: { selection.contains($0.id) }) {
            onOpenItem?(first.id)
        }
    }

    @objc private func contextReveal() { onRevealSelection?() }
    @objc private func contextMerge() { onMergeSelection?() }
    @objc private func contextRemove() { onRemoveSelection?() }
}

// MARK: - Table

extension ShelfContentViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        items.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("cell")
        let cell: ShelfListCellView
        if let reused = tableView.makeView(withIdentifier: identifier, owner: self) as? ShelfListCellView {
            cell = reused
        } else {
            cell = ShelfListCellView()
            cell.identifier = identifier
        }
        cell.configure(item: items[row])
        cell.setAccessibilityLabel(L10n.a11yItem(items[row].displayName))
        return cell
    }

    func tableView(
        _ tableView: NSTableView,
        pasteboardWriterForRow row: Int
    ) -> (any NSPasteboardWriting)? {
        guard items.indices.contains(row) else { return nil }
        let primary = items[row]
        let payload = dragPayload(primary: primary)
        dragOutItemIDs = Set(payload.map(\.id))
        return pasteboardWriter(for: primary)
    }

    func tableView(
        _ tableView: NSTableView,
        draggingSession session: NSDraggingSession,
        willBeginAt screenPoint: NSPoint,
        forRowIndexes rowIndexes: IndexSet
    ) {
        guard let first = rowIndexes.first, items.indices.contains(first) else { return }
        let payload = dragPayload(primary: items[first])
        dragOutItemIDs = Set(payload.map(\.id))
        if payload.count > 1 {
            let pb = session.draggingPasteboard
            pb.clearContents()
            pb.writeObjects(writers(for: payload))
        }
        startDragMonitor()
    }

    func tableView(
        _ tableView: NSTableView,
        draggingSession session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        draggingSession(session, endedAt: screenPoint, operation: operation)
    }

}

// MARK: - Collection (grid)

extension ShelfContentViewController: NSCollectionViewDataSource, NSCollectionViewDelegate {
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        items.count
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        itemForRepresentedObjectAt indexPath: IndexPath
    ) -> NSCollectionViewItem {
        let item = collectionView.makeItem(
            withIdentifier: ShelfGridItemView.identifier,
            for: indexPath
        ) as! ShelfGridItemView
        if items.indices.contains(indexPath.item) {
            let model = items[indexPath.item]
            item.configure(item: model)
            item.view.setAccessibilityLabel(L10n.a11yItem(model.displayName))
            item.view.setAccessibilityRole(.button)
        }
        return item
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        let mods = modifiers(from: NSApp.currentEvent?.modifierFlags ?? [])
        guard let index = ShelfCollectionClickTarget.resolve(
            clickedIndex: clickedCollectionIndex(),
            fallbackIndexPaths: indexPaths
        ), items.indices.contains(index) else { return }
        selectItem(at: index, modifiers: mods)
        if NSApp.currentEvent?.clickCount == 2 {
            onOpenItem?(items[index].id)
        }
    }

    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        // Only Command-click deselect must sync domain; plain/Shift deselects are handled by didSelect.
        let mods = modifiers(from: NSApp.currentEvent?.modifierFlags ?? [])
        guard mods == .toggle else { return }
        guard let index = ShelfCollectionClickTarget.resolve(
            clickedIndex: clickedCollectionIndex(),
            fallbackIndexPaths: indexPaths
        ), items.indices.contains(index) else { return }
        selectItem(at: index, modifiers: .toggle)
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        pasteboardWriterForItemAt indexPath: IndexPath
    ) -> (any NSPasteboardWriting)? {
        guard items.indices.contains(indexPath.item) else { return nil }
        let primary = items[indexPath.item]
        dragOutItemIDs = Set(dragPayload(primary: primary).map(\.id))
        return pasteboardWriter(for: primary)
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        draggingSession session: NSDraggingSession,
        willBeginAt screenPoint: NSPoint,
        forItemsAt indexPaths: Set<IndexPath>
    ) {
        guard let first = indexPaths.first, items.indices.contains(first.item) else { return }
        let payload = dragPayload(primary: items[first.item])
        dragOutItemIDs = Set(payload.map(\.id))
        if payload.count > 1 {
            session.draggingPasteboard.clearContents()
            session.draggingPasteboard.writeObjects(writers(for: payload))
        }
        startDragMonitor()
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        draggingSession session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        dragOperation operation: NSDragOperation
    ) {
        draggingSession(session, endedAt: screenPoint, operation: operation)
    }
}

// MARK: - Context menu

extension ShelfContentViewController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        let built = buildContextMenu()
        menu.removeAllItems()
        for item in built.items {
            built.removeItem(item)
            menu.addItem(item)
        }
    }
}

// MARK: - Hosting / helpers

private final class DropHostingView: NSView {
    weak var owner: ShelfContentViewController?

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        owner?.drawDragHighlight(in: dirtyRect)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        owner?.draggingEntered(sender) ?? []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        owner?.draggingUpdated(sender) ?? []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        owner?.draggingExited(sender)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        owner?.prepareForDragOperation(sender) ?? false
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        owner?.performDragOperation(sender) ?? false
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        owner?.concludeDragOperation(sender)
    }

    override func keyDown(with event: NSEvent) {
        if owner?.handleKeyDown(event) == true { return }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown,
           event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers == "v" {
            owner?.paste(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// Button that starts a dragging session on mouse-drag (collapsed stack affordance).
private final class CollapsedStackDragButton: NSButton {
    var onBeginDrag: ((NSEvent) -> Void)?
    private var mouseDownEvent: NSEvent?

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
    }

    override func mouseDragged(with event: NSEvent) {
        guard let mouseDownEvent else { return }
        let start = mouseDownEvent.locationInWindow
        let current = event.locationInWindow
        let distance = hypot(current.x - start.x, current.y - start.y)
        if distance >= 4 {
            onBeginDrag?(mouseDownEvent)
            self.mouseDownEvent = nil
        }
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownEvent = nil
    }
}

private final class ShelfListCellView: NSTableCellView {
    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private var representedItemID: ShelfItemID?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.font = .systemFont(ofSize: 12)
        addSubview(iconView)
        addSubview(nameLabel)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),
            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            nameLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(item: ShelfItem) {
        representedItemID = item.id
        iconView.image = ShelfItemIconProvider.icon(for: item, size: 18)
        nameLabel.stringValue = item.displayName
        let expectedID = item.id
        ShelfItemIconProvider.requestThumbnail(for: item, size: 18) { [weak self] image in
            guard let self, self.representedItemID == expectedID, let image else { return }
            self.iconView.image = image
        }
    }
}

private final class ShelfGridItemView: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("ShelfGridItemView")

    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private var representedItemID: ShelfItemID?

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.alignment = .center
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.maximumNumberOfLines = 2
        nameLabel.font = .systemFont(ofSize: 11)
        view.addSubview(iconView)
        view.addSubview(nameLabel)
        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            iconView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 48),
            iconView.heightAnchor.constraint(equalToConstant: 48),
            nameLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 6),
            nameLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            nameLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            nameLabel.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -4),
        ])
    }

    func configure(item: ShelfItem) {
        representedItemID = item.id
        iconView.image = ShelfItemIconProvider.icon(for: item, size: 48)
        nameLabel.stringValue = item.displayName
        let expectedID = item.id
        ShelfItemIconProvider.requestThumbnail(for: item, size: 48) { [weak self] image in
            guard let self, self.representedItemID == expectedID, let image else { return }
            self.iconView.image = image
        }
    }

    override var isSelected: Bool {
        didSet {
            view.layer?.backgroundColor = (isSelected
                ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.35)
                : NSColor.clear).cgColor
            view.layer?.cornerRadius = 8
        }
    }
}
