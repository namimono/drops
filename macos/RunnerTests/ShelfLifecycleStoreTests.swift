import XCTest

final class ShelfLifecycleStoreTests: XCTestCase {
  var store: ShelfLifecycleStore!

  override func setUp() {
    super.setUp()
    store = ShelfLifecycleStore()
  }

  func testHotkeyCreateIsPersistent() {
    let (session, reason) = store.createShelf(source: .hotkey)
    XCTAssertNil(reason)
    XCTAssertEqual(session?.lifecycle, .persistent)
  }

  func testMenuCreateIsPersistent() {
    let (session, _) = store.createShelf(source: .menu)
    XCTAssertEqual(session?.lifecycle, .persistent)
  }

  func testShakeCreateIsTransient() {
    store.beginExternalDrag(dragSessionId: "drag-1")
    let (session, reason) = store.createShelf(source: .shake, dragSessionId: "drag-1")
    XCTAssertNil(reason)
    XCTAssertEqual(session?.lifecycle, .transient)
    XCTAssertEqual(store.dragSession?.shakeShelfId, session?.id)
  }

  func testSameDragRejectsSecondShake() {
    store.beginExternalDrag(dragSessionId: "drag-1")
    _ = store.createShelf(source: .shake, dragSessionId: "drag-1")
    let (session, reason) = store.createShelf(source: .shake, dragSessionId: "drag-1")
    XCTAssertNil(session)
    XCTAssertEqual(reason, "shake_shelf_already_exists")
    XCTAssertEqual(store.activeCount, 1)
  }

  func testDropAcceptedPromotesTransient() {
    store.beginExternalDrag(dragSessionId: "drag-1")
    let (session, _) = store.createShelf(source: .shake, dragSessionId: "drag-1")
    let id = session!.id
    XCTAssertTrue(store.markDropAccepted(shelfId: id, dragSessionId: "drag-1"))
    XCTAssertEqual(store.session(id: id)?.lifecycle, .persistent)
  }

  func testShakeWithoutDropClosesOnDragEnd() {
    store.beginExternalDrag(dragSessionId: "drag-1")
    let (session, _) = store.createShelf(source: .shake, dragSessionId: "drag-1")
    let toClose = store.endExternalDrag(dragSessionId: "drag-1")
    XCTAssertEqual(toClose, [session!.id])
  }

  func testPersistentSurvivesDragEnd() {
    store.beginExternalDrag(dragSessionId: "drag-1")
    let (session, _) = store.createShelf(source: .shake, dragSessionId: "drag-1")
    _ = store.markDropAccepted(shelfId: session!.id, dragSessionId: "drag-1")
    let toClose = store.endExternalDrag(dragSessionId: "drag-1")
    XCTAssertTrue(toClose.isEmpty)
  }

  func testMaxShelves() {
    for _ in 0..<20 {
      let (_, reason) = store.createShelf(source: .hotkey)
      XCTAssertNil(reason)
    }
    let (session, reason) = store.createShelf(source: .hotkey)
    XCTAssertNil(session)
    XCTAssertEqual(reason, "max_shelves_reached")
  }

  func testClosingIgnoresEvents() {
    let (session, _) = store.createShelf(source: .menu)
    let id = session!.id
    XCTAssertTrue(store.beginClose(shelfId: id))
    XCTAssertTrue(store.shouldIgnoreEvent(shelfId: id))
    XCTAssertFalse(store.markDropAccepted(shelfId: id))
  }
}
