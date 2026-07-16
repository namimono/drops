import XCTest
@testable import Drops

final class ShakeDetectionTests: XCTestCase {
    func testDetectsHorizontalShakeWithSufficientVelocity() {
        let now = Date()
        // Zig-zag over 0.5s with plenty of distance.
        let positions: [CGPoint] = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 80, y: 0),
            CGPoint(x: 0, y: 0),
            CGPoint(x: 80, y: 0),
            CGPoint(x: 0, y: 0),
            CGPoint(x: 80, y: 0),
        ]
        let timestamps = (0..<positions.count).map {
            now.addingTimeInterval(Double($0) * 0.08)
        }
        XCTAssertTrue(
            ShakeDetector.detect(
                positions: positions,
                timestamps: timestamps
            )
        )
    }

    func testRejectsSlowMovementWithoutDirectionChanges() {
        let now = Date()
        let positions: [CGPoint] = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 10, y: 0),
            CGPoint(x: 20, y: 0),
            CGPoint(x: 30, y: 0),
        ]
        let timestamps = (0..<positions.count).map {
            now.addingTimeInterval(Double($0) * 0.3)
        }
        XCTAssertFalse(
            ShakeDetector.detect(
                positions: positions,
                timestamps: timestamps
            )
        )
    }

    func testHighSensitivityAcceptsFewerDirectionChangesThanMedium() {
        let now = Date()
        // 3 horizontal reversals — enough for high (threshold 3), not for medium (4).
        let positions: [CGPoint] = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 100, y: 0),
            CGPoint(x: 0, y: 0),
            CGPoint(x: 100, y: 0),
            CGPoint(x: 0, y: 0),
        ]
        let timestamps = (0..<positions.count).map {
            now.addingTimeInterval(Double($0) * 0.08)
        }
        let high = SettingsStore.ShakeSensitivity.high
        let medium = SettingsStore.ShakeSensitivity.medium
        XCTAssertTrue(
            ShakeDetector.detect(
                positions: positions,
                timestamps: timestamps,
                threshold: high.threshold,
                minVelocity: high.minVelocity
            )
        )
        XCTAssertFalse(
            ShakeDetector.detect(
                positions: positions,
                timestamps: timestamps,
                threshold: medium.threshold,
                minVelocity: medium.minVelocity
            )
        )
    }
}
