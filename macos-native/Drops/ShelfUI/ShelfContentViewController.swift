import AppKit
import QuartzCore
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
    /// Drag-merge: target item ID, plus the item IDs actually being dragged.
    var onMergeDrag: ((ShelfItemID, Set<ShelfItemID>) -> Bool)?
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
    private let mergeHintBanner = MergeHintBannerView()
    private var languageObserver: NSObjectProtocol?

    private var shelfID: ShelfID?
    private(set) var presentation: ShelfPresentation = .empty
    private var lifecycle: ShelfLifecycle = .persistent
    private(set) var items: [ShelfItem] = []
    private var selection: Set<ShelfItemID> = []
    private var selectionAnchor: ShelfItemID?
    private var displayMode: ShelfDisplayMode = .grid
    /// Cancels in-flight grid↔list crossfades when a newer apply arrives.
    private var displayModeTransitionToken = 0
    private var isReceivingDrag = false
    private var dragOutItemIDs: Set<ShelfItemID> = []

    /// Drag-merge arming (PRD 5.5.2): ~0.45s hover on another plain-text item.
    private var mergeHoverTargetID: ShelfItemID?
    private var mergeArmed = false
    private var mergeHoverTimer: Timer?
    private var dragMonitorTimer: Timer?
    private weak var activeDragSession: NSDraggingSession?
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
        configureModeIcon(button: gridModeButton, symbolName: "square.grid.2x2", action: #selector(gridModeTapped))
        configureModeIcon(button: listModeButton, symbolName: "list.bullet", action: #selector(listModeTapped))
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
        modeRow.spacing = 4
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
        root.addSubview(mergeHintBanner)

        mergeHintBanner.translatesAutoresizingMaskIntoConstraints = false
        mergeHintBanner.isHidden = true
        mergeHintBanner.setAccessibilityElement(true)
        mergeHintBanner.setAccessibilityRole(.staticText)

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

            mergeHintBanner.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            mergeHintBanner.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -14),
            mergeHintBanner.leadingAnchor.constraint(greaterThanOrEqualTo: root.leadingAnchor, constant: 16),
            mergeHintBanner.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -16),
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
        let previousMode = self.displayMode
        let previousPresentation = presentation
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
        let animateModeSwitch =
            previousPresentation == .expanded
            && shelf.presentation == .expanded
            && previousMode != displayMode
        refreshLabels(animateModeButtons: animateModeSwitch)
        if animateModeSwitch {
            reloadContentViews(animated: true) { [weak self] in
                self?.syncSelectionToViews()
            }
        } else {
            reloadContentViews(animated: false)
            syncSelectionToViews()
        }
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
        guard canAcceptExternalDrop(sender) else { return [] }
        isReceivingDrag = true
        view.needsDisplay = true
        return .copy
    }

    func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        canAcceptExternalDrop(sender) ? .copy : []
    }

    func draggingExited(_ sender: NSDraggingInfo?) {
        isReceivingDrag = false
        view.needsDisplay = true
    }

    func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        canAcceptExternalDrop(sender)
    }

    func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isReceivingDrag = false
        view.needsDisplay = true
        // Reject same-shelf drops so in-window drags cannot re-insert / "reorder" items.
        guard canAcceptExternalDrop(sender) else { return false }
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
            let sourceIDs = dragOutItemIDs
            suppressDragImageReturn(session)
            clearMergeHover(restoringDragImageReturn: false)
            activeDragSession = nil
            dragOutItemIDs = []
            // Hide dragged sources immediately so AppKit's drag-end cleanup cannot
            // flash them back into their shelf slots before replaceItems runs.
            // Do not pulse-then-remove: that is what looked like "snap back, shake, vanish".
            setItemViewsHidden(sourceIDs, hidden: true)
            // Use dragged item IDs — not selection — local drops no longer
            // re-insert, so selection may be empty/stale during the drag.
            let merged = onMergeDrag?(target, sourceIDs) ?? false
            if merged {
                playMergeResultPulse()
            } else {
                setItemViewsHidden(sourceIDs, hidden: false)
                onDragOutEnded?(sourceIDs, operation)
            }
            return
        }
        clearMergeHover()
        activeDragSession = nil
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
        refreshMergeFeedback(animated: false)
    }

    private func refreshLabels(animateModeButtons: Bool = false) {
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
        updateModeButtonAppearance(gridModeButton, selected: displayMode == .grid, animated: animateModeButtons)
        updateModeButtonAppearance(listModeButton, selected: displayMode == .list, animated: animateModeButtons)

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

    private func reloadContentViews(animated: Bool = false, completion: (() -> Void)? = nil) {
        guard presentation == .expanded else {
            completion?()
            return
        }

        let installCurrentMode: () -> Void = { [weak self] in
            guard let self else { return }
            let useGrid = self.displayMode == .grid
            if useGrid {
                if self.scrollView.documentView !== self.collectionView {
                    self.scrollView.documentView = self.collectionView
                }
                self.applyGridItemSize()
                self.collectionView.reloadData()
            } else {
                if self.scrollView.documentView !== self.tableView {
                    self.scrollView.documentView = self.tableView
                }
                self.tableView.reloadData()
            }
        }

        guard animated else {
            displayModeTransitionToken += 1
            scrollView.alphaValue = 1
            installCurrentMode()
            completion?()
            return
        }

        displayModeTransitionToken += 1
        let token = displayModeTransitionToken
        scrollView.wantsLayer = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            scrollView.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, token == self.displayModeTransitionToken else { return }
            installCurrentMode()
            self.scrollView.alphaValue = 0
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.scrollView.animator().alphaValue = 1
            }, completionHandler: {
                guard token == self.displayModeTransitionToken else { return }
                completion?()
            })
        })
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

    /// External Finder/app drops only — ignore drags that started inside this shelf.
    private func canAcceptExternalDrop(_ sender: NSDraggingInfo) -> Bool {
        if isLocalShelfDraggingSource(sender) { return false }
        return canAccept(sender)
    }

    private func isLocalShelfDraggingSource(_ sender: NSDraggingInfo) -> Bool {
        if !dragOutItemIDs.isEmpty { return true }
        guard let source = sender.draggingSource else { return false }
        if source as AnyObject === self { return true }
        if source as AnyObject === view { return true }
        if let collectionView, source as AnyObject === collectionView { return true }
        if let tableView, source as AnyObject === tableView { return true }
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

    /// Grid / list toggle: clearer SF Symbols, larger hit target; active gets light rounded rect only.
    private func configureModeIcon(button: NSButton, symbolName: String, action: Selector?) {
        button.bezelStyle = .inline
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: nil
        )
        button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        button.contentTintColor = .labelColor
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 8
        button.layer?.cornerCurve = .continuous
        button.layer?.backgroundColor = NSColor.clear.cgColor
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 34),
            button.heightAnchor.constraint(equalToConstant: 28),
        ])
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

    private func updateModeButtonAppearance(_ button: NSButton, selected: Bool, animated: Bool = false) {
        button.contentTintColor = .labelColor
        // Light fill only — quaternaryLabel @ high alpha reads almost black on light chrome.
        let color = selected
            ? NSColor.labelColor.withAlphaComponent(0.08).cgColor
            : NSColor.clear.cgColor
        guard animated, let layer = button.layer else {
            button.layer?.backgroundColor = color
            return
        }
        let animation = CABasicAnimation(keyPath: "backgroundColor")
        animation.fromValue = layer.presentation()?.backgroundColor ?? layer.backgroundColor
        animation.toValue = color
        animation.duration = 0.2
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(animation, forKey: "modeSelectionBackground")
        layer.backgroundColor = color
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
        if mergeArmed {
            setItemViewsHidden(dragOutItemIDs, hidden: false)
            activeDragSession?.animatesToStartingPositionsOnCancelOrFail = true
        }
        mergeHoverTimer?.invalidate()
        mergeHoverTargetID = targetID
        mergeArmed = false
        refreshMergeFeedback(animated: true)
        mergeHoverTimer = Timer.scheduledTimer(withTimeInterval: Self.mergeHoverDelay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.mergeHoverTargetID == targetID else { return }
                self.mergeArmed = true
                // This must happen before the mouse is released. Setting it in
                // the drag-end callback is too late to prevent AppKit's return
                // animation for the source drag image.
                self.activeDragSession?.animatesToStartingPositionsOnCancelOrFail = false
                // Hide sources while armed so drag-end cannot reveal them at their
                // shelf slots (that flash-back is what users perceived as snap-back).
                self.setItemViewsHidden(self.dragOutItemIDs, hidden: true)
                self.refreshMergeFeedback(animated: true)
                NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
            }
        }
    }

    private func clearMergeHover(restoringDragImageReturn: Bool = true) {
        let hadFeedback = mergeHoverTargetID != nil || mergeArmed || !mergeHintBanner.isHidden
        let wasArmed = mergeArmed
        let sourceIDs = dragOutItemIDs
        mergeHoverTimer?.invalidate()
        mergeHoverTimer = nil
        if restoringDragImageReturn {
            activeDragSession?.animatesToStartingPositionsOnCancelOrFail = true
        }
        mergeHoverTargetID = nil
        mergeArmed = false
        // Only restore sources when cancelling arm (left target / left window).
        // On successful merge commit we keep them hidden until replaceItems.
        if wasArmed, restoringDragImageReturn {
            setItemViewsHidden(sourceIDs, hidden: false)
        }
        if hadFeedback {
            refreshMergeFeedback(animated: true)
        }
    }

    /// Banner + target highlight for drag-merge arming (PRD 5.5.2).
    private func refreshMergeFeedback(animated: Bool) {
        let state: MergeHintBannerView.State
        if mergeHoverTargetID != nil, mergeArmed {
            state = .armed
        } else if mergeHoverTargetID != nil {
            state = .pending
        } else {
            state = .hidden
        }

        let apply = { [weak self] in
            guard let self else { return }
            self.mergeHintBanner.apply(state: state)
            self.mergeHintBanner.setAccessibilityLabel(self.mergeHintBanner.accessibilityLabelText)
            self.applyMergeTargetHighlights()
        }

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.allowsImplicitAnimation = true
                apply()
            }
        } else {
            apply()
        }
    }

    private func applyMergeTargetHighlights() {
        let targetID = mergeHoverTargetID
        let armed = mergeArmed
        if scrollView.documentView === tableView {
            for row in 0..<items.count {
                guard let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? ShelfListCellView
                else { continue }
                let highlight: MergeTargetHighlight = {
                    guard items[row].id == targetID else { return .none }
                    return armed ? .armed : .pending
                }()
                cell.setMergeHighlight(highlight)
            }
        } else if let collectionView {
            for index in 0..<items.count {
                let path = IndexPath(item: index, section: 0)
                guard let item = collectionView.item(at: path) as? ShelfGridItemView else { continue }
                let highlight: MergeTargetHighlight = {
                    guard items[index].id == targetID else { return .none }
                    return armed ? .armed : .pending
                }()
                item.setMergeHighlight(highlight)
            }
        }
    }

    private func startDragMonitor(for session: NSDraggingSession) {
        stopDragMonitor()
        activeDragSession = session
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

    /// Keep AppKit from returning the source drag image once a merge is armed.
    private func suppressDragImageReturn(_ session: NSDraggingSession) {
        session.animatesToStartingPositionsOnCancelOrFail = false
    }

    private func itemViews(for ids: Set<ShelfItemID>, makeIfNecessary: Bool = false) -> [NSView] {
        guard !ids.isEmpty else { return [] }
        var views: [NSView] = []
        if scrollView.documentView === tableView {
            for row in 0..<items.count where ids.contains(items[row].id) {
                if let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: makeIfNecessary) {
                    views.append(cell)
                }
            }
        } else if let collectionView {
            for index in 0..<items.count where ids.contains(items[index].id) {
                let path = IndexPath(item: index, section: 0)
                if let item = collectionView.item(at: path) {
                    views.append(item.view)
                }
            }
        }
        return views
    }

    /// Hide or restore shelf item views without waiting for reloadData.
    private func setItemViewsHidden(_ ids: Set<ShelfItemID>, hidden: Bool) {
        for view in itemViews(for: ids) {
            view.alphaValue = hidden ? 0 : 1
        }
    }

    /// Light in-place scale pulse on the merge result (selected after replaceItems).
    private func playMergeResultPulse() {
        // Defer one turn so reloadData has materialised the result cell.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let views = self.itemViews(for: self.selection, makeIfNecessary: true)
            for view in views {
                view.wantsLayer = true
                view.layer?.removeAnimation(forKey: "mergeResultPulse")
                let animation = CAKeyframeAnimation(keyPath: "transform.scale")
                animation.values = [1.0, 1.06, 1.0]
                animation.keyTimes = [0, 0.45, 1.0]
                animation.duration = 0.28
                animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                view.layer?.add(animation, forKey: "mergeResultPulse")
            }
        }
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
    @objc private func contextMerge() {
        onMergeSelection?()
        playMergeResultPulse()
    }

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
        startDragMonitor(for: session)
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
        startDragMonitor(for: session)
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

