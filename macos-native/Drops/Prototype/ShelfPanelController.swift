import AppKit
import QuartzCore

enum ShelfPanelKind {
    case persistent
    case transient
}

enum ShelfShowMilestone: Equatable {
    /// Persistent shelf: first frame has been committed for display.
    case firstFrameVisible
    /// Transient shelf: panel is on-screen and registered to accept file URL drops.
    case dragReady
}

/// Borderless panels default to `canBecomeKey == false`; override so persistent shelves stay interactive.
private final class ShelfPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Borderless floating shelf panel used to validate Stage 0 window and focus assumptions.
@MainActor
final class ShelfPanelController: NSObject, NSWindowDelegate {
    let kind: ShelfPanelKind
    var onClose: (() -> Void)?

    private let panel: ShelfPanel
    private let contentView: ShelfDropView
    private let titleLabel = NSTextField(labelWithString: "")
    private let cornerRadius: CGFloat = 16

    /// Exposed for Stage 0 automated checks (style mask / focus contract).
    var styleMask: NSWindow.StyleMask { panel.styleMask }
    var canBecomeKeyWindow: Bool { panel.canBecomeKey }
    var isVisible: Bool { panel.isVisible }
    var isDragDestinationReady: Bool {
        contentView.window != nil && contentView.registeredDraggedTypes.contains(.fileURL)
    }

    init(kind: ShelfPanelKind) {
        self.kind = kind
        self.contentView = ShelfDropView(frame: NSRect(x: 0, y: 0, width: 280, height: 220))

        // No `.resizable`: resize chrome on borderless panels often draws a square outline (M-01).
        var style: NSWindow.StyleMask = [.borderless]
        if kind == .transient {
            style.insert(.nonactivatingPanel)
        }
        panel = ShelfPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 220),
            styleMask: style,
            backing: .buffered,
            defer: false
        )
        super.init()

        configurePanel()
        configureContent()
        panel.delegate = self
    }

    /// Shows the panel. Invokes `onMilestone` when the Stage 0 latency end-point is reached.
    func show(onMilestone: ((ShelfShowMilestone) -> Void)? = nil) {
        panel.orderFrontRegardless()
        if kind == .persistent {
            panel.makeKey()
            NSApp.activate(ignoringOtherApps: true)
        }
        // Transient shelves intentionally avoid activation so the drag source keeps focus.

        notifyWhenReady(onMilestone)
    }

    func close() {
        panel.close()
    }

    func positionNearMouse(offset: NSPoint = .zero) {
        let mouse = NSEvent.mouseLocation
        let size = panel.frame.size
        let origin = NSPoint(
            x: mouse.x - size.width / 2 + offset.x,
            y: mouse.y - size.height / 2 + offset.y
        )
        panel.setFrameOrigin(clampedOrigin(origin, size: size))
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }

    func windowDidResize(_ notification: Notification) {
        refreshRoundedWindowChrome()
    }

    private func notifyWhenReady(_ onMilestone: ((ShelfShowMilestone) -> Void)?) {
        guard let onMilestone else { return }

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            guard let self else { return }
            self.panel.layoutIfNeeded()
            self.panel.displayIfNeeded()
            self.refreshRoundedWindowChrome()

            switch self.kind {
            case .persistent:
                onMilestone(.firstFrameVisible)
            case .transient:
                if self.isDragDestinationReady {
                    onMilestone(.dragReady)
                } else {
                    DispatchQueue.main.async {
                        onMilestone(.dragReady)
                    }
                }
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
        panel.becomesKeyOnlyIfNeeded = kind == .transient
        panel.animationBehavior = .utilityWindow
    }

    private func configureContent() {
        // Clear root so the rectangular window surface does not paint behind rounded content.
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

        titleLabel.stringValue = kind == .persistent ? "Drops · Persistent Shelf" : "Drops · Transient Shelf"
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let closeButton = NSButton(title: "关闭", target: self, action: #selector(closeFromButton))
        closeButton.bezelStyle = .inline
        closeButton.font = .systemFont(ofSize: 11, weight: .medium)
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        let subtitle = NSTextField(wrappingLabelWithString: "从 Finder 拖文件到下方 · 选中后按住拖出 · 菜单栏托盘图标可开更多窗口")
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        subtitle.translatesAutoresizingMaskIntoConstraints = false

        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.onItemsChanged = { [weak self] count in
            self?.titleLabel.stringValue = "\(self?.kind == .persistent ? "Drops · Persistent" : "Drops · Transient") · \(count) item(s)"
        }

        container.addSubview(titleLabel)
        container.addSubview(closeButton)
        container.addSubview(subtitle)
        container.addSubview(contentView)
        root.addSubview(container)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -8),

            closeButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),

            subtitle.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitle.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitle.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),

            contentView.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 10),
            contentView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            contentView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            contentView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
        ])

        panel.contentView = root
        refreshRoundedWindowChrome()
    }

    /// Keep window shadow / opaque shape matched to the rounded visual-effect surface (S0-04 / M-01).
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

    @objc private func closeFromButton() {
        close()
    }

    private func clampedOrigin(_ origin: NSPoint, size: NSSize) -> NSPoint {
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) })
                ?? NSScreen.main else {
            return origin
        }
        let visible = screen.visibleFrame
        let x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        let y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        return NSPoint(x: x, y: y)
    }
}
