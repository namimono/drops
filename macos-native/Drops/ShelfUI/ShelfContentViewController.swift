import AppKit

/// Empty / collapsed / expanded content with Stage 2 drag-in, paste, selection, and drag-out.
@MainActor
final class ShelfContentViewController: NSViewController, NSDraggingSource {
    var onCloseRequested: (() -> Void)?
    var onToggleExpand: (() -> Void)?
    var onCollapse: (() -> Void)?
    var onPasteboardDrop: ((NSPasteboard) -> Bool)?
    var onPasteRequested: (() -> Void)?
    var onSelectionClick: ((ShelfItemID, SelectionModifiers, ShelfItemID?) -> Void)?
    var onDragOutEnded: ((Set<ShelfItemID>, NSDragOperation) -> Void)?
    /// Debug hook retained for Stage 1 demo menu.
    var onSimulateReceive: (() -> Void)?

    private let titleLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let emptyLabel = NSTextField(wrappingLabelWithString: "")
    private let expandButton = NSButton(title: "Expand", target: nil, action: nil)
    private let collapseButton = NSButton(title: "Collapse", target: nil, action: nil)
    private let closeButton = NSButton(title: "Close", target: nil, action: nil)

    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private let stackDragHandle = CollapsedStackDragButton(title: "Drag all", target: nil, action: nil)

    private var shelfID: ShelfID?
    private(set) var presentation: ShelfPresentation = .empty
    private var lifecycle: ShelfLifecycle = .persistent
    private(set) var items: [ShelfItem] = []
    private var selection: Set<ShelfItemID> = []
    private var selectionAnchor: ShelfItemID?
    private var isReceivingDrag = false
    private var dragOutItemIDs: Set<ShelfItemID> = []

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
        emptyLabel.stringValue = "Drop or paste your items"

        configure(button: closeButton, action: #selector(closeTapped))
        configure(button: expandButton, action: #selector(expandTapped))
        configure(button: collapseButton, action: #selector(collapseTapped))
        configure(button: stackDragHandle, action: nil)
        stackDragHandle.onBeginDrag = { [weak self] event in
            self?.beginCollapsedStackDrag(with: event)
        }

        configureTable()

        let buttonRow = NSStackView(views: [expandButton, collapseButton, stackDragHandle])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8
        buttonRow.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(titleLabel)
        root.addSubview(closeButton)
        root.addSubview(statusLabel)
        root.addSubview(emptyLabel)
        root.addSubview(scrollView)
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

            buttonRow.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            buttonRow.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -14),
            buttonRow.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -14),
        ])
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(view)
    }

    func apply(shelf: Shelf) {
        shelfID = shelf.id
        presentation = shelf.presentation
        lifecycle = shelf.lifecycle
        items = shelf.items
        selection = shelf.selection
        // Keep a stable Shift-range anchor across manager→view refreshes.
        // Only fall back when the previous anchor is missing from the item list.
        if let anchor = selectionAnchor, items.contains(where: { $0.id == anchor }) {
            // keep
        } else if let first = shelf.orderedSelection().first {
            selectionAnchor = first.id
        } else {
            selectionAnchor = nil
        }
        refreshLabels()
        tableView.reloadData()
        syncTableSelection()
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

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        finishDragOut(operation: operation)
    }

    // MARK: - Paste

    @objc func paste(_ sender: Any?) {
        onPasteRequested?()
    }

    override func responds(to aSelector: Selector!) -> Bool {
        if aSelector == #selector(paste(_:)) {
            return true
        }
        return super.responds(to: aSelector)
    }

    // MARK: - Private

    private func configureTable() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        column.title = "Items"
        column.width = 240
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.delegate = self
        tableView.dataSource = self
        tableView.rowHeight = 26
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .regular
        tableView.allowsMultipleSelection = true
        tableView.setDraggingSourceOperationMask([.copy, .move], forLocal: false)
        tableView.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        tableView.target = self
        tableView.action = #selector(tableClicked)

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
    }

    private func refreshLabels() {
        let shortID = shelfID.map { String($0.rawValue.uuidString.prefix(8)) } ?? "—"
        titleLabel.stringValue = "Drops · \(shortID)"
        statusLabel.stringValue = "\(lifecycle.rawValue) · \(presentation.rawValue) · \(items.count) item(s)"

        let hasItems = !items.isEmpty
        stackDragHandle.isHidden = presentation != .collapsed || !hasItems

        switch presentation {
        case .empty:
            expandButton.isEnabled = hasItems
            collapseButton.isEnabled = false
            scrollView.isHidden = true
            emptyLabel.isHidden = false
        case .collapsed:
            expandButton.isEnabled = true
            collapseButton.isEnabled = false
            scrollView.isHidden = false
            emptyLabel.isHidden = true
        case .expanded:
            expandButton.isEnabled = false
            collapseButton.isEnabled = true
            scrollView.isHidden = false
            emptyLabel.isHidden = true
        }
    }

    private func syncTableSelection() {
        tableView.deselectAll(nil)
        for (index, item) in items.enumerated() where selection.contains(item.id) {
            tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: true)
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

    @objc private func closeTapped() { onCloseRequested?() }
    @objc private func expandTapped() { onToggleExpand?() }
    @objc private func collapseTapped() { onCollapse?() }

    @objc private func tableClicked() {
        let row = tableView.clickedRow
        guard items.indices.contains(row) else { return }
        let item = items[row]
        let mods = modifiers(from: NSApp.currentEvent?.modifierFlags ?? [])
        if mods != .range {
            selectionAnchor = item.id
        }
        onSelectionClick?(item.id, mods, selectionAnchor)
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
                contents: nil
            )
            return draggingItem
        }
        guard !draggingItems.isEmpty else { return }
        let session = view.beginDraggingSession(with: draggingItems, event: event, source: self)
        session.draggingFormation = .stack
    }
}

// MARK: - Table

extension ShelfContentViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        items.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("cell")
        let label: NSTextField
        if let reused = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField {
            label = reused
        } else {
            label = NSTextField(labelWithString: "")
            label.identifier = identifier
            label.lineBreakMode = .byTruncatingMiddle
            label.font = .systemFont(ofSize: 12)
        }
        let item = items[row]
        let kindLabel: String
        switch item.kind {
        case .folder: kindLabel = "[Folder] "
        case .link: kindLabel = "[Link] "
        case .image: kindLabel = "[Image] "
        case .text: kindLabel = "[Text] "
        case .pdf: kindLabel = "[PDF] "
        case .rtf: kindLabel = "[RTF] "
        default: kindLabel = ""
        }
        label.stringValue = kindLabel + item.displayName
        return label
    }

    func tableView(
        _ tableView: NSTableView,
        pasteboardWriterForRow row: Int
    ) -> (any NSPasteboardWriting)? {
        guard items.indices.contains(row) else { return nil }
        let primary = items[row]
        let payload = dragPayload(primary: primary)
        dragOutItemIDs = Set(payload.map(\.id))

        // NSTableView asks for one writer per row; multi-item drag is completed in willBegin.
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
        // Replace pasteboard with full selection when multi-drag.
        if payload.count > 1 {
            let pb = session.draggingPasteboard
            pb.clearContents()
            pb.writeObjects(writers(for: payload))
        }
    }

    func tableView(
        _ tableView: NSTableView,
        draggingSession session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        finishDragOut(operation: operation)
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
