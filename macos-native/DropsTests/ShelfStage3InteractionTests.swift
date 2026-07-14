import AppKit
import XCTest
@testable import Drops

@MainActor
final class ShelfStage3InteractionTests: XCTestCase {
    func testContextMenuKeepsMultiSelectWhenHittingInsideSelection() {
        let a = ShelfItemID()
        let b = ShelfItemID()
        let c = ShelfItemID()
        let current: Set<ShelfItemID> = [a, b]
        XCTAssertEqual(
            ShelfContextMenuSelection.resolved(hitID: b, current: current),
            current
        )
        XCTAssertEqual(
            ShelfContextMenuSelection.resolved(hitID: c, current: current),
            [c]
        )
        XCTAssertNil(ShelfContextMenuSelection.resolved(hitID: nil, current: current))
    }

    func testCollectionClickTargetPrefersConcreteIndexOverUnorderedSet() {
        let paths: Set<IndexPath> = [
            IndexPath(item: 0, section: 0),
            IndexPath(item: 3, section: 0),
            IndexPath(item: 1, section: 0),
        ]
        XCTAssertEqual(
            ShelfCollectionClickTarget.resolve(clickedIndex: 3, fallbackIndexPaths: paths),
            3
        )
        XCTAssertEqual(
            ShelfCollectionClickTarget.resolve(
                clickedIndex: nil,
                fallbackIndexPaths: [IndexPath(item: 2, section: 0)]
            ),
            2
        )
        XCTAssertNil(
            ShelfCollectionClickTarget.resolve(clickedIndex: nil, fallbackIndexPaths: paths),
            "Ambiguous multi-path fallback must not pick an arbitrary Set.first"
        )
    }

    func testRightClickUnselectedItemUpdatesLocalSelectionBeforeMenuActions() {
        let shelf = Shelf(source: .menu, lifecycle: .persistent, presentation: .expanded)
        let drafts = (0..<3).map {
            ShelfItemDraft.file(url: URL(fileURLWithPath: "/tmp/ctx-\($0).txt"), isDirectory: false)
        }
        _ = shelf.insertItems(drafts)
        let ids = shelf.items.map(\.id)
        shelf.setSelection([ids[0], ids[1]])

        let controller = ShelfContentViewController()
        _ = controller.view
        var selectionEvents: [(ShelfItemID, SelectionModifiers)] = []
        controller.onSelectionClick = { id, mods, _ in
            selectionEvents.append((id, mods))
            shelf.applySelectionClick(itemID: id, modifiers: mods, anchorID: id)
        }
        controller.apply(shelf: shelf)

        // Right-click outside the current selection → replace with hit only.
        controller.prepareContextMenuSelectionForTesting(hitID: ids[2])
        XCTAssertEqual(selectionEvents.last?.0, ids[2])
        XCTAssertEqual(selectionEvents.last?.1, .replace)
        XCTAssertEqual(shelf.selection, [ids[2]])

        // Right-click inside multi-select → keep multi-select (no replace event).
        shelf.setSelection([ids[0], ids[1]])
        controller.apply(shelf: shelf)
        selectionEvents.removeAll()
        controller.prepareContextMenuSelectionForTesting(hitID: ids[1])
        XCTAssertTrue(selectionEvents.isEmpty)
        XCTAssertEqual(shelf.selection, [ids[0], ids[1]])
    }

    func testScrollViewDisablesAutoresizingMaskBeforeLayout() {
        let controller = ShelfContentViewController()
        _ = controller.view
        let scrollViews = controller.view.subviews.compactMap { $0 as? NSScrollView }
        XCTAssertFalse(scrollViews.isEmpty)
        for scrollView in scrollViews {
            XCTAssertFalse(
                scrollView.translatesAutoresizingMaskIntoConstraints,
                "REV-S3-001: must be false before Auto Layout constraints activate"
            )
        }
    }

    func testOpenMissingFileReportsRecoverableUserFacingError() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("drops-open-fail-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try ManagedTemporaryFileStore(retentionDays: 30, rootURL: root)
        let manager = ShelfManager(temporaryStore: store)
        var alerts: [(String, String)] = []
        manager.onUserFacingError = { title, message in
            alerts.append((title, message))
        }

        let shelfID = manager.createShelf(source: .menu, nearMouse: false)!
        let missing = URL(fileURLWithPath: "/tmp/drops-missing-\(UUID().uuidString).txt")
        XCTAssertTrue(
            manager.acceptContent(
                shelfId: shelfID,
                drafts: [.file(url: missing, isDirectory: false)]
            )
        )
        let itemID = manager.shelf(id: shelfID)!.items[0].id

        XCTAssertFalse(manager.openItem(shelfId: shelfID, itemID: itemID))
        XCTAssertEqual(alerts.count, 1)
        XCTAssertEqual(alerts[0].0, L10n.unableToOpen)
        XCTAssertTrue(
            alerts[0].1.contains(L10n.recoveryFileMissing)
                || alerts[0].1.contains("moved or deleted")
                || alerts[0].1.contains("移动或删除")
        )
    }

    func testCommandToggleDeselectUpdatesDomainSelection() {
        let shelf = Shelf(source: .menu, lifecycle: .persistent, presentation: .expanded)
        let drafts = (0..<3).map {
            ShelfItemDraft.file(url: URL(fileURLWithPath: "/tmp/toggle-\($0).txt"), isDirectory: false)
        }
        _ = shelf.insertItems(drafts)
        let ids = shelf.items.map(\.id)
        shelf.setSelection([ids[0], ids[1]])

        shelf.applySelectionClick(itemID: ids[1], modifiers: .toggle, anchorID: ids[0])
        XCTAssertEqual(shelf.selection, [ids[0]], "Command-deselect must drop the clicked item from domain selection")

        shelf.applySelectionClick(itemID: ids[2], modifiers: .toggle, anchorID: ids[0])
        XCTAssertEqual(shelf.selection, [ids[0], ids[2]])
    }
}
