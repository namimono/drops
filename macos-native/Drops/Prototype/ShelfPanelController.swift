import AppKit

enum ShelfPanelKind {
    case persistent
    case transient
}

/// Borderless floating shelf panel used to validate Stage 0 window and focus assumptions.
@MainActor
final class ShelfPanelController: NSObject, NSWindowDelegate {
    let kind: ShelfPanelKind
    var onClose: (() -> Void)?

    private let panel: NSPanel
    private let contentView: ShelfDropView
    private let titleLabel = NSTextField(labelWithString: "")

    init(kind: ShelfPanelKind) {
        self.kind = kind
        self.contentView = ShelfDropView(frame: NSRect(x: 0, y: 0, width: 280, height: 220))

        let style: NSWindow.StyleMask = [.borderless, .nonactivatingPanel, .resizable]
        panel = NSPanel(
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

    func show() {
        panel.orderFrontRegardless()
        if kind == .persistent {
            // Persistent shelves may become key for keyboard interaction.
            panel.makeKey()
            NSApp.activate(ignoringOtherApps: true)
        }
        // Transient shelves intentionally avoid activation so the drag source keeps focus.
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

        if kind == .transient {
            panel.styleMask.insert(.nonactivatingPanel)
        }
    }

    private func configureContent() {
        let container = NSVisualEffectView(frame: panel.contentView?.bounds ?? .zero)
        container.material = .hudWindow
        container.blendingMode = .behindWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 16
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

        let subtitle = NSTextField(wrappingLabelWithString: "从 Finder 拖文件到下方 · 选中后双击拖出 · 菜单栏托盘图标可开更多窗口")
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

        panel.contentView = container
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
