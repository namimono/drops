import AppKit
import Carbon.HIToolbox

/// Registers Command-Option-Space (configurable later) without requiring Accessibility permission.
final class GlobalHotkeyManager {
    static let enabledKey = "globalHotkeyEnabled"
    static let keyCodeKey = "globalHotkeyKeyCode"
    static let modifiersKey = "globalHotkeyModifiers"

    static let defaultKeyCode: UInt32 = 49 // Space
    static let defaultModifiers: UInt32 = UInt32(cmdKey | optionKey)

    fileprivate static let signature: OSType = 0x44525053 // "DRPS"
    private let hotkeyID = EventHotKeyID(signature: GlobalHotkeyManager.signature, id: 1)

    private var eventHandler: EventHandlerRef?
    private var registeredHotkey: EventHotKeyRef?
    private var onPressed: (() -> Void)?

    deinit {
        unregister()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    func start(onPressed: @escaping () -> Void) {
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

        let defaults = UserDefaults.standard
        let enabled = (defaults.object(forKey: Self.enabledKey) as? Bool) ?? true
        guard enabled else {
            NSLog("[Hotkey] disabled — not registering")
            return
        }

        let keyCode = UInt32(
            (defaults.object(forKey: Self.keyCodeKey) as? Int) ?? Int(Self.defaultKeyCode)
        )
        let modifiers = UInt32(
            (defaults.object(forKey: Self.modifiersKey) as? Int) ?? Int(Self.defaultModifiers)
        )

        var hotkey: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
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
        NSLog("[Hotkey] registered ⌘⌥Space (keyCode=%u)", keyCode)
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
