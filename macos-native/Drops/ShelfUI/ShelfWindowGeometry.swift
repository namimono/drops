import AppKit

enum ShelfShowMilestone: Equatable {
    /// Persistent shelf: first frame committed for display.
    case firstFrameVisible
    /// Transient shelf: panel on-screen (pre-drop-registration timing aid).
    case transientWindowVisible
    /// Transient shelf: visible and registered as a drag destination.
    case dragReady
}

/// Clamps a proposed shelf frame origin into the visible work area of the target screen.
enum ShelfWindowGeometry {
    static func clampedOrigin(
        _ origin: NSPoint,
        size: NSSize,
        visibleFrame: NSRect,
        margin: CGFloat = 8
    ) -> NSPoint {
        let x = min(
            max(origin.x, visibleFrame.minX + margin),
            max(visibleFrame.minX + margin, visibleFrame.maxX - size.width - margin)
        )
        let y = min(
            max(origin.y, visibleFrame.minY + margin),
            max(visibleFrame.minY + margin, visibleFrame.maxY - size.height - margin)
        )
        return NSPoint(x: x, y: y)
    }

    static func clampedOrigin(
        _ origin: NSPoint,
        size: NSSize,
        mouseLocation: NSPoint = NSEvent.mouseLocation,
        screens: [NSScreen] = NSScreen.screens,
        margin: CGFloat = 8
    ) -> NSPoint {
        let screen = screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
            ?? NSScreen.main
            ?? screens.first
        guard let screen else { return origin }
        return clampedOrigin(origin, size: size, visibleFrame: screen.visibleFrame, margin: margin)
    }

    static func originNearMouse(
        size: NSSize,
        offset: NSPoint = .zero,
        mouseLocation: NSPoint = NSEvent.mouseLocation,
        screens: [NSScreen] = NSScreen.screens
    ) -> NSPoint {
        let proposed = NSPoint(
            x: mouseLocation.x - size.width / 2 + offset.x,
            y: mouseLocation.y - size.height / 2 + offset.y
        )
        return clampedOrigin(proposed, size: size, mouseLocation: mouseLocation, screens: screens)
    }
}
