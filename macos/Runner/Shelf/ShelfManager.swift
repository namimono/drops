import AppKit
import Foundation

/// Owns all shelf sessions and window lifecycle.
final class ShelfManager {
  static let shared = ShelfManager()

  private let store = ShelfLifecycleStore()
  private var windows: [String: ShelfWindow] = [:]

  private init() {}

  var activeCount: Int { store.activeCount }
  var hasActiveExternalDrag: Bool { store.dragSession != nil }

  func shouldIgnore(shelfId: String) -> Bool {
    store.shouldIgnoreEvent(shelfId: shelfId)
  }

  @discardableResult
  func createShelf(source: ShelfOpenSource, position: NSPoint) -> String? {
    let dragId = store.dragSession?.id
    let (record, reason) = store.createShelf(source: source, dragSessionId: dragId)
    guard let record else {
      NSLog("[SHELF] create rejected reason=%@", reason ?? "unknown")
      if reason == "max_shelves_reached" {
        NSSound.beep()
      }
      return nil
    }

    let window = ShelfWindow(shelfId: record.id, source: source, position: position)
    guard window.engineStarted else {
      NSLog("[SHELF] engine start failed, rolling back id=%@", record.id)
      window.tearDown()
      store.beginClose(shelfId: record.id)
      store.markClosed(shelfId: record.id)
      return nil
    }
    windows[record.id] = window

    switch source {
    case .hotkey, .menu:
      window.showActivated(activateApp: true)
    case .shake:
      window.showWithoutActivating()
    }

    store.updateLifecycle(shelfId: record.id, lifecycle: record.lifecycle)
    return record.id
  }

  func markDropAccepted(shelfId: String) {
    let dragId = store.dragSession?.id
    _ = store.markDropAccepted(shelfId: shelfId, dragSessionId: dragId)
  }

  func beginExternalDrag(dragSessionId: String) {
    store.beginExternalDrag(dragSessionId: dragSessionId)
    for window in windows.values {
      window.runtime?.beginExternalDragCapture()
    }
  }

  func endExternalDrag(dragSessionId: String) {
    let toClose = store.endExternalDrag(dragSessionId: dragSessionId)
    for window in windows.values {
      window.runtime?.endExternalDragCapture()
    }
    for id in toClose {
      closeShelf(id: id)
    }
  }

  func handleShake(at position: NSPoint) {
    guard store.dragSession != nil else { return }
    if store.dragSession?.shakeShelfId != nil { return }
    _ = createShelf(source: .shake, position: position)
  }

  func closeShelf(id: String) {
    guard store.beginClose(shelfId: id) else { return }
    if let window = windows.removeValue(forKey: id) {
      window.tearDown()
    }
    store.markClosed(shelfId: id)
  }

  func closeAll() {
    for id in Array(windows.keys) {
      closeShelf(id: id)
    }
  }

  func keyShelfWindow() -> ShelfWindow? {
    if let key = NSApp.keyWindow as? ShelfWindow {
      return key
    }
    return windows.values.first
  }
}
