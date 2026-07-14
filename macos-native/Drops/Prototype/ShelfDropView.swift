import AppKit

/// Minimal drag destination/source used to prove Finder drag-in / drag-out for Stage 0.
final class ShelfDropView: NSView, NSDraggingSource {
    private(set) var fileURLs: [URL] = []
    var onItemsChanged: ((Int) -> Void)?

    private let listView = NSTableView()
    private let scrollView = NSScrollView()
    private var isReceivingDrag = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.55).cgColor
        registerForDraggedTypes([.fileURL])
        configureTable()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if isReceivingDrag {
            NSColor.systemBlue.withAlphaComponent(0.25).setFill()
            dirtyRect.fill()
            NSColor.systemBlue.setStroke()
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5), xRadius: 10, yRadius: 10)
            path.lineWidth = 2
            path.stroke()
        }
    }

    // MARK: - Drag destination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard canAccept(sender) else { return [] }
        isReceivingDrag = true
        needsDisplay = true
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        canAccept(sender) ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isReceivingDrag = false
        needsDisplay = true
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        canAccept(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isReceivingDrag = false
        needsDisplay = true
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL], !urls.isEmpty else {
            return false
        }

        for url in urls {
            if !fileURLs.contains(url) {
                fileURLs.insert(url, at: 0)
            } else if let index = fileURLs.firstIndex(of: url) {
                fileURLs.remove(at: index)
                fileURLs.insert(url, at: 0)
            }
        }
        reload()
        NSLog("[Stage0][DragIn] accepted %d URL(s); shelf now has %d", urls.count, fileURLs.count)
        return true
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        isReceivingDrag = false
        needsDisplay = true
    }

    // MARK: - Drag source (NSTableView row drag + fallback)

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        [.copy, .move]
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        handleDragOutEnded(session: session, operation: operation)
    }

    // MARK: - Private

    private func configureTable() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("path"))
        column.title = "Items"
        column.width = 200
        listView.addTableColumn(column)
        listView.headerView = nil
        listView.delegate = self
        listView.dataSource = self
        listView.rowHeight = 24
        listView.backgroundColor = .clear
        listView.selectionHighlightStyle = .regular
        // Standard click-and-drag out (not double-click). Double-click open is Stage 3.
        listView.setDraggingSourceOperationMask([.copy, .move], forLocal: false)
        listView.setDraggingSourceOperationMask([.copy, .move], forLocal: true)

        scrollView.documentView = listView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
    }

    private func canAccept(_ sender: NSDraggingInfo) -> Bool {
        sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ])
    }

    private func reload() {
        listView.reloadData()
        onItemsChanged?(fileURLs.count)
    }

    private func handleDragOutEnded(session: NSDraggingSession, operation: NSDragOperation) {
        let label: String
        if operation.contains(.move) {
            label = "move"
            if let urls = session.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] {
                fileURLs.removeAll { urls.contains($0) }
                reload()
            }
        } else if operation.contains(.copy) {
            label = "copy"
        } else if operation == [] {
            label = "cancel"
        } else {
            label = "other(\(operation.rawValue))"
        }
        NSLog("[Stage0][DragOut] operation=%@ remaining=%d", label, fileURLs.count)
    }
}

extension ShelfDropView: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        fileURLs.count
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
        label.stringValue = fileURLs[row].lastPathComponent
        return label
    }

    /// Enables click-and-hold drag from a row (Finder-style), without requiring double-click.
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
        guard fileURLs.indices.contains(row) else { return nil }
        return fileURLs[row] as NSURL
    }

    func tableView(
        _ tableView: NSTableView,
        draggingSession session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        handleDragOutEnded(session: session, operation: operation)
    }
}
