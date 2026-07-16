import AppKit

@MainActor
final class MenuBarController {
    private var statusItem: NSStatusItem?
    private var languageObserver: NSObjectProtocol?
    private var shortcutBindings: MenuShortcutBindings
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
        shortcutBindings: MenuShortcutBindings,
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
        self.shortcutBindings = shortcutBindings
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
            let image = NSImage(named: "MenuBarIcon")
                ?? NSImage(systemSymbolName: "tray.and.arrow.down.fill", accessibilityDescription: nil)
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
            Task { @MainActor in
                self?.rebuildMenu()
                if let button = self?.statusItem?.button {
                    button.toolTip = L10n.a11yStatusItem
                    button.setAccessibilityLabel(L10n.a11yStatusItem)
                }
            }
        }
    }

    func updateShortcutBindings(_ bindings: MenuShortcutBindings) {
        shortcutBindings = bindings
        rebuildMenu()
    }

    func rebuildMenu() {
        let menu = NSMenu(title: L10n.appName)
        menu.addItem(makeShortcutItem(L10n.newShelf, #selector(newShelf), shortcutBindings.newShelf))
        menu.addItem(makeShortcutItem(L10n.settings, #selector(openSettings), shortcutBindings.openSettings))
        menu.addItem(makePlainItem(L10n.about, #selector(openAbout)))
        menu.addItem(makePlainItem(L10n.showLogs, #selector(openLogs)))
        menu.addItem(.separator())
        #if DEBUG
        menu.addItem(makeKeyItem(L10n.newTransientDemo, #selector(newTransient), "t"))
        menu.addItem(makeKeyItem(L10n.createThreeShelves, #selector(createMultiple), "3"))
        menu.addItem(makePlainItem(L10n.logBenchmarks, #selector(logMetrics)))
        menu.addItem(.separator())
        #endif
        menu.addItem(makePlainItem(L10n.cleanTemporary, #selector(cleanupTemporary)))
        menu.addItem(makeShortcutItem(L10n.closeAllShelves, #selector(closeAll), shortcutBindings.closeAll))
        menu.addItem(.separator())
        let quit = NSMenuItem(
            title: L10n.quit,
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: shortcutBindings.quit.menuKeyEquivalent ?? "q"
        )
        quit.keyEquivalentModifierMask = shortcutBindings.quit.nsModifierFlags
        menu.addItem(quit)
        statusItem?.menu = menu
    }

    private func makeShortcutItem(
        _ title: String,
        _ action: Selector,
        _ chord: ShortcutChord
    ) -> NSMenuItem {
        let menuItem = NSMenuItem(
            title: title,
            action: action,
            keyEquivalent: chord.menuKeyEquivalent ?? ""
        )
        menuItem.target = self
        menuItem.keyEquivalentModifierMask = chord.nsModifierFlags
        return menuItem
    }

    private func makeKeyItem(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
        menuItem.target = self
        return menuItem
    }

    private func makePlainItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: "")
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
