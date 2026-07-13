import AppKit
import Cocoa
import FlutterMacOS

/// Hidden Flutter host window — app-level services only (settings, tray, updater).
/// Collection shelves are created by ShelfManager as separate engines/windows.
class MainFlutterWindow: NSWindow {
  var channel: FlutterMethodChannel!
  var flutterViewController: FlutterViewController!
  var settingsChannel: FlutterMethodChannel?
  private var initialized = false

  override func awakeFromNib() {
    flutterViewController = FlutterViewController()
    RegisterGeneratedPlugins(registry: flutterViewController)

    channel = FlutterMethodChannel(
      name: "click.shakepin.macos/drop",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    channel.setMethodCallHandler(handleHostMethodCall)

    contentViewController = flutterViewController
    isOpaque = false
    backgroundColor = .clear
    titleVisibility = .hidden
    titlebarAppearsTransparent = true
    styleMask.remove(.titled)
    styleMask.insert(.fullSizeContentView)
    standardWindowButton(.closeButton)?.isHidden = true
    standardWindowButton(.miniaturizeButton)?.isHidden = true
    standardWindowButton(.zoomButton)?.isHidden = true
    level = .floating
    setIsVisible(false)

    settingsChannel = FlutterMethodChannel(
      name: "click.shakepin.macos/settings",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    SettingsBridge.shared.registerChannel(settingsChannel!)
    settingsChannel?.setMethodCallHandler { call, result in
      SettingsBridge.shared.handleMethodCall(call, result: result)
    }

    AppHostController.shared.start(hostWindow: self)
    super.awakeFromNib()
  }

  override func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
    super.order(place, relativeTo: otherWin)
    if !initialized {
      setIsVisible(false)
    }
    initialized = true
  }

  func handleSettingChangeFromBridge(key: String, value: Any) {
    AppHostController.shared.handleSettingChange(key: key, value: value)
  }

  func showSettingsWindow() {
    AppHostController.shared.showSettingsWindow()
  }

  private func handleHostMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "setTrayIcon":
      if let trayIconData = call.arguments as? FlutterStandardTypedData {
        AppHostController.shared.menuBar.setIcon(data: trayIconData.data)
      }
      result(nil)
    case "setupMenuBar":
      AppHostController.shared.menuBar.setup()
      result(nil)
    case "getGlobalHotkeyStatus":
      result([
        "enabled": UserDefaults.standard.object(forKey: GlobalHotkeyManager.enabledKey) as? Bool
          ?? true,
        "keyCode": UserDefaults.standard.object(forKey: GlobalHotkeyManager.keyCodeKey) as? Int
          ?? Int(GlobalHotkeyManager.defaultKeyCode),
        "modifiers": UserDefaults.standard.object(forKey: GlobalHotkeyManager.modifiersKey) as? Int
          ?? Int(GlobalHotkeyManager.defaultModifiers),
      ])
    case "setVisible", "hide", "setFrame", "setMinimumSize", "orderFront", "center", "isVisible":
      // Host window stays hidden; shelf windows handle visibility.
      if call.method == "center" {
        let mouse = NSEvent.mouseLocation
        result([mouse.x, mouse.y])
      } else if call.method == "isVisible" {
        result(false)
      } else {
        result(nil)
      }
    case "setShiftKeyCheckEnabled":
      if let enabled = call.arguments as? Bool {
        GlobalInputCoordinator.shared.shiftKeyCheckEnabled = enabled
        result(nil)
      } else {
        result(
          FlutterError(code: "INVALID_ARGUMENT", message: "Argument must be a boolean", details: nil)
        )
      }
    case "getAppVersion":
      result(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")
    case "cleanup":
      result(nil)
    default:
      result(nil)
    }
  }
}
