import XCTest
@testable import Drops

final class ShelfItemDomainTests: XCTestCase {
    func testInsertPlacesNewItemsFirstAndDedupsByIdentity() {
        let shelf = Shelf(source: .menu, lifecycle: .persistent)
        let a = ShelfItemDraft.file(url: URL(fileURLWithPath: "/tmp/a.txt"), isDirectory: false)
        let b = ShelfItemDraft.file(url: URL(fileURLWithPath: "/tmp/b.txt"), isDirectory: false)
        let c = ShelfItemDraft.file(url: URL(fileURLWithPath: "/tmp/c.txt"), isDirectory: false)

        _ = shelf.insertItems([a, b])
        XCTAssertEqual(shelf.items.map(\.identityKey), [a.identityKey, b.identityKey])

        _ = shelf.insertItems([c, a])
        XCTAssertEqual(
            shelf.items.map(\.identityKey),
            [c.identityKey, a.identityKey, b.identityKey],
            "New batch leads; duplicate a moves forward without a second copy"
        )
        XCTAssertEqual(shelf.items.count, 3)
    }

    func testInsertedItemsJoinSelection() {
        let shelf = Shelf(source: .menu, lifecycle: .persistent)
        let a = ShelfItemDraft.file(url: URL(fileURLWithPath: "/tmp/a.txt"), isDirectory: false)
        let b = ShelfItemDraft.file(url: URL(fileURLWithPath: "/tmp/b.txt"), isDirectory: false)
        _ = shelf.insertItems([a])
        let firstID = shelf.items[0].id
        shelf.setSelection([firstID])

        _ = shelf.insertItems([b])
        XCTAssertTrue(shelf.selection.contains(shelf.items[0].id))
        XCTAssertTrue(shelf.selection.contains(firstID))
    }

    func testSelectionClickReplaceToggleAndRange() {
        let shelf = Shelf(source: .menu, lifecycle: .persistent)
        let drafts = (0..<4).map {
            ShelfItemDraft.file(url: URL(fileURLWithPath: "/tmp/\($0).txt"), isDirectory: false)
        }
        _ = shelf.insertItems(drafts)
        let ids = shelf.items.map(\.id)

        shelf.applySelectionClick(itemID: ids[1], modifiers: .replace, anchorID: nil)
        XCTAssertEqual(shelf.selection, [ids[1]])

        shelf.applySelectionClick(itemID: ids[3], modifiers: .toggle, anchorID: ids[1])
        XCTAssertEqual(shelf.selection, [ids[1], ids[3]])

        shelf.applySelectionClick(itemID: ids[0], modifiers: .range, anchorID: ids[2])
        // Visual order is newest-first: ids[0], ids[1], ids[2], ids[3]
        XCTAssertEqual(shelf.selection, Set(ids[0...2]))
    }

    func testDragOutUsesSelectionOrSingleOrCollapsedStack() {
        let shelf = Shelf(source: .menu, lifecycle: .persistent)
        let drafts = (0..<3).map {
            ShelfItemDraft.file(url: URL(fileURLWithPath: "/tmp/\($0).txt"), isDirectory: false)
        }
        _ = shelf.insertItems(drafts)
        let ids = shelf.items.map(\.id)
        shelf.setSelection([ids[0], ids[2]])

        let selected = shelf.itemsForDragOut(primaryItemID: ids[0], draggingCollapsedStack: false)
        XCTAssertEqual(Set(selected.map(\.id)), [ids[0], ids[2]])

        let single = shelf.itemsForDragOut(primaryItemID: ids[1], draggingCollapsedStack: false)
        XCTAssertEqual(single.map(\.id), [ids[1]])

        let stack = shelf.itemsForDragOut(primaryItemID: nil, draggingCollapsedStack: true)
        XCTAssertEqual(stack.count, 3)
    }

    func testMoveRemovalClearsItemsAndEmptyPresentation() {
        let shelf = Shelf(source: .menu, lifecycle: .persistent)
        let draft = ShelfItemDraft.file(url: URL(fileURLWithPath: "/tmp/only.txt"), isDirectory: false)
        _ = shelf.insertItems([draft])
        XCTAssertEqual(shelf.presentation, .collapsed)
        let id = shelf.items[0].id
        _ = shelf.removeItems(ids: [id])
        XCTAssertTrue(shelf.items.isEmpty)
        XCTAssertEqual(shelf.presentation, .empty)
    }
}
