import AppKit

/// Stage 3 application host: menu bar, settings/about, hotkey, shake drag, shelves.
@MainActor
final class ApplicationController {
    private let shelfManager = ShelfManager()
    private let hotkeyManager = GlobalHotkeyManager()
    private var inputCoordinator: GlobalInputCoordinator?
    private let metrics = Stage0PerformanceMetrics.shared
    private var menuBar: MenuBarController?
    private var settingsWindow: SettingsWindowController?
    private var aboutWindow: AboutWindowController?
    private let logStore: AppLogStore?

    /// Override in tests to avoid modal alerts. Default presents a confirmation dialog.
    var shouldProceedWithManualCleanup: () -> Bool = ApplicationController.defaultCleanupConfirmation

    /// Override in tests. Default presents an input dialog for retention days.
    var promptForRetentionDays: (_ current: Int) -> Int? = ApplicationController.defaultRetentionPrompt

    /// Override in tests to suppress result / error alerts.
    var presentUserMessage: (_ title: String, _ message: String, _ style: NSAlert.Style) -> Void =
        ApplicationController.defaultPresentUserMessage

    init() {
        do {
            logStore = try AppLogStore()
        } catch {
            logStore = nil
            NSLog("[Stage3] log store unavailable: %@", "\(error)")
        }
    }

    func start() {
        NSApp.setActivationPolicy(.regular)
        AppLocalization.applyStoredOverride(shelfManager.settingsStore.languageOverride)
        shelfManager.onUserFacingError = { [weak self] title, message in
            self?.presentUserMessage(title, message, .warning)
        }
        configureMenuBar()
        hotkeyManager.start { [weak self] in
            self?.createPersistentShelf(source: .hotkey)
        }
        configureInputCoordinator()
        shelfManager.retentionScheduler?.start()
        if shelfManager.isTemporaryStoreUnavailable {
            NSLog("[Stage3] Managed temporary storage unavailable; paste/materialize disabled.")
            logStore?.append("Managed temporary storage unavailable")
        }
        NSLog(
            "[Stage3] Ready. Menu/⌘⌥Space create shelves; Settings/About in menu bar. Bundle=%@",
            Bundle.main.bundleIdentifier ?? "unknown"
        )
        logStore?.append("Application started language=\(AppLocalization.effectiveLanguageCode)")
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

    func openSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(
                settings: shelfManager.settingsStore,
                onRetentionChanged: { [weak self] days in
                    guard let self else { return days }
                    return try self.shelfManager.updateRetentionDays(days)
                },
                onDisplayModeChanged: { [weak self] mode in
                    self?.shelfManager.setDisplayMode(mode)
                },
                onLanguageChanged: { [weak self] language in
                    self?.shelfManager.settingsStore.setLanguageOverride(language)
                    AppLocalization.languageOverride = language
                },
                onCleanupRequested: { [weak self] in
                    self?.cleanupTemporaryFilesNow()
                }
            )
        }
        settingsWindow?.showSettings()
    }

    func openAbout() {
        if aboutWindow == nil {
            aboutWindow = AboutWindowController()
        }
        aboutWindow?.showAbout()
    }

    func openLogs() {
        guard let logStore else {
            presentUserMessage(L10n.logsUnavailable, L10n.logsUnavailableBody, .warning)
            return
        }
        logStore.append("Opened logs from menu")
        NSWorkspace.shared.activateFileViewerSelecting([logStore.logFileURL])
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
            logStore?.append(
                "Manual cleanup deleted=\(result.deleted.count) skipped=\(result.skippedReferenced)"
            )
            presentUserMessage(
                L10n.cleanResultTitle,
                L10n.cleanResultBody(deleted: result.deleted.count, skipped: result.skippedReferenced),
                .informational
            )
        } catch {
            NSSound.beep()
            NSLog("[Retention] manual cleanup failed: %@", "\(error)")
            presentUserMessage(L10n.cleanupFailed, error.localizedDescription, .warning)
        }
    }

    func configureRetentionDays() {
        guard let entered = promptForRetentionDays(shelfManager.retentionDays) else { return }
        do {
            let applied = try shelfManager.updateRetentionDays(entered)
            presentUserMessage(
                L10n.retentionUpdated,
                L10n.retentionUpdatedBody(applied),
                .informational
            )
        } catch {
            NSSound.beep()
            presentUserMessage(
                L10n.invalidRetention,
                L10n.invalidRetentionBody(shelfManager.retentionDays),
                .warning
            )
            NSLog("[Settings] retention update rejected: %@", "\(error)")
        }
    }

    func logBenchmarks() {
        NSLog("%@", metrics.summary())
        logStore?.append(metrics.summary())
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
            onOpenSettings: { [weak self] in self?.openSettings() },
            onOpenAbout: { [weak self] in self?.openAbout() },
            onOpenLogs: { [weak self] in self?.openLogs() },
            onCreateTransientDemo: { [weak self] in self?.createTransientDemoShelf() },
            onCreateMultiple: { [weak self] in self?.createMultipleShelves() },
            onCloseAll: { [weak self] in self?.closeAllShelves() },
            onCleanupTemporary: { [weak self] in self?.cleanupTemporaryFilesNow() },
            onLogMetrics: { [weak self] in self?.logBenchmarks() }
        )
        controller.start()
        menuBar = controller
    }

    private static func defaultCleanupConfirmation() -> Bool {
        let alert = NSAlert()
        alert.messageText = L10n.cleanConfirmTitle
        alert.informativeText = L10n.cleanConfirmBody
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.cleanNow)
        alert.addButton(withTitle: L10n.cancel)
        return alert.runModal() == .alertFirstButtonReturn
    }

    private static func defaultRetentionPrompt(current: Int) -> Int? {
        let alert = NSAlert()
        alert.messageText = L10n.settingsRetention
        alert.informativeText = L10n.retentionUpdatedBody(current)
        alert.alertStyle = .informational
        let field = NSTextField(string: "\(current)")
        field.frame = NSRect(x: 0, y: 0, width: 220, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: L10n.settingsSave)
        alert.addButton(withTitle: L10n.cancel)
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
