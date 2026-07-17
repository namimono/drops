import AppKit

@MainActor
final class MenuBarController: NSObject {
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
        super.init()
    }

    deinit {
        if let languageObserver {
            NotificationCenter.default.removeObserver(languageObserver)
        }
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
    }

    func start() {
        // UIElement / accessory launch: create the status item on the next turn so
        // AppKit has finished applying activation policy (otherwise the item can be dropped).
        DispatchQueue.main.async { [weak self] in
            self?.installStatusItemIfNeeded()
        }
    }

    func updateShortcutBindings(_ bindings: MenuShortcutBindings) {
        shortcutBindings = bindings
        rebuildMenu()
    }

    private func installStatusItemIfNeeded() {
        if statusItem != nil {
            rebuildMenu()
            return
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.isVisible = true
        if let button = item.button {
            button.image = Self.makeMenuBarImage()
            button.imagePosition = .imageOnly
            button.toolTip = L10n.a11yStatusItem
            button.setAccessibilityLabel(L10n.a11yStatusItem)
        } else {
            NSLog("[MenuBar] status item button unavailable")
        }
        statusItem = item
        rebuildMenu()
        NSLog("[MenuBar] status item installed visible=%@", item.isVisible ? "YES" : "NO")
    }

    private static func makeMenuBarImage() -> NSImage {
        if let named = NSImage(named: "MenuBarIcon")?.copy() as? NSImage {
            named.isTemplate = true
            if named.size.width < 1 || named.size.height < 1 {
                named.size = NSSize(width: 18, height: 18)
            }
            return named
        }

        let symbolName = "tray.and.arrow.down.fill"
        if let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: L10n.a11yStatusItem) {
            let configured = symbol.withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            ) ?? symbol
            configured.isTemplate = true
            return configured
        }

        // Last resort: never leave an empty status item.
        let fallback = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            let inset = rect.insetBy(dx: 3, dy: 3)
            NSColor.black.setStroke()
            let path = NSBezierPath(roundedRect: inset, xRadius: 2, yRadius: 2)
            path.lineWidth = 1.5
            path.stroke()
            return true
        }
        fallback.isTemplate = true
        return fallback
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

        if let button = statusItem?.button {
            button.toolTip = L10n.a11yStatusItem
            button.setAccessibilityLabel(L10n.a11yStatusItem)
        }
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
