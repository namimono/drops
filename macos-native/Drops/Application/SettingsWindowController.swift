import AppKit
import SwiftUI

/// Settings surface: general prefs, shake sensitivity, and configurable shortcuts.
@MainActor
final class SettingsWindowController: NSWindowController {
    private let settings: SettingsStore
    private let onRetentionChanged: (Int) throws -> Int
    private let onDisplayModeChanged: (ShelfDisplayMode) -> Void
    private let onLanguageChanged: (SettingsStore.LanguageOverride) -> Void
    private let onShakeSensitivityChanged: (SettingsStore.ShakeSensitivity) -> Void
    private let onHotkeyChanged: () -> Void
    private let onMenuShortcutsChanged: () -> Void
    private let onCleanupRequested: () -> Void

    init(
        settings: SettingsStore,
        onRetentionChanged: @escaping (Int) throws -> Int,
        onDisplayModeChanged: @escaping (ShelfDisplayMode) -> Void,
        onLanguageChanged: @escaping (SettingsStore.LanguageOverride) -> Void,
        onShakeSensitivityChanged: @escaping (SettingsStore.ShakeSensitivity) -> Void,
        onHotkeyChanged: @escaping () -> Void,
        onMenuShortcutsChanged: @escaping () -> Void,
        onCleanupRequested: @escaping () -> Void
    ) {
        self.settings = settings
        self.onRetentionChanged = onRetentionChanged
        self.onDisplayModeChanged = onDisplayModeChanged
        self.onLanguageChanged = onLanguageChanged
        self.onShakeSensitivityChanged = onShakeSensitivityChanged
        self.onHotkeyChanged = onHotkeyChanged
        self.onMenuShortcutsChanged = onMenuShortcutsChanged
        self.onCleanupRequested = onCleanupRequested

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.settingsWindowTitle
        window.center()
        super.init(window: window)

        reloadRootView()

        NotificationCenter.default.addObserver(
            forName: .dropsLanguageDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.window?.title = L10n.settingsWindowTitle
                self?.reloadRootView()
            }
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
        window?.contentViewController = NSHostingController(rootView: makeRootView())
    }

    private func makeRootView() -> SettingsRootView {
        SettingsRootView(
            retentionDays: settings.retentionDays,
            language: settings.languageOverride,
            displayMode: settings.displayMode,
            shakeSensitivity: settings.shakeSensitivity,
            globalHotkeyEnabled: settings.globalHotkeyEnabled,
            shortcutChords: Dictionary(
                uniqueKeysWithValues: SettingsStore.ShortcutAction.allCases.map {
                    ($0, settings.chordFor($0))
                }
            ),
            onSaveRetention: { [onRetentionChanged] days in
                _ = try onRetentionChanged(days)
            },
            onLanguageChange: onLanguageChanged,
            onDisplayModeChange: onDisplayModeChanged,
            onShakeSensitivityChange: { [settings, onShakeSensitivityChanged] value in
                settings.setShakeSensitivity(value)
                onShakeSensitivityChanged(value)
            },
            onGlobalHotkeyEnabledChange: { [settings, onHotkeyChanged] enabled in
                settings.setGlobalHotkeyEnabled(enabled)
                onHotkeyChanged()
            },
            onShortcutChange: { [settings, onHotkeyChanged, onMenuShortcutsChanged] action, chord in
                let accepted = settings.setShortcut(action, chord: chord)
                if accepted {
                    if action.isGlobal {
                        onHotkeyChanged()
                    } else {
                        onMenuShortcutsChanged()
                    }
                }
                return accepted
            },
            onResetShortcut: { [settings, onHotkeyChanged, onMenuShortcutsChanged] action in
                settings.resetShortcut(action)
                if action.isGlobal {
                    onHotkeyChanged()
                } else {
                    onMenuShortcutsChanged()
                }
            },
            onResetAllShortcuts: { [settings, onHotkeyChanged, onMenuShortcutsChanged] in
                settings.resetAllShortcuts()
                onHotkeyChanged()
                onMenuShortcutsChanged()
            },
            onCleanup: onCleanupRequested
        )
    }
}

private struct SettingsRootView: View {
    @State var retentionDays: Int
    @State var language: SettingsStore.LanguageOverride
    @State var displayMode: ShelfDisplayMode
    @State var shakeSensitivity: SettingsStore.ShakeSensitivity
    @State var globalHotkeyEnabled: Bool
    @State var shortcutChords: [SettingsStore.ShortcutAction: ShortcutChord]
    @State var retentionError: String?
    @State var shortcutError: String?
    @State var recordingAction: SettingsStore.ShortcutAction?

    let onSaveRetention: (Int) throws -> Void
    let onLanguageChange: (SettingsStore.LanguageOverride) -> Void
    let onDisplayModeChange: (ShelfDisplayMode) -> Void
    let onShakeSensitivityChange: (SettingsStore.ShakeSensitivity) -> Void
    let onGlobalHotkeyEnabledChange: (Bool) -> Void
    let onShortcutChange: (SettingsStore.ShortcutAction, ShortcutChord) -> Bool
    let onResetShortcut: (SettingsStore.ShortcutAction) -> Void
    let onResetAllShortcuts: () -> Void
    let onCleanup: () -> Void

