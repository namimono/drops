import AppKit

/// Empty / collapsed / expanded skeleton for Stage 1. Real items arrive in Stage 2.
@MainActor
final class ShelfContentViewController: NSViewController {
    var onCloseRequested: (() -> Void)?
    var onToggleExpand: (() -> Void)?
    var onCollapse: (() -> Void)?
    /// Stage 1 demo hook: simulate receiving one item (also promotes transient shelves).
    var onSimulateReceive: (() -> Void)?

    private let titleLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let bodyLabel = NSTextField(wrappingLabelWithString: "")
    private let expandButton = NSButton(title: "Expand", target: nil, action: nil)
    private let collapseButton = NSButton(title: "Collapse", target: nil, action: nil)
    private let simulateButton = NSButton(title: "Simulate Drop", target: nil, action: nil)
    private let closeButton = NSButton(title: "Close", target: nil, action: nil)

    private var shelfID: ShelfID?
    private var presentation: ShelfPresentation = .empty
    private var lifecycle: ShelfLifecycle = .persistent
    private var itemCount = 0

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 220))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.clear.cgColor
        view = root

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        bodyLabel.font = .systemFont(ofSize: 12)
        bodyLabel.textColor = .labelColor
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false
        bodyLabel.alignment = .center

        configure(button: closeButton, action: #selector(closeTapped))
        configure(button: expandButton, action: #selector(expandTapped))
        configure(button: collapseButton, action: #selector(collapseTapped))
        configure(button: simulateButton, action: #selector(simulateTapped))

        let buttonRow = NSStackView(views: [expandButton, collapseButton, simulateButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8
        buttonRow.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(titleLabel)
        root.addSubview(closeButton)
        root.addSubview(statusLabel)
        root.addSubview(bodyLabel)
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

            bodyLabel.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            bodyLabel.centerYAnchor.constraint(equalTo: root.centerYAnchor, constant: -8),
            bodyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: root.leadingAnchor, constant: 20),
            bodyLabel.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -20),

            buttonRow.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            buttonRow.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -14),
            buttonRow.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -14),
        ])
    }

    func apply(shelf: Shelf) {
        shelfID = shelf.id
        presentation = shelf.presentation
        lifecycle = shelf.lifecycle
        itemCount = shelf.items.count
        refreshLabels()
    }

    private func refreshLabels() {
        let shortID = shelfID.map { String($0.rawValue.uuidString.prefix(8)) } ?? "—"
        titleLabel.stringValue = "Drops · \(shortID)"
        statusLabel.stringValue = "\(lifecycle.rawValue) · \(presentation.rawValue) · \(itemCount) item(s)"

        switch presentation {
        case .empty:
            bodyLabel.stringValue = "Drop or paste your items"
            expandButton.isEnabled = itemCount > 0
            collapseButton.isEnabled = false
        case .collapsed:
            bodyLabel.stringValue = "Collapsed stack · \(itemCount)"
            expandButton.isEnabled = true
            collapseButton.isEnabled = false
        case .expanded:
            bodyLabel.stringValue = "Expanded grid · \(itemCount)"
            expandButton.isEnabled = false
            collapseButton.isEnabled = true
        }
    }

    private func configure(button: NSButton, action: Selector) {
        button.bezelStyle = .inline
        button.font = .systemFont(ofSize: 11, weight: .medium)
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    @objc private func closeTapped() { onCloseRequested?() }
    @objc private func expandTapped() { onToggleExpand?() }
    @objc private func collapseTapped() { onCollapse?() }
    @objc private func simulateTapped() { onSimulateReceive?() }
}
