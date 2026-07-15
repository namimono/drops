import AppKit

/// Overlapping icon stack for collapsed shelves (PRD 5.3.1: show at most 3 icons).
@MainActor
final class CollapsedStackView: NSView {
    var onBeginDrag: ((NSEvent) -> Void)?
    var onExpand: (() -> Void)?

    private let iconViews: [NSImageView] = (0..<3).map { _ in
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.wantsLayer = true
        view.layer?.cornerRadius = 8
        view.layer?.masksToBounds = true
        view.layer?.borderWidth = 1
        view.layer?.borderColor = NSColor.separatorColor.cgColor
        return view
    }

    private var mouseDownEvent: NSEvent?
    private var itemCount = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        for icon in iconViews {
            icon.translatesAutoresizingMaskIntoConstraints = false
            addSubview(icon)
            icon.isHidden = true
        }
        // Back-to-front stacking around the center of the compact overlay.
        NSLayoutConstraint.activate([
            iconViews[2].centerXAnchor.constraint(equalTo: centerXAnchor, constant: 11),
            iconViews[2].centerYAnchor.constraint(equalTo: centerYAnchor, constant: 1),
            iconViews[2].widthAnchor.constraint(equalToConstant: 52),
            iconViews[2].heightAnchor.constraint(equalToConstant: 52),

            iconViews[1].centerXAnchor.constraint(equalTo: centerXAnchor, constant: 4),
            iconViews[1].centerYAnchor.constraint(equalTo: centerYAnchor, constant: 5),
            iconViews[1].widthAnchor.constraint(equalToConstant: 56),
            iconViews[1].heightAnchor.constraint(equalToConstant: 56),

            iconViews[0].centerXAnchor.constraint(equalTo: centerXAnchor, constant: -4),
            iconViews[0].centerYAnchor.constraint(equalTo: centerYAnchor, constant: 9),
            iconViews[0].widthAnchor.constraint(equalToConstant: 60),
            iconViews[0].heightAnchor.constraint(equalToConstant: 60),
        ])

        setAccessibilityElement(true)
        setAccessibilityRole(.group)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(items: [ShelfItem]) {
        itemCount = items.count
        let visible = Array(items.prefix(3))
        for (index, iconView) in iconViews.enumerated() {
            if index < visible.count {
                let item = visible[index]
                iconView.isHidden = false
                iconView.image = ShelfItemIconProvider.icon(for: item, size: 48)
                iconView.toolTip = item.displayName
                let expectedID = item.id
                ShelfItemIconProvider.requestThumbnail(for: item, size: 48) { [weak iconView] image in
                    // Identity is per-slot; only apply if still showing the same tip item.
                    guard let image, index < items.prefix(3).count,
                          items[index].id == expectedID else { return }
                    iconView?.image = image
                }
            } else {
                iconView.isHidden = true
                iconView.image = nil
            }
        }
        // z-order: later icons behind earlier ones.
        iconViews[2].layer?.zPosition = 0
        iconViews[1].layer?.zPosition = 1
        iconViews[0].layer?.zPosition = 2

        setAccessibilityLabel(L10n.a11yCollapsedCount(itemCount))
        setAccessibilityHelp(L10n.a11yCollapsedStack)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
    }

    override func mouseDragged(with event: NSEvent) {
        guard let mouseDownEvent else { return }
        let start = mouseDownEvent.locationInWindow
        let current = event.locationInWindow
        if hypot(current.x - start.x, current.y - start.y) >= 4 {
            onBeginDrag?(mouseDownEvent)
            self.mouseDownEvent = nil
        }
    }

    override func mouseUp(with event: NSEvent) {
        if mouseDownEvent != nil, event.clickCount == 2 {
            onExpand?()
        }
        mouseDownEvent = nil
    }

    override func updateLayer() {
        super.updateLayer()
        for icon in iconViews {
            icon.layer?.borderColor = NSColor.separatorColor.cgColor
            icon.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        }
    }

    override var wantsUpdateLayer: Bool { true }
}
