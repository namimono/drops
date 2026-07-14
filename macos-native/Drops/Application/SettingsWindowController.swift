import AppKit
import SwiftUI

/// Stage 3 settings surface: retention, language, display defaults.
@MainActor
final class SettingsWindowController: NSWindowController {
    private let settings: SettingsStore
    private let onRetentionChanged: (Int) throws -> Int
    private let onDisplayModeChanged: (ShelfDisplayMode) -> Void
    private let onLanguageChanged: (SettingsStore.LanguageOverride) -> Void
    private let onCleanupRequested: () -> Void

    init(
        settings: SettingsStore,
        onRetentionChanged: @escaping (Int) throws -> Int,
        onDisplayModeChanged: @escaping (ShelfDisplayMode) -> Void,
        onLanguageChanged: @escaping (SettingsStore.LanguageOverride) -> Void,
        onCleanupRequested: @escaping () -> Void
    ) {
        self.settings = settings
        self.onRetentionChanged = onRetentionChanged
        self.onDisplayModeChanged = onDisplayModeChanged
        self.onLanguageChanged = onLanguageChanged
        self.onCleanupRequested = onCleanupRequested

        let hosting = NSHostingController(
            rootView: SettingsRootView(
                retentionDays: settings.retentionDays,
                language: settings.languageOverride,
                displayMode: settings.displayMode,
                onSaveRetention: { days in
                    _ = try onRetentionChanged(days)
                },
                onLanguageChange: onLanguageChanged,
                onDisplayModeChange: onDisplayModeChanged,
                onCleanup: onCleanupRequested
            )
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 400),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.settingsWindowTitle
        window.contentViewController = hosting
        window.center()
        super.init(window: window)

        NotificationCenter.default.addObserver(
            forName: .dropsLanguageDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.window?.title = L10n.settingsWindowTitle
            self?.reloadRootView()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showSettings() {
        window?.title = L10n.settingsWindowTitle
        reloadRootView()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func reloadRootView() {
        window?.contentViewController = NSHostingController(
            rootView: SettingsRootView(
                retentionDays: settings.retentionDays,
                language: settings.languageOverride,
                displayMode: settings.displayMode,
                onSaveRetention: { [onRetentionChanged] days in
                    _ = try onRetentionChanged(days)
                },
                onLanguageChange: onLanguageChanged,
                onDisplayModeChange: onDisplayModeChanged,
                onCleanup: onCleanupRequested
            )
        )
    }
}

private struct SettingsRootView: View {
    @State var retentionDays: Int
    @State var language: SettingsStore.LanguageOverride
    @State var displayMode: ShelfDisplayMode
    @State var retentionError: String?

    let onSaveRetention: (Int) throws -> Void
    let onLanguageChange: (SettingsStore.LanguageOverride) -> Void
    let onDisplayModeChange: (ShelfDisplayMode) -> Void
    let onCleanup: () -> Void

    var body: some View {
        Form {
            Section(header: Text(L10n.settingsGeneral)) {
                HStack {
                    Text(L10n.settingsRetention)
                    Spacer()
                    TextField("", value: $retentionDays, formatter: NumberFormatter())
                        .frame(width: 64)
                    Button(L10n.settingsSave) {
                        do {
                            try onSaveRetention(retentionDays)
                            retentionError = nil
                        } catch {
                            retentionError = L10n.settingsRetentionError
                        }
                    }
                }
                if let retentionError {
                    Text(retentionError)
                        .foregroundColor(.red)
                        .font(.caption)
                }

                Picker(L10n.settingsDefaultView, selection: $displayMode) {
                    Text(L10n.grid).tag(ShelfDisplayMode.grid)
                    Text(L10n.list).tag(ShelfDisplayMode.list)
                }
                .onChange(of: displayMode) { newValue in
                    onDisplayModeChange(newValue)
                }

                Picker(L10n.settingsLanguage, selection: $language) {
                    Text(L10n.settingsLanguageSystem).tag(SettingsStore.LanguageOverride.system)
                    Text(L10n.settingsLanguageEnglish).tag(SettingsStore.LanguageOverride.english)
                    Text(L10n.settingsLanguageChinese).tag(SettingsStore.LanguageOverride.simplifiedChinese)
                }
                .onChange(of: language) { newValue in
                    onLanguageChange(newValue)
                }

                Text(L10n.settingsLanguageRestartHint)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section(header: Text(L10n.settingsMaintenance)) {
                Button(L10n.cleanTemporary, action: onCleanup)
                Text(L10n.settingsCleanupHint)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section(header: Text(L10n.settingsSecurity)) {
                Text(L10n.settingsSecurityBody)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
        .frame(minWidth: 420, minHeight: 360)
    }
}
