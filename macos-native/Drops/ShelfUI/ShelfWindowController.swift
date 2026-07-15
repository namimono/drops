import AppKit
import QuartzCore

/// Borderless panels default to `canBecomeKey == false`; override so persistent shelves stay interactive.
private final class ShelfPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Keep domain-driven empty/collapsed/expanded sizes; do not inflate to content fittingSize.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        var constrained = super.constrainFrameRect(frameRect, to: screen)
        constrained.size = frameRect.size
        if let screen {
            let visible = screen.visibleFrame
            constrained.origin.x = min(
                max(constrained.origin.x, visible.minX),
                max(visible.minX, visible.maxX - constrained.size.width)
            )
            constrained.origin.y = min(
                max(constrained.origin.y, visible.minY),
                max(visible.minY, visible.maxY - constrained.size.height)
            )
        }
        return constrained
    }
}

/// Formal shelf window. Migrates Stage 0 chrome / focus contracts into `NSWindowController`.
@MainActor
final class ShelfWindowController: NSWindowController, NSWindowDelegate {
    let shelfID: ShelfID
    let openSource: ShelfOpenSource

    var onClose: (() -> Void)?
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
    var onMergeDrag: ((ShelfItemID, Set<ShelfItemID>) -> Bool)?
    var onCanMergeSelection: (() -> Bool)?
    var onDisplayModeChange: ((ShelfDisplayMode) -> Void)?
    var onSimulateReceive: (() -> Void)?

    private let contentController: ShelfContentViewController
    private let cornerRadius: CGFloat = 16

    private var panel: ShelfPanel { window as! ShelfPanel }

    var styleMask: NSWindow.StyleMask { panel.styleMask }
    var canBecomeKeyWindow: Bool { panel.canBecomeKey }
    var isVisible: Bool { panel.isVisible }
    var frame: NSRect { panel.frame }

    /// True when the window is visible and has registered pasteboard types for drops.
    var isDragDestinationReady: Bool {
        guard panel.isVisible else { return false }
        return contentController.hasRegisteredDragTypes
    }

    /// A small floating overlay that keeps the dropped stack within a single visual focus.
    private static let emptySize = NSSize(width: 200, height: 208)
    private static let collapsedSize = NSSize(width: 200, height: 208)

    /// Expanded detail width stays fixed; height grows with item count between min and max.
    private static let expandedWidth: CGFloat = 320
    private static let expandedMinHeight: CGFloat = 240
    private static let expandedMaxHeight: CGFloat = 434
    private static let expandedHeaderHeight: CGFloat = 49
    private static let expandedScrollVerticalInset: CGFloat = 20
    private static let gridColumns = 3
    static let gridItemHeight: CGFloat = 96
    private static let gridLineSpacing: CGFloat = 8
    private static let gridSectionVerticalInset: CGFloat = 8
    private static let listRowHeight: CGFloat = 28

    static func size(
        for presentation: ShelfPresentation,
        itemCount: Int = 0,
        displayMode: ShelfDisplayMode = .grid
    ) -> NSSize {
        switch presentation {
        case .empty: return emptySize
        case .collapsed: return collapsedSize
        case .expanded:
            return expandedSize(itemCount: itemCount, displayMode: displayMode)
        }
    }

    /// Height grows with rows/items, clamped to `[expandedMinHeight, expandedMaxHeight]`.
    static func expandedSize(itemCount: Int, displayMode: ShelfDisplayMode) -> NSSize {
        let count = max(itemCount, 1)
        let contentHeight: CGFloat
        switch displayMode {
        case .grid:
            let rows = ceil(CGFloat(count) / CGFloat(gridColumns))
            contentHeight = gridSectionVerticalInset
                + rows * gridItemHeight
                + max(0, rows - 1) * gridLineSpacing
        case .list:
            contentHeight = CGFloat(count) * listRowHeight
        }
        let height = min(
            expandedMaxHeight,
            max(expandedMinHeight, expandedHeaderHeight + expandedScrollVerticalInset + contentHeight)
        )
        return NSSize(width: expandedWidth, height: height)
    }

    init(shelfID: ShelfID, openSource: ShelfOpenSource) {
        self.shelfID = shelfID
        self.openSource = openSource
        self.contentController = ShelfContentViewController()

        var style: NSWindow.StyleMask = [.borderless]
        if openSource == .shake {
            style.insert(.nonactivatingPanel)
        }
        let panel = ShelfPanel(
            contentRect: NSRect(origin: .zero, size: Self.emptySize),
            styleMask: style,
            backing: .buffered,
            defer: false
        )
        super.init(window: panel)

        configurePanel()
        configureContent()
        panel.delegate = self

        contentController.onCloseRequested = { [weak self] in self?.close() }
        contentController.onToggleExpand = { [weak self] in self?.onToggleExpand?() }
        contentController.onCollapse = { [weak self] in self?.onCollapse?() }
        contentController.onPasteboardDrop = { [weak self] pb in self?.onPasteboardDrop?(pb) ?? false }
        contentController.onPasteRequested = { [weak self] in self?.onPasteRequested?() }
        contentController.onSelectionClick = { [weak self] id, mods, anchor in
            self?.onSelectionClick?(id, mods, anchor)
        }
        contentController.onDragOutEnded = { [weak self] ids, op in
            self?.onDragOutEnded?(ids, op)
        }
        contentController.onOpenItem = { [weak self] id in self?.onOpenItem?(id) }
        contentController.onPreviewSelection = { [weak self] in self?.onPreviewSelection?() }
        contentController.onRevealSelection = { [weak self] in self?.onRevealSelection?() }
        contentController.onRemoveSelection = { [weak self] in self?.onRemoveSelection?() }
        contentController.onMergeSelection = { [weak self] in self?.onMergeSelection?() }
        contentController.onMergeDrag = { [weak self] target, sources in
            self?.onMergeDrag?(target, sources) ?? false
        }
        contentController.onCanMergeSelection = { [weak self] in self?.onCanMergeSelection?() ?? false }
        contentController.onDisplayModeChange = { [weak self] mode in self?.onDisplayModeChange?(mode) }
        contentController.onSimulateReceive = { [weak self] in self?.onSimulateReceive?() }
        contentController.onClaimKeyFocus = { [weak self] in self?.claimKeyFocus() }
    }

