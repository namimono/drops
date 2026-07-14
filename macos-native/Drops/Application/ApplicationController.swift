import AppKit

/// Stage 2 application host: menu bar, hotkey, shake drag, shelf manager, retention.
@MainActor
final class ApplicationController {
    private let shelfManager = ShelfManager()
    private let hotkeyManager = GlobalHotkeyManager()
    private var inputCoordinator: GlobalInputCoordinator?
    private let metrics = Stage0PerformanceMetrics.shared
    private var menuBar: MenuBarController?

    /// Override in tests to avoid modal alerts. Default presents a confirmation dialog.
    var shouldProceedWithManualCleanup: () -> Bool = ApplicationController.defaultCleanupConfirmation

    /// Override in tests. Default presents an input dialog for retention days.
    var promptForRetentionDays: (_ current: Int) -> Int? = ApplicationController.defaultRetentionPrompt

    /// Override in tests to suppress result / error alerts.
    var presentUserMessage: (_ title: String, _ message: String, _ style: NSAlert.Style) -> Void =
        ApplicationController.defaultPresentUserMessage

    func start() {
        NSApp.setActivationPolicy(.regular)
        configureMenuBar()
        hotkeyManager.start { [weak self] in
            self?.createPersistentShelf(source: .hotkey)
        }
        configureInputCoordinator()
        shelfManager.retentionScheduler?.start()
        if shelfManager.isTemporaryStoreUnavailable {
            NSLog("[Stage2] Managed temporary storage unavailable; paste/materialize disabled.")
        }
        NSLog(
            "[Stage2] Ready. Menu/⌘⌥Space create shelves; shake or Shift while dragging summons transient. Bundle=%@",
            Bundle.main.bundleIdentifier ?? "unknown"
        )
    }

    func prepareForTermination() {
        shelfManager.prepareForTermination()
    }

    func createPersistentShelf(source: ShelfOpenSource) {
        let started = CFAbsoluteTimeGetCurrent()
        _ = shelfManager.createShelf(source: source, nearMouse: true) { [metrics] milestone in
            guard case .firstFrameVisible = milestone else { return }
            metrics.recordPersistentFirstFrame(seconds: CFAbsoluteTimeGetCurrent() - started)
        }
    }

    /// Demo-only: starts a fake drag session so transient lifecycle can be exercised without real Finder drag.
    func createTransientDemoShelf() {
        let dragID = DragSessionID("demo-\(UUID().uuidString)")
        shelfManager.beginExternalDrag(dragSessionId: dragID)
        let started = CFAbsoluteTimeGetCurrent()
        let created = shelfManager.createShelf(source: .shake, nearMouse: true) { [metrics] milestone in
            if case .dragReady = milestone {
                metrics.recordTransientReady(seconds: CFAbsoluteTimeGetCurrent() - started)
            }
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

    func cleanupTemporaryFilesNow() {
        guard shouldProceedWithManualCleanup() else { return }
        do {
            let result = try shelfManager.cleanupTemporaryFilesNow()
            NSLog(
                "[Retention] manual cleanup deleted=%d skippedReferenced=%d",
                result.deleted.count,
                result.skippedReferenced
            )
            presentUserMessage(
                "Temporary files cleaned",
                "Deleted \(result.deleted.count). Skipped \(result.skippedReferenced) still referenced.",
                .informational
            )
        } catch {
            NSSound.beep()
            NSLog("[Retention] manual cleanup failed: %@", "\(error)")
            presentUserMessage("Cleanup Failed", error.localizedDescription, .warning)
        }
    }

    func configureRetentionDays() {
        guard let entered = promptForRetentionDays(shelfManager.retentionDays) else { return }
        do {
            let applied = try shelfManager.updateRetentionDays(entered)
            presentUserMessage(
                "Retention Updated",
                "Temporary files are kept for \(applied) day(s).",
                .informational
            )
        } catch {
            NSSound.beep()
            presentUserMessage(
                "Invalid Retention Days",
                "Please enter a whole number from 1 to 120. The previous value (\(shelfManager.retentionDays)) was kept.",
                .warning
            )
            NSLog("[Settings] retention update rejected: %@", "\(error)")
        }
    }

    func logBenchmarks() {
        NSLog("%@", metrics.summary())
    }

    var managerForTesting: ShelfManager { shelfManager }

    private func configureInputCoordinator() {
        let coordinator = GlobalInputCoordinator(
            onBeginExternalDrag: { [weak self] id in
                self?.shelfManager.beginExternalDrag(dragSessionId: id)
            },
            onShake: { [weak self] location, id in
                self?.createShakeShelf(at: location, dragSessionId: id)
            },
            onEndExternalDrag: { [weak self] id in
                self?.shelfManager.endExternalDrag(dragSessionId: id)
            }
        )
        coordinator.start()
        inputCoordinator = coordinator
    }

    private func createShakeShelf(at location: NSPoint, dragSessionId: DragSessionID) {
        guard shelfManager.currentDragSessionId == dragSessionId else { return }
        let started = CFAbsoluteTimeGetCurrent()
        _ = shelfManager.createShelf(
            source: .shake,
            nearMouse: true,
            mouseLocation: location
        ) { [metrics] milestone in
            if case .dragReady = milestone {
                metrics.recordTransientReady(seconds: CFAbsoluteTimeGetCurrent() - started)
            }
        }
    }

    private func configureMenuBar() {
        let controller = MenuBarController(
            onNewShelf: { [weak self] in self?.createPersistentShelf(source: .menu) },
            onCreateTransientDemo: { [weak self] in self?.createTransientDemoShelf() },
            onCreateMultiple: { [weak self] in self?.createMultipleShelves() },
            onCloseAll: { [weak self] in self?.closeAllShelves() },
            onCleanupTemporary: { [weak self] in self?.cleanupTemporaryFilesNow() },
            onConfigureRetention: { [weak self] in self?.configureRetentionDays() },
            onLogMetrics: { [weak self] in self?.logBenchmarks() }
        )
        controller.start()
        menuBar = controller
    }

    private static func defaultCleanupConfirmation() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Clean Temporary Files?"
        alert.informativeText =
            "Delete managed temporary files that are not referenced by any open shelf. This cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clean Now")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private static func defaultRetentionPrompt(current: Int) -> Int? {
        let alert = NSAlert()
        alert.messageText = "Temporary File Retention"
        alert.informativeText = "Enter retention days (1–120). Current: \(current)."
        alert.alertStyle = .informational
        let field = NSTextField(string: "\(current)")
        field.frame = NSRect(x: 0, y: 0, width: 220, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let trimmed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return Int(trimmed)
    }

    private static func defaultPresentUserMessage(
        title: String,
        message: String,
        style: NSAlert.Style
    ) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style
        alert.runModal()
    }
}
