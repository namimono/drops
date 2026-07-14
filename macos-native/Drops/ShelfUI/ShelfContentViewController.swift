import AppKit
import QuickLookUI

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
    /// Activate Drops so Space preview is not delivered to Finder.
    var onClaimKeyFocus: (() -> Void)?

    private let emptyLabel = NSTextField(wrappingLabelWithString: "")
    private let overlayCloseButton = NSButton(title: "", target: nil, action: nil)
    private let detailBackButton = NSButton(title: "", target: nil, action: nil)
    private let gridModeButton = NSButton(title: "", target: nil, action: nil)
    private let listModeButton = NSButton(title: "", target: nil, action: nil)
    private let detailTitleLabel = NSTextField(labelWithString: "")
    private let detailSubtitleLabel = NSTextField(labelWithString: "")
    private let enterDetailsButton = NSButton(title: "", target: nil, action: nil)
    private let overlayGrabber = NSView()

    private let scrollView = NSScrollView()
    private var tableView: NSTableView!
    private var collectionView: NSCollectionView!
    private let collapsedStackView = CollapsedStackView()
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

        emptyLabel.font = .systemFont(ofSize: 12)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        detailTitleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        detailTitleLabel.textColor = .labelColor
        detailTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        detailSubtitleLabel.font = .systemFont(ofSize: 10)
        detailSubtitleLabel.textColor = .secondaryLabelColor
        detailSubtitleLabel.lineBreakMode = .byTruncatingTail
        detailSubtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        configureRoundIcon(button: overlayCloseButton, symbolName: "xmark", action: #selector(closeTapped))
        configureRoundIcon(button: detailBackButton, symbolName: "chevron.left", action: #selector(collapseTapped))
        configureRoundIcon(button: gridModeButton, symbolName: "square.grid.2x2", action: #selector(gridModeTapped))
        configureRoundIcon(button: listModeButton, symbolName: "list.bullet", action: #selector(listModeTapped))
        configureEnterDetailsButton()

        overlayGrabber.wantsLayer = true
        overlayGrabber.layer?.cornerRadius = 2
        overlayGrabber.layer?.backgroundColor = NSColor.secondaryLabelColor.withAlphaComponent(0.5).cgColor
        overlayGrabber.translatesAutoresizingMaskIntoConstraints = false

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
        modeRow.spacing = 6
        modeRow.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(overlayGrabber)
        root.addSubview(overlayCloseButton)
        root.addSubview(detailBackButton)
        root.addSubview(detailTitleLabel)
        root.addSubview(detailSubtitleLabel)
        root.addSubview(modeRow)
        root.addSubview(emptyLabel)
        root.addSubview(scrollView)
        root.addSubview(collapsedStackView)
        root.addSubview(enterDetailsButton)

        NSLayoutConstraint.activate([
            overlayGrabber.topAnchor.constraint(equalTo: root.topAnchor, constant: 5),
            overlayGrabber.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            overlayGrabber.widthAnchor.constraint(equalToConstant: 35),
            overlayGrabber.heightAnchor.constraint(equalToConstant: 4),

            overlayCloseButton.topAnchor.constraint(equalTo: root.topAnchor, constant: 7),
            overlayCloseButton.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 7),
            overlayCloseButton.widthAnchor.constraint(equalToConstant: 32),
            overlayCloseButton.heightAnchor.constraint(equalToConstant: 32),

            detailBackButton.topAnchor.constraint(equalTo: root.topAnchor, constant: 7),
            detailBackButton.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 7),
            detailBackButton.widthAnchor.constraint(equalToConstant: 32),
            detailBackButton.heightAnchor.constraint(equalToConstant: 32),

            detailTitleLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 9),
            detailTitleLabel.leadingAnchor.constraint(equalTo: detailBackButton.trailingAnchor, constant: 7),
            detailTitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: modeRow.leadingAnchor, constant: -8),
            detailSubtitleLabel.topAnchor.constraint(equalTo: detailTitleLabel.bottomAnchor, constant: 1),
            detailSubtitleLabel.leadingAnchor.constraint(equalTo: detailTitleLabel.leadingAnchor),
            detailSubtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: modeRow.leadingAnchor, constant: -8),

            modeRow.centerYAnchor.constraint(equalTo: detailBackButton.centerYAnchor),
            modeRow.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10),

            emptyLabel.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: root.centerYAnchor, constant: 2),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: root.leadingAnchor, constant: 20),
            emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -20),

            scrollView.topAnchor.constraint(equalTo: detailBackButton.bottomAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -10),

            collapsedStackView.topAnchor.constraint(equalTo: overlayCloseButton.bottomAnchor, constant: 9),
            collapsedStackView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            collapsedStackView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            collapsedStackView.bottomAnchor.constraint(equalTo: enterDetailsButton.topAnchor, constant: -7),

            enterDetailsButton.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            enterDetailsButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -11),
            enterDetailsButton.heightAnchor.constraint(equalToConstant: 28),
            enterDetailsButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 58),
        ])

        languageObserver = NotificationCenter.default.addObserver(
            forName: .dropsLanguageDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.applyLocalizedChrome()
                self?.refreshLabels()
            }
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

    /// Lightweight selection sync used after click so cells are not reloaded/resized.
    func syncSelection(from shelf: Shelf) {
        selection = shelf.selection
        if let anchor = selectionAnchor, items.contains(where: { $0.id == anchor }) {
            // keep
        } else if let first = shelf.orderedSelection().first {
            selectionAnchor = first.id
        } else {
            selectionAnchor = nil
        }
        syncSelectionToViews()
    }

    /// Recompute grid itemSize when the window resizes without a full content reload.
    func updateExpandedGridLayoutIfNeeded() {
        guard presentation == .expanded, displayMode == .grid else { return }
        applyGridItemSize()
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
        case 49: // Space — claim focus so Finder does not receive the preview shortcut
            onClaimKeyFocus?()
            prepareQuickLookURLsFromSelection()
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

    /// QLPreviewPanel walks the responder chain; accept only when we have local files to show.
    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        canControlQuickLookPanel
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        prepareQuickLookURLsFromSelection()
        QuickLookPreviewController.shared.attach(to: panel)
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        QuickLookPreviewController.shared.detach(from: panel)
    }

    private var canControlQuickLookPanel: Bool {
        let ordered = items.filter { selection.contains($0.id) }
        guard !ordered.isEmpty else { return QuickLookPreviewController.shared.hasPreviewItems }
        if case .quickLookLocalFiles = ShelfPreviewDecision.decide(for: ordered) {
            return true
        }
        return false
    }

    private func prepareQuickLookURLsFromSelection() {
        let ordered = items.filter { selection.contains($0.id) }
        guard !ordered.isEmpty else { return }
        if case .quickLookLocalFiles(let urls) = ShelfPreviewDecision.decide(for: ordered) {
            QuickLookPreviewController.shared.setPreviewURLs(urls)
        }
    }

    // MARK: - Private

    private func configureTable() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        column.title = "Items"
        column.width = 360
        let keyTable = KeyHandlingTableView()
        keyTable.keyHandler = self
        tableView = keyTable
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.delegate = self
        tableView.dataSource = self
        tableView.rowHeight = 28
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .regular
        tableView.allowsMultipleSelection = true
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
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
        layout.itemSize = NSSize(width: 90, height: ShelfWindowController.gridItemHeight)
        layout.minimumInteritemSpacing = 8
        layout.minimumLineSpacing = 8
        layout.sectionInset = NSEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)

        let keyCollection = KeyHandlingCollectionView()
        keyCollection.keyHandler = self
        collectionView = keyCollection
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
        emptyLabel.stringValue = L10n.emptyDrop

        overlayCloseButton.setAccessibilityLabel(L10n.close)
        detailBackButton.setAccessibilityLabel(L10n.collapse)
        gridModeButton.setAccessibilityLabel(L10n.grid)
        listModeButton.setAccessibilityLabel(L10n.list)
        tableView.setAccessibilityLabel(L10n.a11yItemList)
        collectionView?.setAccessibilityLabel(L10n.a11yItemGrid)
        view.setAccessibilityLabel(L10n.a11yShelfWindow)
    }

    private func refreshLabels() {
        let hasItems = !items.isEmpty
        let isDetail = presentation == .expanded
        let itemCount = items.count
        detailTitleLabel.stringValue = detailTitle(for: itemCount)
        detailSubtitleLabel.stringValue = isDetail ? detailSubtitle : ""
        enterDetailsButton.title = "\(detailTitle(for: itemCount))  ›"

        overlayGrabber.isHidden = isDetail
        overlayCloseButton.isHidden = isDetail
        detailBackButton.isHidden = !isDetail
        detailTitleLabel.isHidden = !isDetail
        detailSubtitleLabel.isHidden = !isDetail
        gridModeButton.isHidden = !isDetail
        listModeButton.isHidden = !isDetail
        gridModeButton.state = displayMode == .grid ? .on : .off
        listModeButton.state = displayMode == .list ? .on : .off
        updateModeButtonAppearance(gridModeButton, selected: displayMode == .grid)
        updateModeButtonAppearance(listModeButton, selected: displayMode == .list)

        switch presentation {
        case .empty:
            scrollView.isHidden = true
            collapsedStackView.isHidden = true
            emptyLabel.isHidden = false
            enterDetailsButton.isHidden = true
        case .collapsed:
            scrollView.isHidden = true
            collapsedStackView.isHidden = !hasItems
            emptyLabel.isHidden = hasItems
            enterDetailsButton.isHidden = !hasItems
            if hasItems {
                collapsedStackView.apply(items: items)
            }
        case .expanded:
            scrollView.isHidden = false
            collapsedStackView.isHidden = true
            emptyLabel.isHidden = true
            enterDetailsButton.isHidden = true
        }
    }

    private func reloadContentViews() {
        guard presentation == .expanded else { return }
        let useGrid = displayMode == .grid
        if useGrid {
            if scrollView.documentView !== collectionView {
                scrollView.documentView = collectionView
            }
            applyGridItemSize()
            collectionView.reloadData()
        } else {
            if scrollView.documentView !== tableView {
                scrollView.documentView = tableView
            }
            tableView.reloadData()
        }
    }

    /// PRD 5.3.2: at most 3 items per row; height stays content-tight (not width-derived).
    private func applyGridItemSize() {
        guard let layout = collectionView.collectionViewLayout as? NSCollectionViewFlowLayout else {
            return
        }
        let horizontalInset = layout.sectionInset.left + layout.sectionInset.right
        let containerWidth = scrollView.bounds.width > 1
            ? scrollView.bounds.width
            : (view.bounds.width > 1 ? max(view.bounds.width - 16, 1) : expandedFallbackWidth)
        let available = max(containerWidth - horizontalInset, 60)
        let spacing = layout.minimumInteritemSpacing
        let width = floor((available - spacing * 2) / 3)
        let next = NSSize(width: max(width, 60), height: ShelfWindowController.gridItemHeight)
        guard layout.itemSize != next else { return }
        layout.itemSize = next
        layout.invalidateLayout()
    }

    private var expandedFallbackWidth: CGFloat { 304 }

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

    private func configureRoundIcon(button: NSButton, symbolName: String, action: Selector?) {
        button.bezelStyle = .inline
        button.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: nil
        )
        button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        button.contentTintColor = .secondaryLabelColor
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 16
        button.layer?.cornerCurve = .continuous
        button.layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.6).cgColor
    }

    private func configureEnterDetailsButton() {
        enterDetailsButton.bezelStyle = .inline
        enterDetailsButton.font = .systemFont(ofSize: 11, weight: .medium)
        enterDetailsButton.contentTintColor = .labelColor
        enterDetailsButton.target = self
        enterDetailsButton.action = #selector(expandTapped)
        enterDetailsButton.translatesAutoresizingMaskIntoConstraints = false
        enterDetailsButton.wantsLayer = true
        enterDetailsButton.layer?.cornerRadius = 14
        enterDetailsButton.layer?.cornerCurve = .continuous
        enterDetailsButton.layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.75).cgColor
    }

    private func updateModeButtonAppearance(_ button: NSButton, selected: Bool) {
        button.contentTintColor = selected ? .labelColor : .secondaryLabelColor
        button.layer?.backgroundColor = (selected
            ? NSColor.tertiaryLabelColor.withAlphaComponent(0.7)
            : NSColor.quaternaryLabelColor.withAlphaComponent(0.6)
        ).cgColor
    }

    private func detailTitle(for count: Int) -> String {
        if AppLocalization.effectiveLanguageCode == "zh-Hans" {
            return "\(count) 项"
        }
        return "\(count) \(count == 1 ? "item" : "items")"
    }

    private var detailSubtitle: String {
        AppLocalization.effectiveLanguageCode == "zh-Hans"
            ? "右键文件可查看更多操作"
            : "Right-click an item for actions"
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
        onClaimKeyFocus?()
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

    override func mouseDown(with event: NSEvent) {
        owner?.onClaimKeyFocus?()
        super.mouseDown(with: event)
    }

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

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        owner?.acceptsPreviewPanelControl(panel) ?? false
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        owner?.beginPreviewPanelControl(panel)
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        owner?.endPreviewPanelControl(panel)
    }
}

/// Forwards Space / Delete / Escape while the grid holds first responder.
private final class KeyHandlingCollectionView: NSCollectionView {
    weak var keyHandler: ShelfContentViewController?

    override func mouseDown(with event: NSEvent) {
        keyHandler?.onClaimKeyFocus?()
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if keyHandler?.handleKeyDown(event) == true { return }
        super.keyDown(with: event)
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        keyHandler?.acceptsPreviewPanelControl(panel) ?? false
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        keyHandler?.beginPreviewPanelControl(panel)
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        keyHandler?.endPreviewPanelControl(panel)
    }
}

/// Forwards Space / Delete / Escape while the list holds first responder.
private final class KeyHandlingTableView: NSTableView {
    weak var keyHandler: ShelfContentViewController?

    override func mouseDown(with event: NSEvent) {
        keyHandler?.onClaimKeyFocus?()
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if keyHandler?.handleKeyDown(event) == true { return }
        super.keyDown(with: event)
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        keyHandler?.acceptsPreviewPanelControl(panel) ?? false
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        keyHandler?.beginPreviewPanelControl(panel)
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        keyHandler?.endPreviewPanelControl(panel)
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
