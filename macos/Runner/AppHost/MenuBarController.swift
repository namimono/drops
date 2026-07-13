import AppKit
import Foundation

/// Menu bar status item for the app host.
final class MenuBarController: NSObject {
  private var statusItem: NSStatusItem?

  func setup() {
    let showMenuBarIcon = SettingsBridge.shared.getSetting(key: "showMenuBarIcon") as? Bool ?? true
    if showMenuBarIcon {
      show()
    } else {
      hide()
    }
  }

  func show() {
    if statusItem != nil {
      NSStatusBar.system.removeStatusItem(statusItem!)
      statusItem = nil
    }
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    let menu = NSMenu()
    let menuItems: [(String, Int)] = [
      ("New Shelf", 1),
      ("Settings…", -2),
      ("About Shakepin", 3),
      ("Quit", -1),
    ]
    for (title, tag) in menuItems {
      let item = NSMenuItem(title: title, action: #selector(menuItemClicked(_:)), keyEquivalent: "")
      item.target = self
      item.tag = tag
      menu.addItem(item)
    }
    statusItem?.menu = menu

    if let button = statusItem?.button {
      if let imagePath = Bundle.main.path(forResource: "tray_icon", ofType: "png"),
        let originalImage = NSImage(contentsOfFile: imagePath)
      {
        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.lockFocus()
        originalImage.draw(in: NSRect(x: 0, y: 0, width: 18, height: 18))
        image.unlockFocus()
        image.isTemplate = true
        button.image = image
      } else if let systemImage = NSImage(
        systemSymbolName: "app.badge", accessibilityDescription: "ShakePin")
      {
        button.image = systemImage
      } else {
        button.title = "SP"
      }
    }
  }

  func hide() {
    if let statusItem {
      NSStatusBar.system.removeStatusItem(statusItem)
      self.statusItem = nil
    }
  }

  func setIcon(data: Data) {
    let icon = NSImage(data: data)
    icon?.isTemplate = true
    icon?.size = NSSize(width: 18, height: 18)
    statusItem?.button?.image = icon
  }

  @objc private func menuItemClicked(_ sender: NSMenuItem) {
    AppHostController.shared.handleMenuTag(sender.tag)
  }
}
