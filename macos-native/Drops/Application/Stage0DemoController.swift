import AppKit

/// Stage 0 interactive harness: menu bar + auto-shown shelf so the prototype is discoverable.
@MainActor
final class Stage0DemoController {
    private var statusItem: NSStatusItem?
    private var shelves: [ShelfPanelController] = []
    private let metrics = Stage0PerformanceMetrics.shared

    func start() {
        // Stage 0: appear in Dock so the running app is obvious during validation.
        NSApp.setActivationPolicy(.regular)
        configureStatusItem()
        NSApp.activate(ignoringOtherApps: true)
        createPersistentShelf()
        NSLog("[Stage0] Demo ready. Look for Dock icon 'Drops' or menu-bar tray icon. Bundle=%@",
              Bundle.main.bundleIdentifier ?? "unknown")
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.isVisible = true
        if let button = item.button {
            let image = NSImage(systemSymbolName: "tray.and.arrow.down.fill", accessibilityDescription: "Drops")
            image?.isTemplate = true
            button.image = image
            button.title = ""
            button.toolTip = "Drops Stage 0 — click for demo actions"
        }

        let menu = NSMenu(title: "Drops")
        menu.addItem(makeItem("New Persistent Shelf", #selector(createPersistentShelf), "n"))
        menu.addItem(makeItem("New Transient Shelf (No Activate)", #selector(createTransientShelf), "t"))
        menu.addItem(makeItem("Create Three Independent Shelves", #selector(createMultipleShelves), "3"))
        menu.addItem(.separator())
        menu.addItem(makeItem("Log Performance Benchmarks", #selector(logBenchmarks), ""))
        menu.addItem(makeItem("Close All Shelves", #selector(closeAllShelves), "w"))
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Drops", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
    }

    private func makeItem(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func createPersistentShelf() {
        let started = CFAbsoluteTimeGetCurrent()
        let shelf = makeShelf(kind: .persistent, nearMouse: true)
        shelves.append(shelf)
        shelf.show()
        metrics.recordPersistentFirstFrame(seconds: CFAbsoluteTimeGetCurrent() - started)
    }

    @objc private func createTransientShelf() {
        let started = CFAbsoluteTimeGetCurrent()
        let shelf = makeShelf(kind: .transient, nearMouse: true)
        shelves.append(shelf)
        shelf.show()
        metrics.recordTransientReady(seconds: CFAbsoluteTimeGetCurrent() - started)
    }

    @objc private func createMultipleShelves() {
        for index in 0..<3 {
            let offset = NSPoint(x: CGFloat(index) * 36, y: CGFloat(index) * -36)
            let shelf = makeShelf(kind: .persistent, nearMouse: true, mouseOffset: offset)
            shelves.append(shelf)
            shelf.show()
        }
    }

    @objc private func closeAllShelves() {
        shelves.forEach { $0.close() }
        shelves.removeAll()
    }

    @objc private func logBenchmarks() {
        NSLog("%@", metrics.summary())
    }

    private func makeShelf(
        kind: ShelfPanelKind,
        nearMouse: Bool,
        mouseOffset: NSPoint = .zero
    ) -> ShelfPanelController {
        let shelf = ShelfPanelController(kind: kind)
        shelf.onClose = { [weak self, weak shelf] in
            guard let self, let shelf else { return }
            self.shelves.removeAll { $0 === shelf }
        }
        if nearMouse {
            shelf.positionNearMouse(offset: mouseOffset)
        }
        return shelf
    }
}