private enum MergeTargetHighlight {
    case none
    case pending
    case armed
}

/// Floating cue shown while dragging text onto another text item for merge.
private final class MergeHintBannerView: NSView {
    enum State {
        case hidden
        case pending
        case armed
    }

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private(set) var accessibilityLabelText = ""

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.contentTintColor = .white

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail

        addSubview(iconView)
        addSubview(titleLabel)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 14),
            iconView.heightAnchor.constraint(equalToConstant: 14),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -7),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(state: State) {
        // The merge status should be informative but visually still. In
        // particular, it must not compete with the merge-success animation.
        layer?.removeAnimation(forKey: "mergePulse")
        layer?.transform = CATransform3DIdentity
        switch state {
        case .hidden:
            isHidden = true
            alphaValue = 0
            accessibilityLabelText = ""
        case .pending:
            isHidden = false
            alphaValue = 1
            // Soft gray chrome — matches empty/collapsed HUD, no new accent hue.
            layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.96).cgColor
            layer?.borderWidth = 1
            layer?.borderColor = NSColor.separatorColor.cgColor
            iconView.contentTintColor = .secondaryLabelColor
            titleLabel.textColor = .secondaryLabelColor
            iconView.image = NSImage(
                systemSymbolName: "clock.arrow.circlepath",
                accessibilityDescription: nil
            )
            titleLabel.stringValue = L10n.mergeHoverPending
            accessibilityLabelText = L10n.mergeHoverPending
        case .armed:
            isHidden = false
            alphaValue = 1
            // Same blue family as selection / drag highlight.
            layer?.backgroundColor = NSColor.selectedContentBackgroundColor.cgColor
            layer?.borderWidth = 0
            layer?.borderColor = nil
            iconView.contentTintColor = .white
            titleLabel.textColor = .white
            iconView.image = NSImage(
                systemSymbolName: "arrow.triangle.merge",
                accessibilityDescription: nil
            )
            titleLabel.stringValue = L10n.mergeHoverArmed
            accessibilityLabelText = L10n.mergeHoverArmed
        }
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
    private var mergeHighlight: MergeTargetHighlight = .none

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
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

    func setMergeHighlight(_ highlight: MergeTargetHighlight) {
        mergeHighlight = highlight
        wantsLayer = true
        switch highlight {
        case .none:
            layer?.borderWidth = 0
            layer?.borderColor = nil
            layer?.backgroundColor = nil
            layer?.cornerRadius = 0
            layer?.removeAnimation(forKey: "mergePulse")
        case .pending:
            // Align with drag-in blue ring, lighter than selection fill.
            layer?.cornerRadius = 6
            layer?.borderWidth = 1.5
            layer?.borderColor = NSColor.systemBlue.withAlphaComponent(0.55).cgColor
            layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.10).cgColor
            layer?.removeAnimation(forKey: "mergePulse")
        case .armed:
            layer?.cornerRadius = 6
            layer?.borderWidth = 2
            layer?.borderColor = NSColor.systemBlue.cgColor
            layer?.backgroundColor = NSColor.selectedContentBackgroundColor.withAlphaComponent(0.35).cgColor
            let animation = CABasicAnimation(keyPath: "borderWidth")
            animation.fromValue = 1.5
            animation.toValue = 2.5
            animation.duration = 0.45
            animation.autoreverses = true
            animation.repeatCount = .infinity
            layer?.add(animation, forKey: "mergePulse")
        }
    }
}

