import AppKit

/// Stage 1 application host: menu bar, hotkey, and shelf manager wiring.
@MainActor
final class ApplicationController {
    private let shelfManager = ShelfManager()
    private let hotkeyManager = GlobalHotkeyManager()
    private let metrics = Stage0PerformanceMetrics.shared
    private var menuBar: MenuBarController?

    func start() {
        NSApp.setActivationPolicy(.regular)
        configureMenuBar()
        hotkeyManager.start { [weak self] in
            self?.createPersistentShelf(source: .hotkey)
        }
        NSApp.activate(ignoringOtherApps: true)
        createPersistentShelf(source: .menu)
        NSLog(
            "[Stage1] Ready. Menu bar tray + ⌘⌥Space create shelves. Bundle=%@",
            Bundle.main.bundleIdentifier ?? "unknown"
        )
    }

    func createPersistentShelf(source: ShelfOpenSource) {
        let started = CFAbsoluteTimeGetCurrent()
        _ = shelfManager.createShelf(source: source, nearMouse: true) { [metrics] milestone in
            guard case .firstFrameVisible = milestone else { return }
            metrics.recordPersistentFirstFrame(seconds: CFAbsoluteTimeGetCurrent() - started)
        }
    }

    /// Demo-only: starts a fake drag session so transient lifecycle can be exercised without Stage 2 drag.
    func createTransientDemoShelf() {
        let dragID = DragSessionID("demo-\(UUID().uuidString)")
        shelfManager.beginExternalDrag(dragSessionId: dragID)
        let started = CFAbsoluteTimeGetCurrent()
        let created = shelfManager.createShelf(source: .shake, nearMouse: true) { [metrics] milestone in
            guard case .dragReady = milestone else { return }
            metrics.recordTransientReady(seconds: CFAbsoluteTimeGetCurrent() - started)
        }
        if created == nil {
            shelfManager.endExternalDrag(dragSessionId: dragID)
        }
    }

    func createMultipleShelves() {
        for index in 0..<3 {
            let offset = NSPoint(x: CGFloat(index) * 36, y: CGFloat(index) * -36)
            _ = shelfManager.createShelf(source: .menu, nearMouse: true, mouseOffset: offset)
        }
    }

    func closeAllShelves() {
        shelfManager.closeAll()
    }

    func logBenchmarks() {
        NSLog("%@", metrics.summary())
    }

    var managerForTesting: ShelfManager { shelfManager }

    private func configureMenuBar() {
        let controller = MenuBarController(
            onNewShelf: { [weak self] in self?.createPersistentShelf(source: .menu) },
            onCreateTransientDemo: { [weak self] in self?.createTransientDemoShelf() },
            onCreateMultiple: { [weak self] in self?.createMultipleShelves() },
            onCloseAll: { [weak self] in self?.closeAllShelves() },
            onLogMetrics: { [weak self] in self?.logBenchmarks() }
        )
        controller.start()
        menuBar = controller
    }
}
