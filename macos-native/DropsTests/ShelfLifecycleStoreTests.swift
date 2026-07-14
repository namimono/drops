import XCTest
@testable import Drops

final class ShelfLifecycleStoreTests: XCTestCase {
    private var store: ShelfLifecycleStore!

    override func setUp() {
        super.setUp()
        store = ShelfLifecycleStore()
    }

    func testHotkeyCreateIsPersistent() {
        let result = store.createShelf(source: .hotkey)
        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(result.shelf?.lifecycle, .persistent)
        XCTAssertEqual(result.shelf?.source, .hotkey)
        XCTAssertEqual(result.shelf?.presentation, .empty)
    }

    func testMenuCreateIsPersistent() {
        let result = store.createShelf(source: .menu)
        XCTAssertEqual(result.shelf?.lifecycle, .persistent)
    }

    func testShakeCreateIsTransient() {
        store.beginExternalDrag(dragSessionId: DragSessionID("drag-1"))
        let result = store.createShelf(source: .shake, dragSessionId: DragSessionID("drag-1"))
        XCTAssertNil(result.rejection)
        XCTAssertEqual(result.shelf?.lifecycle, .transient)
        XCTAssertEqual(store.dragSession?.shakeShelfId, result.shelf?.id)
    }

    func testSameDragRejectsSecondShake() {
        store.beginExternalDrag(dragSessionId: DragSessionID("drag-1"))
        _ = store.createShelf(source: .shake, dragSessionId: DragSessionID("drag-1"))
        let second = store.createShelf(source: .shake, dragSessionId: DragSessionID("drag-1"))
        XCTAssertNil(second.shelf)
        XCTAssertEqual(second.rejection, .shakeShelfAlreadyExists)
        XCTAssertEqual(store.activeCount, 1)
    }

    func testDropAcceptedPromotesTransient() {
        store.beginExternalDrag(dragSessionId: DragSessionID("drag-1"))
        let created = store.createShelf(source: .shake, dragSessionId: DragSessionID("drag-1"))
        let id = created.shelf!.id
        XCTAssertTrue(store.markDropAccepted(shelfId: id, dragSessionId: DragSessionID("drag-1")))
        XCTAssertEqual(store.shelf(id: id)?.lifecycle, .persistent)
        XCTAssertTrue(store.shelf(id: id)?.acceptedDrop == true)
    }

    func testSimulateReceivePromotesAndLeavesCollapsed() {
        store.beginExternalDrag(dragSessionId: DragSessionID("drag-1"))
        let created = store.createShelf(source: .shake, dragSessionId: DragSessionID("drag-1"))
        let id = created.shelf!.id
        XCTAssertTrue(store.simulateReceiveContent(shelfId: id, named: "a.txt"))
        XCTAssertEqual(store.shelf(id: id)?.lifecycle, .persistent)
        XCTAssertEqual(store.shelf(id: id)?.presentation, .collapsed)
        XCTAssertEqual(store.shelf(id: id)?.items.count, 1)
    }

    func testShakeWithoutDropClosesOnDragEnd() {
        store.beginExternalDrag(dragSessionId: DragSessionID("drag-1"))
        let created = store.createShelf(source: .shake, dragSessionId: DragSessionID("drag-1"))
        let toClose = store.endExternalDrag(dragSessionId: DragSessionID("drag-1"))
        XCTAssertEqual(toClose, [created.shelf!.id])
    }

    func testPersistentSurvivesDragEnd() {
        store.beginExternalDrag(dragSessionId: DragSessionID("drag-1"))
        let created = store.createShelf(source: .shake, dragSessionId: DragSessionID("drag-1"))
        _ = store.markDropAccepted(shelfId: created.shelf!.id)
        let toClose = store.endExternalDrag(dragSessionId: DragSessionID("drag-1"))
        XCTAssertTrue(toClose.isEmpty)
        XCTAssertEqual(store.shelf(id: created.shelf!.id)?.lifecycle, .persistent)
    }

    func testNewDragSessionCanCreateAnotherShakeShelf() {
        store.beginExternalDrag(dragSessionId: DragSessionID("drag-1"))
        let first = store.createShelf(source: .shake, dragSessionId: DragSessionID("drag-1"))
        _ = store.markDropAccepted(shelfId: first.shelf!.id)
        _ = store.endExternalDrag(dragSessionId: DragSessionID("drag-1"))

        store.beginExternalDrag(dragSessionId: DragSessionID("drag-2"))
        let second = store.createShelf(source: .shake, dragSessionId: DragSessionID("drag-2"))
        XCTAssertTrue(second.isSuccess)
        XCTAssertEqual(store.activeCount, 2)
    }

    func testMaxShelvesTwentiethAllowedTwentyFirstRejected() {
        for _ in 0..<20 {
            XCTAssertTrue(store.createShelf(source: .hotkey).isSuccess)
        }
        let overflow = store.createShelf(source: .hotkey)
        XCTAssertFalse(overflow.isSuccess)
        XCTAssertEqual(overflow.rejection, .maxShelvesReached)
        XCTAssertEqual(store.activeCount, 20)
    }

    func testClosingIgnoresLateEvents() {
        let created = store.createShelf(source: .menu)
        let id = created.shelf!.id
        XCTAssertTrue(store.beginClose(shelfId: id))
        XCTAssertTrue(store.shouldIgnoreEvent(shelfId: id))
        XCTAssertFalse(store.markDropAccepted(shelfId: id))
        XCTAssertFalse(store.simulateReceiveContent(shelfId: id))
        XCTAssertFalse(store.setPresentation(shelfId: id, presentation: .expanded))
        store.markClosed(shelfId: id)
        XCTAssertTrue(store.shouldIgnoreEvent(shelfId: id))
        XCTAssertNil(store.shelf(id: id))
    }

    func testUserCloseOnTransientBeginsClosing() {
        store.beginExternalDrag(dragSessionId: DragSessionID("drag-1"))
        let created = store.createShelf(source: .shake, dragSessionId: DragSessionID("drag-1"))
        let id = created.shelf!.id
        XCTAssertTrue(store.beginClose(shelfId: id))
        XCTAssertEqual(store.shelf(id: id)?.lifecycle, .closing)
    }

    func testPresentationToggleDoesNotChangeLifecycle() {
        let created = store.createShelf(source: .menu)
        let id = created.shelf!.id
        _ = store.simulateReceiveContent(shelfId: id)
        XCTAssertTrue(store.setPresentation(shelfId: id, presentation: .expanded))
        XCTAssertEqual(store.shelf(id: id)?.presentation, .expanded)
        XCTAssertEqual(store.shelf(id: id)?.lifecycle, .persistent)
        XCTAssertTrue(store.setPresentation(shelfId: id, presentation: .collapsed))
        XCTAssertEqual(store.shelf(id: id)?.presentation, .collapsed)
        XCTAssertEqual(store.shelf(id: id)?.lifecycle, .persistent)
    }

    func testPersistentEmptyDoesNotAutoClose() {
        let created = store.createShelf(source: .hotkey)
        let id = created.shelf!.id
        XCTAssertEqual(store.shelf(id: id)?.lifecycle, .persistent)
        XCTAssertTrue(store.shelf(id: id)?.isEmpty == true)
        // No timer / focus-loss path exists; shelf remains until beginClose.
        XCTAssertFalse(store.shouldIgnoreEvent(shelfId: id))
        XCTAssertEqual(store.activeCount, 1)
    }
}
