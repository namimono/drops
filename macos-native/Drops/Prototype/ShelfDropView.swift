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

    // MARK: - Drag source

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        [.copy, .move]
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
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
        listView.doubleAction = #selector(beginDragFromSelection)
        listView.target = self

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

    @objc private func beginDragFromSelection() {
        let indexes = listView.selectedRowIndexes
        guard !indexes.isEmpty else { return }
        let urls = indexes.compactMap { fileURLs.indices.contains($0) ? fileURLs[$0] : nil }
        guard !urls.isEmpty else { return }

        let draggingItems = urls.map { url -> NSDraggingItem in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            item.setDraggingFrame(NSRect(x: 0, y: 0, width: 64, height: 64), contents: NSImage(named: NSImage.folderName))
            return item
        }
        beginDraggingSession(with: draggingItems, event: NSApp.currentEvent ?? NSEvent(), source: self)
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
}
