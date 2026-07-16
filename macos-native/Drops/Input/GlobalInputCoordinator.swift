import AppKit
import Foundation

/// Detects external drag sessions and shake-to-summon transient shelves.
@MainActor
final class GlobalInputCoordinator {
    var shiftKeyCheckEnabled = true

    private var mouseDownMonitor: Any?
    private var dragMonitor: Any?
    private var mouseUpMonitor: Any?

    private var initialChangeCount = 0
    private var isDragging = false
    private var dragStarted = false
    private var positions: [CGPoint] = []
    private var timestamps: [Date] = []
    private var currentDragSessionId: DragSessionID?

    /// Updated from Settings; defaults match historical medium sensitivity.
    var shakeSensitivity: SettingsStore.ShakeSensitivity = .medium

    private let onBeginExternalDrag: (DragSessionID) -> Void
    private let onShake: (NSPoint, DragSessionID) -> Void
    private let onEndExternalDrag: (DragSessionID) -> Void

    init(
        onBeginExternalDrag: @escaping (DragSessionID) -> Void,
        onShake: @escaping (NSPoint, DragSessionID) -> Void,
        onEndExternalDrag: @escaping (DragSessionID) -> Void
    ) {
        self.onBeginExternalDrag = onBeginExternalDrag
        self.onShake = onShake
        self.onEndExternalDrag = onEndExternalDrag
    }

    func start() {
        stop()

        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                let pasteboard = NSPasteboard(name: .drag)
                self.initialChangeCount = pasteboard.changeCount
                self.positions.removeAll()
                self.timestamps.removeAll()
                self.isDragging = true
                self.dragStarted = false
                self.currentDragSessionId = nil
            }
        }

        dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] event in
            guard let self else { return }
            Task { @MainActor in
                self.handleDragged(event)
            }
        }

        mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.handleMouseUp()
            }
        }
    }

    func stop() {
        if let mouseDownMonitor { NSEvent.removeMonitor(mouseDownMonitor) }
        if let dragMonitor { NSEvent.removeMonitor(dragMonitor) }
        if let mouseUpMonitor { NSEvent.removeMonitor(mouseUpMonitor) }
        mouseDownMonitor = nil
        dragMonitor = nil
        mouseUpMonitor = nil
    }

    // MARK: - Private

    private func handleDragged(_ event: NSEvent) {
        guard isDragging else { return }
        let pasteboard = NSPasteboard(name: .drag)
        let currentChangeCount = pasteboard.changeCount
        guard currentChangeCount != initialChangeCount else { return }

        if !dragStarted {
            dragStarted = true
            let id = DragSessionID(UUID().uuidString)
            currentDragSessionId = id
            onBeginExternalDrag(id)
        }

        guard let sessionId = currentDragSessionId else { return }
        let currentPos = NSEvent.mouseLocation

        if shiftKeyCheckEnabled, event.modifierFlags.contains(.shift) {
            onShake(currentPos, sessionId)
            return
        }

        let currentTime = Date()
        positions.append(currentPos)
        timestamps.append(currentTime)

        let sensitivity = shakeSensitivity
        while timestamps.count > 1,
              currentTime.timeIntervalSince(timestamps[0]) > sensitivity.timeWindow {
            positions.removeFirst()
            timestamps.removeFirst()
        }

        if ShakeDetector.detect(
            positions: positions,
            timestamps: timestamps,
            threshold: sensitivity.threshold,
            minVelocity: sensitivity.minVelocity
        ) {
            onShake(currentPos, sessionId)
        }
    }

    private func handleMouseUp() {
        dragStarted = false
        let pasteboard = NSPasteboard(name: .drag)
        let currentChangeCount = pasteboard.changeCount
        if currentChangeCount != initialChangeCount {
            isDragging = false
            positions.removeAll()
            timestamps.removeAll()
            if let id = currentDragSessionId {
                // Slight delay so AppKit performDragOperation can win the race.
                let end = onEndExternalDrag
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    end(id)
                }
            }
            currentDragSessionId = nil
        }
    }
}
