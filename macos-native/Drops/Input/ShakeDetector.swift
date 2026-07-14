import CoreGraphics
import Foundation

/// Pure shake-gesture detector (no AppKit actor isolation).
enum ShakeDetector {
    static func detect(
        positions: [CGPoint],
        timestamps: [Date],
        threshold: Int = 4,
        minVelocity: CGFloat = 200
    ) -> Bool {
        guard positions.count > 2, timestamps.count == positions.count else { return false }

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

            if lastHorizontalDirection != 0,
               currentHorizontalDirection != 0,
               currentHorizontalDirection != lastHorizontalDirection {
                horizontalChanges += 1
            }
            if lastVerticalDirection != 0,
               currentVerticalDirection != 0,
               currentVerticalDirection != lastVerticalDirection {
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
        let velocity = totalDistance / CGFloat(duration)
        return (horizontalChanges >= threshold || verticalChanges >= threshold)
            && velocity >= minVelocity
    }
}
