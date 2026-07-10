import AppKit
import Carbon.HIToolbox

/// Registers the configurable shortcut used to show the shelf from anywhere.
///
/// Carbon hot keys are still the appropriate API here: unlike a global key
/// monitor, they do not require Accessibility permission and work while the
/// app is inactive (important for LSUIElement apps).
final class GlobalHotkeyManager {
  static let shared = GlobalHotkeyManager()

  static let enabledKey = "globalHotkeyEnabled"
  static let keyCodeKey = "globalHotkeyKeyCode"
  static let modifiersKey = "globalHotkeyModifiers"

  static let defaultKeyCode: UInt32 = 49 // Space
  static let defaultModifiers: UInt32 = UInt32(cmdKey | optionKey)

  /// FourCharCode "SHPN" — fileprivate so the C trampoline can filter our events.
  fileprivate static let signature: OSType = 0x5348504E
  private let hotkeyID = EventHotKeyID(signature: GlobalHotkeyManager.signature, id: 1)

  private var eventHandler: EventHandlerRef?
  private var registeredHotkey: EventHotKeyRef?
  private var onPressed: (() -> Void)?

  private init() {}

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
      DispatchQueue.main.async { [weak self] in
        self?.reload()
      }
      return
    }

    guard installEventHandlerIfNeeded() else { return }
    unregister()

    let defaults = UserDefaults.standard
    let enabled: Bool
    if let boolValue = defaults.object(forKey: Self.enabledKey) as? Bool {
      enabled = boolValue
    } else if let number = defaults.object(forKey: Self.enabledKey) as? NSNumber {
      enabled = number.boolValue
    } else {
      enabled = true
    }
    guard enabled else {
      NSLog("[HOTKEY] Shortcut disabled — not registering")
      return
    }

    let keyCode = UInt32(intDefault(defaults, key: Self.keyCodeKey, fallback: Int(Self.defaultKeyCode)))
    let modifiers = UInt32(intDefault(defaults, key: Self.modifiersKey, fallback: Int(Self.defaultModifiers)))

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
      NSLog(
        "[HOTKEY] Failed to register shortcut keyCode=%u modifiers=%u (status: %d)",
        keyCode, modifiers, status
      )
      return
    }
    registeredHotkey = hotkey
    NSLog(
      "[HOTKEY] Registered shortcut %@ (keyCode=%u modifiers=%u)",
      Self.displayString(keyCode: keyCode, modifiers: modifiers),
      keyCode,
      modifiers
    )
  }

  func unregister() {
    if let registeredHotkey {
      UnregisterEventHotKey(registeredHotkey)
      self.registeredHotkey = nil
    }
  }

  /// Invoked from the Carbon C trampoline on the main queue.
  fileprivate func handleHotKeyPressed() {
    NSLog("[HOTKEY] Carbon event received")
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

  static func displayString(keyCode: UInt32, modifiers: UInt32) -> String {
    var display = ""
    if modifiers & UInt32(controlKey) != 0 { display += "⌃" }
    if modifiers & UInt32(optionKey) != 0 { display += "⌥" }
    if modifiers & UInt32(shiftKey) != 0 { display += "⇧" }
    if modifiers & UInt32(cmdKey) != 0 { display += "⌘" }
    return display + keyName(for: keyCode)
  }

  private static func keyName(for keyCode: UInt32) -> String {
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

  private func intDefault(_ defaults: UserDefaults, key: String, fallback: Int) -> Int {
    if let value = defaults.object(forKey: key) as? Int {
      return value
    }
    if let number = defaults.object(forKey: key) as? NSNumber {
      return number.intValue
    }
    return fallback
  }

  @discardableResult
  private func installEventHandlerIfNeeded() -> Bool {
    guard eventHandler == nil else { return true }

    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed)
    )
    let status = InstallEventHandler(
      GetEventDispatcherTarget(),
      globalHotkeyEventHandler,
      1,
      &eventType,
      Unmanaged.passUnretained(self).toOpaque(),
      &eventHandler
    )

    if status != noErr {
      NSLog("[HOTKEY] Failed to install event handler (status: %d)", status)
      return false
    }
    return true
  }
}

/// C trampoline for Carbon hotkey presses. Routes back to `GlobalHotkeyManager`
/// via the unretained user-data pointer passed to `InstallEventHandler`.
private func globalHotkeyEventHandler(
  _ callRef: EventHandlerCallRef?,
  _ event: EventRef?,
  _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
  guard let event, let userData else {
    return OSStatus(eventNotHandledErr)
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
  guard status == noErr else { return status }
  guard hotKeyID.signature == GlobalHotkeyManager.signature, hotKeyID.id == 1 else {
    return OSStatus(eventNotHandledErr)
  }

  let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(userData).takeUnretainedValue()
  if Thread.isMainThread {
    manager.handleHotKeyPressed()
  } else {
    DispatchQueue.main.async {
      manager.handleHotKeyPressed()
    }
  }
  return noErr
}
