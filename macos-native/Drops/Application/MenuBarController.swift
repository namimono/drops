import AppKit

@MainActor
final class MenuBarController {
    private var statusItem: NSStatusItem?
    private var languageObserver: NSObjectProtocol?
    private let onNewShelf: () -> Void
    private let onOpenSettings: () -> Void
    private let onOpenAbout: () -> Void
    private let onOpenLogs: () -> Void
    private let onCreateTransientDemo: () -> Void
    private let onCreateMultiple: () -> Void
    private let onCloseAll: () -> Void
    private let onCleanupTemporary: () -> Void
    private let onLogMetrics: () -> Void

    init(
        onNewShelf: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onOpenAbout: @escaping () -> Void,
        onOpenLogs: @escaping () -> Void,
        onCreateTransientDemo: @escaping () -> Void,
        onCreateMultiple: @escaping () -> Void,
        onCloseAll: @escaping () -> Void,
        onCleanupTemporary: @escaping () -> Void,
        onLogMetrics: @escaping () -> Void
    ) {
        self.onNewShelf = onNewShelf
        self.onOpenSettings = onOpenSettings
        self.onOpenAbout = onOpenAbout
        self.onOpenLogs = onOpenLogs
        self.onCreateTransientDemo = onCreateTransientDemo
        self.onCreateMultiple = onCreateMultiple
        self.onCloseAll = onCloseAll
        self.onCleanupTemporary = onCleanupTemporary
        self.onLogMetrics = onLogMetrics
    }

    func start() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.isVisible = true
        if let button = item.button {
            let image = NSImage(
                systemSymbolName: "tray.and.arrow.down.fill",
                accessibilityDescription: L10n.a11yStatusItem
            )
            image?.isTemplate = true
            button.image = image
            button.toolTip = L10n.a11yStatusItem
            button.setAccessibilityLabel(L10n.a11yStatusItem)
        }
        statusItem = item
        rebuildMenu()

        languageObserver = NotificationCenter.default.addObserver(
            forName: .dropsLanguageDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.rebuildMenu()
            if let button = self?.statusItem?.button {
                button.toolTip = L10n.a11yStatusItem
                button.setAccessibilityLabel(L10n.a11yStatusItem)
            }
        }
    }

    func rebuildMenu() {
        let menu = NSMenu(title: "Drops")
        menu.addItem(makeItem(L10n.newShelf, #selector(newShelf), "n"))
        menu.addItem(makeItem(L10n.settings, #selector(openSettings), ","))
        menu.addItem(makeItem(L10n.about, #selector(openAbout), ""))
        menu.addItem(makeItem(L10n.showLogs, #selector(openLogs), ""))
        menu.addItem(.separator())
        #if DEBUG
        menu.addItem(makeItem(L10n.newTransientDemo, #selector(newTransient), "t"))
        menu.addItem(makeItem(L10n.createThreeShelves, #selector(createMultiple), "3"))
        menu.addItem(makeItem(L10n.logBenchmarks, #selector(logMetrics), ""))
        menu.addItem(.separator())
        #endif
        menu.addItem(makeItem(L10n.cleanTemporary, #selector(cleanupTemporary), ""))
        menu.addItem(makeItem(L10n.closeAllShelves, #selector(closeAll), "w"))
        menu.addItem(.separator())
        let quit = NSMenuItem(title: L10n.quit, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        statusItem?.menu = menu
    }

    private func makeItem(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
        menuItem.target = self
        return menuItem
    }

    @objc private func newShelf() { onNewShelf() }
    @objc private func openSettings() { onOpenSettings() }
    @objc private func openAbout() { onOpenAbout() }
    @objc private func openLogs() { onOpenLogs() }
    @objc private func newTransient() { onCreateTransientDemo() }
    @objc private func createMultiple() { onCreateMultiple() }
    @objc private func closeAll() { onCloseAll() }
    @objc private func cleanupTemporary() { onCleanupTemporary() }
    @objc private func logMetrics() { onLogMetrics() }
}
