import AppKit
import FlutterMacOS
import Foundation

/// Application host: menu bar, hotkeys, settings, input — not a collection shelf.
final class AppHostController: NSObject {
  static let shared = AppHostController()

  let menuBar = MenuBarController()
  private var settingsWindowController: NSWindowController?
  private weak var hostWindow: MainFlutterWindow?

  private override init() {
    super.init()
  }

  func start(hostWindow: MainFlutterWindow) {
    self.hostWindow = hostWindow
    menuBar.setup()
    GlobalInputCoordinator.shared.start()

    GlobalHotkeyManager.shared.start { [weak self] in
      guard let self else { return }
      NSLog("[HOTKEY] creating new shelf")
      let position = NSEvent.mouseLocation
      _ = ShelfManager.shared.createShelf(source: .hotkey, position: position)
      NSApp.activate(ignoringOtherApps: true)
    }
  }

  func showSettingsWindow() {
    if let controller = settingsWindowController, controller.window?.isVisible == true {
      controller.showWindow(self)
      NSApp.activate(ignoringOtherApps: true)
      return
    }
    let vc = SettingsHostingController()
    let window = NSWindow(contentViewController: vc)
    window.title = "Settings"
    window.styleMask = [.titled, .closable, .miniaturizable]
    window.setContentSize(NSSize(width: 640, height: 480))
    window.center()
    let controller = NSWindowController(window: window)
    settingsWindowController = controller
    controller.showWindow(self)
    NSApp.activate(ignoringOtherApps: true)
  }

  func handleMenuTag(_ tag: Int) {
    switch tag {
    case -1:
      NSApplication.shared.terminate(nil)
    case -2:
      showSettingsWindow()
    case 1:
      // New shelf
      _ = ShelfManager.shared.createShelf(source: .menu, position: NSEvent.mouseLocation)
      NSApp.activate(ignoringOtherApps: true)
    case 3:
      // About — open a shelf and ask it to show about
      if let id = ShelfManager.shared.createShelf(
        source: .menu, position: NSEvent.mouseLocation)
      {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
          // Best-effort: find window and invoke about
          if let window = NSApp.windows.first(where: {
            ($0 as? ShelfWindow)?.shelfId == id
          }) as? ShelfWindow {
            window.runtime?.invokeMenuTag(3)
          }
        }
        NSApp.activate(ignoringOtherApps: true)
      }
    default:
      break
    }
  }

  func handleSettingChange(key: String, value: Any) {
    switch key {
    case "showMenuBarIcon":
      if let showIcon = value as? Bool {
        if showIcon {
          menuBar.show()
        } else {
          menuBar.hide()
        }
      }
    case GlobalHotkeyManager.enabledKey,
      GlobalHotkeyManager.keyCodeKey,
      GlobalHotkeyManager.modifiersKey:
      GlobalHotkeyManager.shared.reload()
    default:
      break
    }
  }
}