private final class ShelfGridItemView: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("ShelfGridItemView")

    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private var representedItemID: ShelfItemID?
    private var mergeHighlight: MergeTargetHighlight = .none

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
        setMergeHighlight(.none)
    }

    func setMergeHighlight(_ highlight: MergeTargetHighlight) {
        mergeHighlight = highlight
        view.wantsLayer = true
        view.layer?.cornerRadius = 8
        view.layer?.removeAnimation(forKey: "mergePulse")
        switch highlight {
        case .none:
            refreshSelectionBackground()
            view.layer?.borderWidth = 0
            view.layer?.borderColor = nil
        case .pending:
            view.layer?.borderWidth = 1.5
            view.layer?.borderColor = NSColor.systemBlue.withAlphaComponent(0.55).cgColor
            view.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.10).cgColor
        case .armed:
            view.layer?.borderWidth = 2
            view.layer?.borderColor = NSColor.systemBlue.cgColor
            view.layer?.backgroundColor = NSColor.selectedContentBackgroundColor.withAlphaComponent(0.35).cgColor
            let animation = CABasicAnimation(keyPath: "transform.scale")
            animation.fromValue = 1.0
            animation.toValue = 1.05
            animation.duration = 0.5
            animation.autoreverses = true
            animation.repeatCount = .infinity
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            view.layer?.add(animation, forKey: "mergePulse")
        }
    }

    override var isSelected: Bool {
        didSet {
            guard mergeHighlight == .none else { return }
            refreshSelectionBackground()
        }
    }

    private func refreshSelectionBackground() {
        view.layer?.backgroundColor = (isSelected
            ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.35)
            : NSColor.clear).cgColor
        view.layer?.cornerRadius = 8
    }
}
