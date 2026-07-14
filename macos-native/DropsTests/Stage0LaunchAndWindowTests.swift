import AppKit
import XCTest
@testable import Drops

@MainActor
final class Stage0LaunchAndWindowTests: XCTestCase {
    func testHostAppInstallsDelegate() {
        XCTAssertNotNil(
            NSApplication.shared.delegate,
            "NSApp.delegate must be installed; storyboard-less apps need an explicit strong-held AppDelegate"
        )
        XCTAssertTrue(
            NSApplication.shared.delegate is AppDelegate,
            "Expected AppDelegate as NSApp.delegate"
        )
    }

    func testPersistentPanelIsActivatingAndCanBecomeKey() {
        let shelf = ShelfWindowController(shelfID: ShelfID(), openSource: .menu)
        XCTAssertFalse(
            shelf.styleMask.contains(.nonactivatingPanel),
            "Persistent shelf must not use .nonactivatingPanel (S0-05 / S1)"
        )
        XCTAssertTrue(shelf.canBecomeKeyWindow)
        shelf.show()
        XCTAssertTrue(shelf.isVisible)
        shelf.close()
    }

    func testTransientPanelKeepsNonactivatingMask() {
        let shelf = ShelfWindowController(shelfID: ShelfID(), openSource: .shake)
        XCTAssertTrue(
            shelf.styleMask.contains(.nonactivatingPanel),
            "Transient shelf must keep .nonactivatingPanel so it does not steal drag-source focus"
        )
        shelf.show()
        XCTAssertTrue(shelf.isVisible)
        XCTAssertTrue(shelf.isDragDestinationReady)
        shelf.close()
    }

    func testClosingOneShelfDoesNotCloseOthers() {
        let first = ShelfWindowController(shelfID: ShelfID(), openSource: .menu)
        let second = ShelfWindowController(shelfID: ShelfID(), openSource: .menu)
        var firstClosed = false
        var secondClosed = false
        first.onClose = { firstClosed = true }
        second.onClose = { secondClosed = true }

        first.show()
        second.show()
        XCTAssertTrue(first.isVisible)
        XCTAssertTrue(second.isVisible)

        first.close()
        XCTAssertTrue(firstClosed)
        XCTAssertFalse(secondClosed)
        XCTAssertFalse(first.isVisible)
        XCTAssertTrue(second.isVisible)

        second.close()
        XCTAssertTrue(secondClosed)
    }

    func testShowReportsFirstFrameMilestoneForPersistent() {
        let shelf = ShelfWindowController(shelfID: ShelfID(), openSource: .hotkey)
        let expectation = expectation(description: "firstFrameVisible")
        shelf.show { milestone in
            XCTAssertEqual(milestone, .firstFrameVisible)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)
        shelf.close()
    }

    func testShowReportsDragReadyMilestoneForTransient() {
        let shelf = ShelfWindowController(shelfID: ShelfID(), openSource: .shake)
        let expectation = expectation(description: "dragReady")
        shelf.show { milestone in
            XCTAssertEqual(milestone, .dragReady)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)
        XCTAssertTrue(shelf.isDragDestinationReady)
        shelf.close()
    }
}
