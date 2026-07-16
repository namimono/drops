import AppKit
import Carbon.HIToolbox

/// Registers a global Carbon hotkey without requiring Accessibility permission.
final class GlobalHotkeyManager {
    /// Legacy keys — still written by `SettingsStore` for compatibility.
    static let enabledKey = SettingsStore.legacyHotkeyEnabledKey
    static let keyCodeKey = SettingsStore.legacyHotkeyKeyCodeKey
    static let modifiersKey = SettingsStore.legacyHotkeyModifiersKey

    static let defaultKeyCode: UInt32 = 49 // Space
    static let defaultModifiers: UInt32 = UInt32(cmdKey | optionKey)

    fileprivate static let signature: OSType = 0x44525053 // "DRPS"
    private let hotkeyID = EventHotKeyID(signature: GlobalHotkeyManager.signature, id: 1)

    private var eventHandler: EventHandlerRef?
    private var registeredHotkey: EventHotKeyRef?
    private var onPressed: (() -> Void)?
    private weak var settings: SettingsStore?

    deinit {
        unregister()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    func start(settings: SettingsStore, onPressed: @escaping () -> Void) {
        self.settings = settings
        self.onPressed = onPressed
        DispatchQueue.main.async { [weak self] in
            self?.reload()
        }
    }

    func reload() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.reload() }
            return
        }

        guard installEventHandlerIfNeeded() else { return }
        unregister()

        let enabled = settings?.globalHotkeyEnabled
            ?? ((UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool) ?? true)
        guard enabled else {
            NSLog("[Hotkey] disabled — not registering")
            return
        }

        let chord = settings?.globalHotkey ?? ShortcutChord(
            keyCode: UInt32(
                (UserDefaults.standard.object(forKey: Self.keyCodeKey) as? Int)
                    ?? Int(Self.defaultKeyCode)
            ),
            carbonModifiers: UInt32(
                (UserDefaults.standard.object(forKey: Self.modifiersKey) as? Int)
                    ?? Int(Self.defaultModifiers)
            )
        )

        var hotkey: EventHotKeyRef?
        let status = RegisterEventHotKey(
            chord.keyCode,
            chord.carbonModifiers,
            hotkeyID,
            GetEventDispatcherTarget(),
            0,
            &hotkey
        )
        guard status == noErr, let hotkey else {
            NSLog("[Hotkey] register failed status=%d", status)
            return
        }
        registeredHotkey = hotkey
        NSLog(
            "[Hotkey] registered %@ (keyCode=%u modifiers=%u)",
            Self.displayString(keyCode: chord.keyCode, modifiers: chord.carbonModifiers),
            chord.keyCode,
            chord.carbonModifiers
        )
    }

    func unregister() {
        if let registeredHotkey {
            UnregisterEventHotKey(registeredHotkey)
            self.registeredHotkey = nil
        }
    }

    fileprivate func handleHotKeyPressed() {
        onPressed?()
    }

    static func modifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }

    static func modifierFlags(from carbonModifiers: UInt32) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbonModifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if carbonModifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if carbonModifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if carbonModifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        return flags
    }

    static func displayString(keyCode: UInt32, modifiers: UInt32) -> String {
        var display = ""
        if modifiers & UInt32(controlKey) != 0 { display += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { display += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { display += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { display += "⌘" }
        return display + keyName(for: keyCode)
    }

    static func keyName(for keyCode: UInt32) -> String {
        let names: [UInt32: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z",
            7: "X", 8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E",
            15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4",
            22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8",
            29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
            36: "↩", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\",
            43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 48: "⇥", 49: "Space",
            51: "⌫", 53: "⎋", 123: "←", 124: "→", 125: "↓", 126: "↑",
        ]
        return names[keyCode] ?? "Key \(keyCode)"
    }

    private func installEventHandlerIfNeeded() -> Bool {
        if eventHandler != nil { return true }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            hotkeyEventHandler,
            1,
            &eventType,
            refcon,
            &eventHandler
        )
        return status == noErr
    }
}

private func hotkeyEventHandler(
    nextHandler: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData, let event else {
        return CallNextEventHandler(nextHandler, event)
    }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr,
          hotKeyID.signature == GlobalHotkeyManager.signature,
          hotKeyID.id == 1 else {
        return CallNextEventHandler(nextHandler, event)
    }

    let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(userData).takeUnretainedValue()
    DispatchQueue.main.async {
        manager.handleHotKeyPressed()
    }
    return noErr
}
