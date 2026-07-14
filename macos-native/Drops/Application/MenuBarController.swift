import AppKit

@MainActor
final class MenuBarController {
    private var statusItem: NSStatusItem?
    private let onNewShelf: () -> Void
    private let onCreateTransientDemo: () -> Void
    private let onCreateMultiple: () -> Void
    private let onCloseAll: () -> Void
    private let onCleanupTemporary: () -> Void
    private let onConfigureRetention: () -> Void
    private let onLogMetrics: () -> Void

    init(
        onNewShelf: @escaping () -> Void,
        onCreateTransientDemo: @escaping () -> Void,
        onCreateMultiple: @escaping () -> Void,
        onCloseAll: @escaping () -> Void,
        onCleanupTemporary: @escaping () -> Void,
        onConfigureRetention: @escaping () -> Void,
        onLogMetrics: @escaping () -> Void
    ) {
        self.onNewShelf = onNewShelf
        self.onCreateTransientDemo = onCreateTransientDemo
        self.onCreateMultiple = onCreateMultiple
        self.onCloseAll = onCloseAll
        self.onCleanupTemporary = onCleanupTemporary
        self.onConfigureRetention = onConfigureRetention
        self.onLogMetrics = onLogMetrics
    }

    func start() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.isVisible = true
        if let button = item.button {
            let image = NSImage(systemSymbolName: "tray.and.arrow.down.fill", accessibilityDescription: "Drops")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "Drops"
        }

        let menu = NSMenu(title: "Drops")
        menu.addItem(makeItem("New Shelf", #selector(newShelf), "n"))
        menu.addItem(makeItem("New Transient Shelf (Demo)", #selector(newTransient), "t"))
        menu.addItem(makeItem("Create Three Shelves", #selector(createMultiple), "3"))
        menu.addItem(.separator())
        menu.addItem(makeItem("Retention Days…", #selector(configureRetention), ""))
        menu.addItem(makeItem("Clean Temporary Files Now…", #selector(cleanupTemporary), ""))
        menu.addItem(makeItem("Log Performance Benchmarks", #selector(logMetrics), ""))
        menu.addItem(makeItem("Close All Shelves", #selector(closeAll), "w"))
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Drops", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
    }

    private func makeItem(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
        menuItem.target = self
        return menuItem
    }

    @objc private func newShelf() { onNewShelf() }
    @objc private func newTransient() { onCreateTransientDemo() }
    @objc private func createMultiple() { onCreateMultiple() }
    @objc private func closeAll() { onCloseAll() }
    @objc private func cleanupTemporary() { onCleanupTemporary() }
    @objc private func configureRetention() { onConfigureRetention() }
    @objc private func logMetrics() { onLogMetrics() }
}
