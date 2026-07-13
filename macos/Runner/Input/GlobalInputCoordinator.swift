import AppKit
import Foundation

/// Converts OS-level input into shelf domain events. Does not touch Flutter engines directly.
final class GlobalInputCoordinator {
  static let shared = GlobalInputCoordinator()

  var shiftKeyCheckEnabled = true

  private var mouseDownMonitor: Any?
  private var dragMonitor: Any?
  private var mouseUpMonitor: Any?

  private var initialChangeCount = 0
  private var isDragging = false
  private var dragStarted = false
  private var positions: [CGPoint] = []
  private var timestamps: [Date] = []
  private var currentDragSessionId: String?

  private let shakeThreshold = 4
  private let timeWindow: TimeInterval = 1
  private let minVelocity: CGFloat = 200

  private init() {}

  func start() {
    stop()

    mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
      guard let self else { return }
      let pasteboard = NSPasteboard(name: .drag)
      self.initialChangeCount = pasteboard.changeCount
      self.positions.removeAll()
      self.timestamps.removeAll()
      self.isDragging = true
      self.dragStarted = false
      self.currentDragSessionId = nil
    }

    dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] event in
      guard let self, self.isDragging else { return }
      let pasteboard = NSPasteboard(name: .drag)
      let currentChangeCount = pasteboard.changeCount
      guard currentChangeCount != self.initialChangeCount else { return }

      if !self.dragStarted {
        self.dragStarted = true
        let id = UUID().uuidString
        self.currentDragSessionId = id
        ShelfManager.shared.beginExternalDrag(dragSessionId: id)
      }

      let currentPos = NSEvent.mouseLocation
      let currentTime = Date()

      if self.shiftKeyCheckEnabled && event.modifierFlags.contains(.shift) {
        ShelfManager.shared.handleShake(at: currentPos)
        return
      }

      self.positions.append(currentPos)
      self.timestamps.append(currentTime)

      while self.timestamps.count > 1,
        currentTime.timeIntervalSince(self.timestamps[0]) > self.timeWindow
      {
        self.positions.removeFirst()
        self.timestamps.removeFirst()
      }

      if self.detectShake(
        positions: self.positions, timestamps: self.timestamps,
        threshold: self.shakeThreshold, minVelocity: self.minVelocity)
      {
        ShelfManager.shared.handleShake(at: currentPos)
      }
    }

    mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
      guard let self else { return }
      self.dragStarted = false
      let pasteboard = NSPasteboard(name: .drag)
      let currentChangeCount = pasteboard.changeCount
      if currentChangeCount != self.initialChangeCount {
        self.isDragging = false
        self.positions.removeAll()
        self.timestamps.removeAll()
        if let id = self.currentDragSessionId {
          // Slight delay so AppKit performDragOperation can win the race.
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            ShelfManager.shared.endExternalDrag(dragSessionId: id)
          }
        }
        self.currentDragSessionId = nil
      }
    }
  }

  func stop() {
    if let m = mouseDownMonitor { NSEvent.removeMonitor(m) }
    if let m = dragMonitor { NSEvent.removeMonitor(m) }
    if let m = mouseUpMonitor { NSEvent.removeMonitor(m) }
    mouseDownMonitor = nil
    dragMonitor = nil
    mouseUpMonitor = nil
  }

  private func detectShake(
    positions: [CGPoint], timestamps: [Date],
    threshold: Int, minVelocity: CGFloat
  ) -> Bool {
    guard positions.count > 2 else { return false }

    var horizontalChanges = 0
    var verticalChanges = 0
    var lastHorizontalDirection = 0
    var lastVerticalDirection = 0
    var totalDistance: CGFloat = 0

    for i in 1..<positions.count {
      let dx = positions[i].x - positions[i - 1].x
      let dy = positions[i].y - positions[i - 1].y
      let currentHorizontalDirection = dx == 0 ? 0 : dx > 0 ? 1 : -1
      let currentVerticalDirection = dy == 0 ? 0 : dy > 0 ? 1 : -1
      totalDistance += sqrt(dx * dx + dy * dy)

      if lastHorizontalDirection != 0 && currentHorizontalDirection != 0
        && currentHorizontalDirection != lastHorizontalDirection
      {
        horizontalChanges += 1
      }
      if lastVerticalDirection != 0 && currentVerticalDirection != 0
        && currentVerticalDirection != lastVerticalDirection
      {
        verticalChanges += 1
      }
      if currentHorizontalDirection != 0 {
        lastHorizontalDirection = currentHorizontalDirection
      }
      if currentVerticalDirection != 0 {
        lastVerticalDirection = currentVerticalDirection
      }
    }

    let duration = timestamps.last!.timeIntervalSince(timestamps.first!)
    guard duration > 0 else { return false }
    let velocity = CGFloat(totalDistance) / CGFloat(duration)
    return (horizontalChanges >= threshold || verticalChanges >= threshold)
      && velocity >= minVelocity
  }
}
