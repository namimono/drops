import AppKit
import QuartzCore

/// Borderless panels default to `canBecomeKey == false`; override so persistent shelves stay interactive.
private final class ShelfPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Formal shelf window. Migrates Stage 0 chrome / focus contracts into `NSWindowController`.
@MainActor
final class ShelfWindowController: NSWindowController, NSWindowDelegate {
    let shelfID: ShelfID
    let openSource: ShelfOpenSource

    var onClose: (() -> Void)?
    var onToggleExpand: (() -> Void)?
    var onCollapse: (() -> Void)?
    var onSimulateReceive: (() -> Void)?

    private let contentController: ShelfContentViewController
    private let cornerRadius: CGFloat = 16

    private var panel: ShelfPanel { window as! ShelfPanel }

    var styleMask: NSWindow.StyleMask { panel.styleMask }
    var canBecomeKeyWindow: Bool { panel.canBecomeKey }
    var isVisible: Bool { panel.isVisible }
    var isDragDestinationReady: Bool { panel.isVisible }

    private static let emptySize = NSSize(width: 280, height: 220)
    private static let collapsedSize = NSSize(width: 200, height: 160)
    private static let expandedSize = NSSize(width: 420, height: 360)

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
        contentController.onSimulateReceive = { [weak self] in self?.onSimulateReceive?() }
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

    func positionNearMouse(offset: NSPoint = .zero) {
        let size = panel.frame.size
        let origin = ShelfWindowGeometry.originNearMouse(size: size, offset: offset)
        panel.setFrameOrigin(origin)
    }

    /// When `false`, size changes skip `NSWindow` animation (useful for rapid automated toggles).
    var animatesPresentationChanges = true

    func apply(shelf: Shelf) {
        contentController.apply(shelf: shelf)
        resize(for: shelf.presentation, animated: animatesPresentationChanges)
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }

    func windowDidResize(_ notification: Notification) {
        refreshRoundedWindowChrome()
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
                onMilestone(.dragReady)
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
    }

    private func configureContent() {
        let root = NSView(frame: panel.frame)
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.clear.cgColor

        let container = NSVisualEffectView(frame: root.bounds)
        container.material = .hudWindow
        container.blendingMode = .behindWindow
        container.state = .active
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

    private func resize(for presentation: ShelfPresentation, animated: Bool) {
        let size: NSSize
        switch presentation {
        case .empty: size = Self.emptySize
        case .collapsed: size = Self.collapsedSize
        case .expanded: size = Self.expandedSize
        }

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
}
