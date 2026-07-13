import Foundation

enum ShelfOpenSource: String {
  case hotkey
  case menu
  case shake
}

enum ShelfLifecycle: String {
  case creating
  case transient
  case persistent
  case closing
  case closed
}

enum DragSessionState: String {
  case idle
  case dragging
  case finishing
  case finished
}

struct DragSessionRecord {
  let id: String
  var state: DragSessionState
  var shakeShelfId: String?
  let startedAt: Date

  init(id: String) {
    self.id = id
    self.state = .dragging
    self.shakeShelfId = nil
    self.startedAt = Date()
  }
}

/// Pure lifecycle registry — no window / Flutter dependencies.
final class ShelfLifecycleStore {
  static let maxShelves = 20

  private var sessions: [String: ShelfSessionRecord] = [:]
  private(set) var dragSession: DragSessionRecord?
  private var idCounter = 0

  var activeCount: Int {
    sessions.values.filter { $0.isActive }.count
  }

  func session(id: String) -> ShelfSessionRecord? {
    sessions[id]
  }

  func allSessions() -> [ShelfSessionRecord] {
    Array(sessions.values)
  }

  @discardableResult
  func createShelf(source: ShelfOpenSource, dragSessionId: String? = nil) -> (
    session: ShelfSessionRecord?, reason: String?
  ) {
    if activeCount >= Self.maxShelves {
      return (nil, "max_shelves_reached")
    }

    if source == .shake {
      guard let drag = dragSession, drag.id == dragSessionId else {
        return (nil, "no_active_drag_session")
      }
      if drag.shakeShelfId != nil {
        return (nil, "shake_shelf_already_exists")
      }
      if drag.state != .dragging {
        return (nil, "drag_session_not_active")
      }
    }

    idCounter += 1
    let id = "shelf-\(idCounter)"
    let lifecycle: ShelfLifecycle = source == .shake ? .transient : .persistent
    var record = ShelfSessionRecord(
      id: id,
      source: source,
      lifecycle: lifecycle,
      associatedDragSessionId: source == .shake ? dragSessionId : nil
    )
    sessions[id] = record

    if source == .shake {
      dragSession?.shakeShelfId = id
    }

    NSLog("[SHELF] created id=%@ source=%@ lifecycle=%@", id, source.rawValue, lifecycle.rawValue)
    return (record, nil)
  }

  func beginExternalDrag(dragSessionId: String) {
    dragSession = DragSessionRecord(id: dragSessionId)
    NSLog("[SHELF] dragStarted dragSessionId=%@", dragSessionId)
  }

  @discardableResult
  func markDropAccepted(shelfId: String, dragSessionId: String? = nil) -> Bool {
    guard var session = sessions[shelfId], session.isActive else { return false }
    session.acceptedDrop = true
    if session.lifecycle == .transient {
      session.lifecycle = .persistent
      session.associatedDragSessionId = nil
      NSLog(
        "[SHELF] dropAccepted shelfId=%@ dragSessionId=%@ → persistent",
        shelfId, dragSessionId ?? "nil")
    }
    sessions[shelfId] = session
    return true
  }

  /// Returns shelf ids that should be closed because transient + no drop.
  func endExternalDrag(dragSessionId: String) -> [String] {
    guard var drag = dragSession, drag.id == dragSessionId else { return [] }
    drag.state = .finished
    var toClose: [String] = []
    if let shakeId = drag.shakeShelfId,
      let session = sessions[shakeId],
      session.lifecycle == .transient,
      !session.acceptedDrop
    {
      toClose.append(shakeId)
    }
    dragSession = nil
    NSLog(
      "[SHELF] dragEnded dragSessionId=%@ closeCount=%d", dragSessionId, toClose.count)
    return toClose
  }

  @discardableResult
  func beginClose(shelfId: String) -> Bool {
    guard var session = sessions[shelfId] else { return false }
    if session.lifecycle == .closed { return false }
    if session.lifecycle == .closing { return true }
    session.lifecycle = .closing
    sessions[shelfId] = session
    NSLog("[SHELF] closing shelfId=%@", shelfId)
    return true
  }

  func markClosed(shelfId: String) {
    sessions.removeValue(forKey: shelfId)
    NSLog("[SHELF] closed shelfId=%@", shelfId)
  }

  func shouldIgnoreEvent(shelfId: String) -> Bool {
    guard let session = sessions[shelfId] else { return true }
    return session.lifecycle == .closing || session.lifecycle == .closed
  }

  func updateLifecycle(shelfId: String, lifecycle: ShelfLifecycle) {
    guard var session = sessions[shelfId] else { return }
    session.lifecycle = lifecycle
    sessions[shelfId] = session
  }
}

struct ShelfSessionRecord {
  let id: String
  let source: ShelfOpenSource
  var lifecycle: ShelfLifecycle
  var associatedDragSessionId: String?
  var acceptedDrop: Bool
  let createdAt: Date

  init(
    id: String,
    source: ShelfOpenSource,
    lifecycle: ShelfLifecycle,
    associatedDragSessionId: String? = nil,
    acceptedDrop: Bool = false
  ) {
    self.id = id
    self.source = source
    self.lifecycle = lifecycle
    self.associatedDragSessionId = associatedDragSessionId
    self.acceptedDrop = acceptedDrop
    self.createdAt = Date()
  }

  var isActive: Bool {
    lifecycle != .closing && lifecycle != .closed
  }
}
