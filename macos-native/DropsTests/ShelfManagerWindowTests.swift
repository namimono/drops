import AppKit
import XCTest
@testable import Drops

@MainActor
final class ShelfManagerWindowTests: XCTestCase {
    func testManagerCreatesIndependentShelves() {
        let manager = ShelfManager()
        let first = manager.createShelf(source: .menu, nearMouse: false)
        let second = manager.createShelf(source: .menu, nearMouse: false)
        XCTAssertNotNil(first)
        XCTAssertNotNil(second)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(manager.activeCount, 2)

        manager.closeShelf(id: first!)
        XCTAssertEqual(manager.activeCount, 1)
        XCTAssertNil(manager.shelf(id: first!))
        XCTAssertNotNil(manager.shelf(id: second!))
        manager.closeAll()
    }

    func testManagerRejectsTwentyFirstShelf() {
        let manager = ShelfManager()
        for _ in 0..<20 {
            XCTAssertNotNil(manager.createShelf(source: .hotkey, nearMouse: false))
        }
        XCTAssertNil(manager.createShelf(source: .hotkey, nearMouse: false))
        XCTAssertEqual(manager.activeCount, 20)
        manager.closeAll()
    }

    func testLateEventsAfterCloseAreIgnored() {
        let manager = ShelfManager()
        let id = manager.createShelf(source: .menu, nearMouse: false)!
        manager.closeShelf(id: id)

        var ran = false
        manager.handleLateEvent(shelfId: id) { ran = true }
        XCTAssertFalse(ran)
        XCTAssertFalse(manager.simulateReceiveContent(shelfId: id))
        XCTAssertFalse(manager.setPresentation(shelfId: id, presentation: .expanded))
    }

    func testPresentationRapidToggleDoesNotLeaveInconsistentState() {
        let manager = ShelfManager()
        let id = manager.createShelf(source: .menu, nearMouse: false)!
        XCTAssertTrue(manager.simulateReceiveContent(shelfId: id))

        for _ in 0..<20 {
            manager.toggleExpand(shelfId: id)
        }
        let shelf = manager.shelf(id: id)
        XCTAssertNotNil(shelf)
        XCTAssertTrue(shelf?.presentation == .collapsed || shelf?.presentation == .expanded)
        XCTAssertEqual(shelf?.lifecycle, .persistent)

        let expected = ShelfWindowController.size(for: shelf!.presentation)
        let frame = manager.windowFrame(shelfId: id)
        XCTAssertNotNil(frame)
        XCTAssertEqual(frame!.size.width, expected.width, accuracy: 0.5)
        XCTAssertEqual(frame!.size.height, expected.height, accuracy: 0.5)
        manager.closeAll()
    }

    func testPresentationToggleSettlesToTargetFrameWithAnimation() {
        let manager = ShelfManager()
        let id = manager.createShelf(source: .menu, nearMouse: false)!
        manager.setAnimatesPresentationChanges(true, for: id)
        XCTAssertTrue(manager.simulateReceiveContent(shelfId: id))
        XCTAssertEqual(manager.shelf(id: id)?.presentation, .collapsed)

        let collapsed = ShelfWindowController.size(for: .collapsed)
        let collapsedReady = expectation(description: "collapsed frame after animation")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            let frame = manager.windowFrame(shelfId: id)
            XCTAssertEqual(frame?.size.width ?? -1, collapsed.width, accuracy: 0.5)
            XCTAssertEqual(frame?.size.height ?? -1, collapsed.height, accuracy: 0.5)
            collapsedReady.fulfill()
        }
        wait(for: [collapsedReady], timeout: 1.5)