    var body: some View {
        Form {
            Section {
                Picker(L10n.settingsShakeSensitivity, selection: $shakeSensitivity) {
                    Text(L10n.settingsShakeLow).tag(SettingsStore.ShakeSensitivity.low)
                    Text(L10n.settingsShakeMedium).tag(SettingsStore.ShakeSensitivity.medium)
                    Text(L10n.settingsShakeHigh).tag(SettingsStore.ShakeSensitivity.high)
                }
                .onChange(of: shakeSensitivity) { newValue in
                    onShakeSensitivityChange(newValue)
                }

                Text(L10n.settingsShakeHint)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text(L10n.settingsInteraction)
            }

            Section {
                Toggle(L10n.settingsHotkeyEnabled, isOn: $globalHotkeyEnabled)
                    .onChange(of: globalHotkeyEnabled) { newValue in
                        onGlobalHotkeyEnabledChange(newValue)
                    }

                ForEach(SettingsStore.ShortcutAction.allCases) { action in
                    shortcutRow(for: action)
                }

                if let shortcutError {
                    Text(shortcutError)
                        .foregroundColor(.red)
                        .font(.caption)
                }

                Text(L10n.settingsHotkeyHint)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Spacer()
                    Button(L10n.settingsResetAllShortcuts) {
                        onResetAllShortcuts()
                        for action in SettingsStore.ShortcutAction.allCases {
                            shortcutChords[action] = action.defaultChord
                        }
                        globalHotkeyEnabled = true
                        shortcutError = nil
                        recordingAction = nil
                    }
                }
            } header: {
                Text(L10n.settingsShortcuts)
            }

            Section {
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
            } header: {
                Text(L10n.settingsGeneral)
            }

            Section {
                Button(L10n.cleanTemporary, action: onCleanup)
                Text(L10n.settingsCleanupHint)
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text(L10n.settingsMaintenance)
            }

            Section {
                Text(L10n.settingsSecurityBody)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text(L10n.settingsSecurity)
            }
        }
        .formStyle(.grouped)
        .padding(8)
        .frame(minWidth: 460, minHeight: 520)
    }

    @ViewBuilder
    private func shortcutRow(for action: SettingsStore.ShortcutAction) -> some View {
        let chord = shortcutChords[action] ?? action.defaultChord
        let disabled = action.isGlobal && !globalHotkeyEnabled

        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title(for: action))
                if action.isGlobal {
                    Text(L10n.settingsHotkeyGlobalCaption)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            ShortcutRecorder(
                displayString: chord.displayString,
                isRecording: Binding(
                    get: { recordingAction == action },
                    set: { recording in
                        recordingAction = recording ? action : nil
                    }
                ),
                recordingPrompt: L10n.settingsHotkeyRecording
            ) { keyCode, modifiers in
                let next = ShortcutChord(keyCode: keyCode, carbonModifiers: modifiers)
                if onShortcutChange(action, next) {
                    shortcutChords[action] = next
                    shortcutError = nil
                } else {
                    shortcutError = L10n.settingsHotkeyConflict
                    NSSound.beep()
                }
            }
            .disabled(disabled)
            .opacity(disabled ? 0.45 : 1)

            Button(L10n.settingsResetShortcut) {
                onResetShortcut(action)
                shortcutChords[action] = action.defaultChord
                shortcutError = nil
            }
            .disabled(disabled)
        }
        .padding(.vertical, 2)
    }

    private func title(for action: SettingsStore.ShortcutAction) -> String {
        switch action {
        case .summonShelf: return L10n.settingsHotkeySummon
        case .newShelf: return L10n.newShelf
        case .openSettings: return L10n.settings
        case .closeAll: return L10n.closeAllShelves
        case .quit: return L10n.quit
        }
    }
}

// MARK: - Shortcut recorder

private struct ShortcutRecorder: View {
    let displayString: String
    @Binding var isRecording: Bool
    let recordingPrompt: String
    let onShortcut: (UInt32, UInt32) -> Void

    var body: some View {
        ShortcutRecorderRepresentable(
            isRecording: $isRecording,
            onShortcut: onShortcut
        )
        .frame(width: 132, height: 28)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            isRecording ? Color.accentColor : Color.secondary.opacity(0.35),
                            lineWidth: isRecording ? 2 : 1
                        )
                )
        )
        .overlay(
            Text(isRecording ? recordingPrompt : displayString)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isRecording ? .accentColor : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .allowsHitTesting(false)
        )
    }
}

private struct ShortcutRecorderRepresentable: NSViewRepresentable {
    @Binding var isRecording: Bool
    let onShortcut: (UInt32, UInt32) -> Void

    func makeNSView(context: Context) -> ShortcutCaptureView {
        let view = ShortcutCaptureView()
        view.onRecordingChanged = { isRecording = $0 }
        view.onShortcut = onShortcut
        return view
    }

    func updateNSView(_ view: ShortcutCaptureView, context: Context) {
        view.isRecording = isRecording
        view.onRecordingChanged = { isRecording = $0 }
        view.onShortcut = onShortcut
    }
}

private final class ShortcutCaptureView: NSView {
    var isRecording = false
    var onRecordingChanged: ((Bool) -> Void)?
    var onShortcut: ((UInt32, UInt32) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        isRecording = true
        window?.makeFirstResponder(self)
        onRecordingChanged?(true)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        if event.keyCode == 53 { // Escape cancels
            isRecording = false
            onRecordingChanged?(false)
            return
        }

        let modifiers = GlobalHotkeyManager.modifiers(from: event.modifierFlags)
        guard modifiers != 0 else {
            NSSound.beep()
            return
        }

        onShortcut?(UInt32(event.keyCode), modifiers)
        isRecording = false
        onRecordingChanged?(false)
    }
}