    /// Activate Drops and make this shelf key so keyboard / Quick Look stay in-process.
    func claimKeyFocus() {
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKey()
        if panel.firstResponder == nil
            || panel.firstResponder === panel
            || panel.firstResponder === panel.contentView {
            panel.makeFirstResponder(contentController.view)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(onMilestone: ((ShelfShowMilestone) -> Void)? = nil) {
        panel.orderFrontRegardless()
        if openSource != .shake {
            panel.makeKey()
            NSApp.activate(ignoringOtherApps: true)
        }
        notifyWhenReady(onMilestone)
    }

    override func close() {
        panel.close()
    }

    func positionNearMouse(offset: NSPoint = .zero, mouseLocation: NSPoint? = nil) {
        let size = panel.frame.size
        let origin = ShelfWindowGeometry.originNearMouse(
            size: size,
            offset: offset,
            mouseLocation: mouseLocation ?? NSEvent.mouseLocation
        )
        panel.setFrameOrigin(origin)
    }

    /// When `false`, size changes skip `NSWindow` animation (useful for rapid automated toggles).
    var animatesPresentationChanges = true

    func apply(shelf: Shelf, displayMode: ShelfDisplayMode = .grid) {
        let size = Self.size(
            for: shelf.presentation,
            itemCount: shelf.items.count,
            displayMode: displayMode
        )

        switch shelf.presentation {
        case .expanded:
            // Size first so grid itemSize uses final scrollView bounds (avoids click-to-grow jump).
            resize(to: size, animated: animatesPresentationChanges)
            panel.layoutIfNeeded()
            contentController.apply(shelf: shelf, displayMode: displayMode)
            settleFrame(to: size)
        case .empty, .collapsed:
            // Apply chrome first so expanded Auto Layout cannot inflate the smaller frame.
            contentController.apply(shelf: shelf, displayMode: displayMode)
            resize(to: size, animated: animatesPresentationChanges)
            settleFrame(to: size)
        }
    }

    /// Selection-only refresh: avoid reloadData so grid cells do not jump size on click.
    func syncSelection(from shelf: Shelf) {
        contentController.syncSelection(from: shelf)
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }

    func windowDidResize(_ notification: Notification) {
        refreshRoundedWindowChrome()
        contentController.updateExpandedGridLayoutIfNeeded()
    }

    // MARK: - Private

    private func notifyWhenReady(_ onMilestone: ((ShelfShowMilestone) -> Void)?) {
        guard let onMilestone else { return }
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            guard let self else { return }
            self.panel.layoutIfNeeded()
            self.panel.displayIfNeeded()
            self.refreshRoundedWindowChrome()
            if self.openSource == .shake {
                onMilestone(.transientWindowVisible)
                if self.isDragDestinationReady {
                    onMilestone(.dragReady)
                }
            } else {
                onMilestone(.firstFrameVisible)
            }
        }
        panel.layoutIfNeeded()
        panel.displayIfNeeded()
        CATransaction.commit()
    }

    private func configurePanel() {
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.becomesKeyOnlyIfNeeded = openSource == .shake
        panel.animationBehavior = .utilityWindow
        panel.minSize = NSSize(width: 1, height: 1)
        panel.contentMinSize = NSSize(width: 1, height: 1)
        panel.setAccessibilityTitle(L10n.a11yShelfWindow)
        // Follow system appearance (light/dark) without a fixed chrome color.
        panel.appearance = nil
    }

    private func configureContent() {
        let root = NSView(frame: panel.frame)
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.clear.cgColor

        let container = NSVisualEffectView(frame: root.bounds)
        container.material = .hudWindow
        container.blendingMode = .behindWindow
        container.state = .followsWindowActiveState
        container.appearance = nil
        container.wantsLayer = true
        container.layer?.cornerRadius = cornerRadius
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = true
        container.autoresizingMask = [.width, .height]

        contentController.view.frame = container.bounds
        contentController.view.autoresizingMask = [.width, .height]
        container.addSubview(contentController.view)
        root.addSubview(container)

        panel.contentView = root
        refreshRoundedWindowChrome()
    }

    private func refreshRoundedWindowChrome() {
        guard let root = panel.contentView else { return }
        root.wantsLayer = true
        root.layer?.cornerRadius = cornerRadius
        root.layer?.cornerCurve = .continuous
        root.layer?.masksToBounds = false
        root.layer?.backgroundColor = NSColor.clear.cgColor
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.invalidateShadow()
    }

    private func resize(to size: NSSize, animated: Bool) {
        var frame = panel.frame
        let origin = ShelfWindowGeometry.clampedOrigin(
            NSPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2),
            size: size,
            mouseLocation: NSPoint(x: frame.midX, y: frame.midY)
        )
        frame = NSRect(origin: origin, size: size)
        panel.setFrame(frame, display: true, animate: animated)
        refreshRoundedWindowChrome()
    }

    /// Re-assert domain-driven size if Auto Layout nudged the panel during content updates.
    private func settleFrame(to size: NSSize) {
        guard abs(panel.frame.width - size.width) > 0.5
            || abs(panel.frame.height - size.height) > 0.5 else { return }
        resize(to: size, animated: false)
    }
}