        manager.toggleExpand(shelfId: id)
        XCTAssertEqual(manager.shelf(id: id)?.presentation, .expanded)
        let expanded = ShelfWindowController.size(for: .expanded)
        let expandedReady = expectation(description: "expanded frame after animation")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            let frame = manager.windowFrame(shelfId: id)
            XCTAssertEqual(frame?.size.width ?? -1, expanded.width, accuracy: 0.5)
            XCTAssertEqual(frame?.size.height ?? -1, expanded.height, accuracy: 0.5)
            expandedReady.fulfill()
        }
        wait(for: [expandedReady], timeout: 1.5)
        manager.closeAll()
    }

    func testPreemptedDragClosesOrphanTransientWindow() {
        let manager = ShelfManager()
        let drag1 = DragSessionID("preempt-1")
        manager.beginExternalDrag(dragSessionId: drag1)
        let orphan = manager.createShelf(source: .shake, nearMouse: false)!

        let drag2 = DragSessionID("preempt-2")
        manager.beginExternalDrag(dragSessionId: drag2)
        XCTAssertNil(manager.shelf(id: orphan))

        let replacement = manager.createShelf(source: .shake, nearMouse: false)!
        manager.endExternalDrag(dragSessionId: drag2)
        XCTAssertNil(manager.shelf(id: replacement))
        manager.closeAll()
    }

    func testTransientPromoteAndAutoCloseViaSimulatedDrag() {
        let manager = ShelfManager()
        let dragID = DragSessionID("test-drag")
        manager.beginExternalDrag(dragSessionId: dragID)
        let promoted = manager.createShelf(source: .shake, nearMouse: false)!
        XCTAssertTrue(manager.simulateReceiveContent(shelfId: promoted))
        XCTAssertEqual(manager.shelf(id: promoted)?.lifecycle, .persistent)
        manager.endExternalDrag(dragSessionId: dragID)
        XCTAssertEqual(manager.shelf(id: promoted)?.lifecycle, .persistent)

        let dragID2 = DragSessionID("test-drag-2")
        manager.beginExternalDrag(dragSessionId: dragID2)
        let doomed = manager.createShelf(source: .shake, nearMouse: false)!
        manager.endExternalDrag(dragSessionId: dragID2)
        XCTAssertNil(manager.shelf(id: doomed))
        manager.closeAll()
    }

}

final class ShelfWindowGeometryTests: XCTestCase {
    func testClampedOriginStaysInsideVisibleFrame() {
        let visible = NSRect(x: 0, y: 25, width: 1000, height: 775)
        let size = NSSize(width: 280, height: 220)

        let topLeft = ShelfWindowGeometry.clampedOrigin(
            NSPoint(x: -100, y: 900),
            size: size,
            visibleFrame: visible
        )
        XCTAssertEqual(topLeft.x, 8, accuracy: 0.5)
        XCTAssertEqual(topLeft.y, visible.maxY - size.height - 8, accuracy: 0.5)

        let bottomRight = ShelfWindowGeometry.clampedOrigin(
            NSPoint(x: 2000, y: -50),
            size: size,
            visibleFrame: visible
        )
        XCTAssertEqual(bottomRight.x, visible.maxX - size.width - 8, accuracy: 0.5)
        XCTAssertEqual(bottomRight.y, visible.minY + 8, accuracy: 0.5)
    }

    func testOriginNearMouseCentersThenClamps() {
        let size = NSSize(width: 200, height: 100)
        let mouse = NSPoint(x: 100, y: 100)
        let origin = ShelfWindowGeometry.originNearMouse(
            size: size,
            offset: .zero,
            mouseLocation: mouse,
            screens: NSScreen.screens
        )
        // Clamp uses the screen containing the mouse, not necessarily NSScreen.main.
        XCTAssertFalse(origin.x.isNaN)
        XCTAssertFalse(origin.y.isNaN)
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
            ?? NSScreen.main
        if let screen {
            let visible = screen.visibleFrame
            XCTAssertGreaterThanOrEqual(origin.x, visible.minX + 8 - 0.5)
            XCTAssertGreaterThanOrEqual(origin.y, visible.minY + 8 - 0.5)
            XCTAssertLessThanOrEqual(origin.x + size.width, visible.maxX - 8 + 0.5)
            XCTAssertLessThanOrEqual(origin.y + size.height, visible.maxY - 8 + 0.5)
        }
    }
}
