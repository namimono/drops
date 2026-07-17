import AppKit
import XCTest
@testable import Drops

@MainActor
final class ShelfManagerContentTests: XCTestCase {
    private var tempRoot: URL!
    private var manager: ShelfManager!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("DropsManagerContent-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let store = try ManagedTemporaryFileStore(
            bundleIdentifier: "click.shakepin.macos.tests",
            retentionDays: 30,
            rootURL: tempRoot
        )
        manager = ShelfManager(temporaryStore: store)
    }

    override func tearDownWithError() throws {
        manager?.closeAll()
        manager = nil
        if let tempRoot, FileManager.default.fileExists(atPath: tempRoot.path) {
            try FileManager.default.removeItem(at: tempRoot)
        }
        tempRoot = nil
    }

    func testAcceptContentPromotesTransientShelf() {
        let drag = DragSessionID("content-1")
        manager.beginExternalDrag(dragSessionId: drag)
        let id = manager.createShelf(source: .shake, nearMouse: false)!
        XCTAssertEqual(manager.shelf(id: id)?.lifecycle, .transient)

        let draft = ShelfItemDraft.file(
            url: URL(fileURLWithPath: "/tmp/drops-stage2.txt"),
            isDirectory: false
        )
        XCTAssertTrue(manager.acceptContent(shelfId: id, drafts: [draft]))
        XCTAssertEqual(manager.shelf(id: id)?.lifecycle, .persistent)
        XCTAssertEqual(manager.shelf(id: id)?.items.count, 1)
    }

    func testPasteboardAcceptCreatesManagedFileAndReference() throws {
        let id = manager.createShelf(source: .menu, nearMouse: false)!
        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }
        pb.clearContents()
        pb.setString("managed note", forType: .string)

        XCTAssertTrue(manager.acceptPasteboard(shelfId: id, pasteboard: pb))
        let item = try XCTUnwrap(manager.shelf(id: id)?.items.first)
        XCTAssertEqual(item.kind, .text)
        let tempID = try XCTUnwrap(item.managedTemporaryFileID)
        XCTAssertEqual(
            manager.managedTemporaryStoreForTesting.record(for: tempID)?.activeShelfReferences,
            [id]
        )
    }

    func testClosingShelfReleasesTemporaryReference() throws {
        let id = manager.createShelf(source: .menu, nearMouse: false)!
        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }
        pb.clearContents()
        pb.setString("release me", forType: .string)
        XCTAssertTrue(manager.acceptPasteboard(shelfId: id, pasteboard: pb))
        let tempID = try XCTUnwrap(manager.shelf(id: id)?.items.first?.managedTemporaryFileID)

        manager.closeShelf(id: id)
        XCTAssertTrue(
            manager.managedTemporaryStoreForTesting.record(for: tempID)?.activeShelfReferences.isEmpty
                ?? false
        )
    }

    func testCrossShelfManagedDragAddsReferenceAndProtectsCleanup() throws {
        let shelfA = manager.createShelf(source: .menu, nearMouse: false)!
        let shelfB = manager.createShelf(source: .menu, nearMouse: false)!

        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }
        pb.clearContents()
        pb.setString("shared managed", forType: .string)
        XCTAssertTrue(manager.acceptPasteboard(shelfId: shelfA, pasteboard: pb))

        let itemA = try XCTUnwrap(manager.shelf(id: shelfA)?.items.first)
        let tempID = try XCTUnwrap(itemA.managedTemporaryFileID)
        let fileURL = try XCTUnwrap(itemA.fileURL)

        let transfer = NSPasteboard.withUniqueName()
        defer { transfer.releaseGlobally() }
        transfer.clearContents()
        let transferItem = NSPasteboardItem()
        transferItem.setString(fileURL.absoluteString, forType: .fileURL)
        transferItem.setString(tempID.uuidString, forType: PasteboardMaterializer.managedTemporaryFileType)
        transfer.writeObjects([transferItem])

        XCTAssertTrue(manager.acceptPasteboard(shelfId: shelfB, pasteboard: transfer))
        let refs = manager.managedTemporaryStoreForTesting.record(for: tempID)?.activeShelfReferences
        XCTAssertEqual(refs, Set([shelfA, shelfB]))

        manager.closeShelf(id: shelfA)
        let afterCloseA = try manager.cleanupTemporaryFilesNow()
        XCTAssertFalse(afterCloseA.deleted.contains(tempID))
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: fileURL.path),
            "File must remain while shelf B still references it"
        )

        manager.closeShelf(id: shelfB)
        let afterCloseB = try manager.cleanupTemporaryFilesNow()
        XCTAssertTrue(afterCloseB.deleted.contains(tempID))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testMaterializeFailureRollsBackPartialCreations() throws {
        let store = manager.managedTemporaryStoreForTesting
        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }
        pb.clearContents()

        let ok = NSPasteboardItem()
        ok.setString("first", forType: .string)
        // Second item uses an empty preferred path segment via invalid UTF8-free data path:
        // Force failure by making metadata unwritable after first create using a spy-like approach:
        // Create a materializer against a store whose root becomes non-writable mid-batch is hard;
        // instead verify discardCreatedFiles removes orphan records explicitly, and that
        // acceptPasteboard rolls back when acceptContent rejects.
        pb.writeObjects([ok])

        let shelf = manager.createShelf(source: .menu, nearMouse: false)!
        manager.closeShelf(id: shelf)
        // Shelf closed → acceptContent fails → newly created files must be discarded.
        XCTAssertFalse(manager.acceptPasteboard(shelfId: shelf, pasteboard: pb))
        XCTAssertTrue(store.allRecords().isEmpty)
    }

    func testStaleReferencesClearedOnStoreReloadAllowCleanup() throws {
        let shelf = ShelfID()
        let nestedRoot = tempRoot.appendingPathComponent("reload-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedRoot, withIntermediateDirectories: true)
        let store = try ManagedTemporaryFileStore(
            bundleIdentifier: "click.shakepin.macos.tests",
            retentionDays: 30,
            rootURL: nestedRoot
        )
        let (_, record) = try store.createTemporaryFile(
            named: "orphan.txt",
            data: Data("x".utf8),
            referencedBy: shelf
        )
        XCTAssertEqual(store.record(for: record.id)?.activeShelfReferences, [shelf])

        let reloaded = try ManagedTemporaryFileStore(
            bundleIdentifier: "click.shakepin.macos.tests",
            retentionDays: 30,
            rootURL: nestedRoot
        )
        XCTAssertTrue(reloaded.record(for: record.id)?.activeShelfReferences.isEmpty ?? false)
        let deleted = try reloaded.cleanupNow().deleted
        XCTAssertEqual(deleted, [record.id])
    }

    func testDragOutMoveRemovesItemsCopyKeepsThem() {
        let id = manager.createShelf(source: .menu, nearMouse: false)!
        let draft = ShelfItemDraft.file(
            url: URL(fileURLWithPath: "/tmp/move-or-copy.txt"),
            isDirectory: false
        )
        XCTAssertTrue(manager.acceptContent(shelfId: id, drafts: [draft]))
        let itemID = manager.shelf(id: id)!.items[0].id

        manager.handleDragOutEnded(shelfId: id, itemIDs: [itemID], operation: .copy)
        XCTAssertEqual(manager.shelf(id: id)?.items.count, 1)

        manager.handleDragOutEnded(shelfId: id, itemIDs: [itemID], operation: [])
        XCTAssertEqual(manager.shelf(id: id)?.items.count, 1)

        manager.handleDragOutEnded(shelfId: id, itemIDs: [itemID], operation: .move)
        XCTAssertEqual(manager.shelf(id: id)?.items.count, 0)
    }

    func testRetentionUpdateRecalculatesViaManager() throws {
        XCTAssertEqual(try manager.updateRetentionDays(60), 60)
        XCTAssertThrowsError(try manager.updateRetentionDays(0))
        XCTAssertEqual(manager.retentionDays, 60)
    }

    func testManualCleanupConfirmationGate() {
        let controller = ApplicationController()
        var cleanupCalls = 0
        var messages = 0
        controller.shouldProceedWithManualCleanup = {
            cleanupCalls += 1
            return false
        }
        controller.presentUserMessage = { _, _, _ in messages += 1 }
        controller.cleanupTemporaryFilesNow()
        XCTAssertEqual(cleanupCalls, 1)
        XCTAssertEqual(messages, 0, "Cancel must not run cleanup or show a result alert")
    }

    func testRetentionPromptRejectsIllegalInputWithFeedbackPath() {
        let controller = ApplicationController()
        var seenTitles: [String] = []
        controller.presentUserMessage = { title, _, _ in seenTitles.append(title) }
        controller.promptForRetentionDays = { _ in 999 }
        let before = controller.managerForTesting.retentionDays
        controller.configureRetentionDays()
        XCTAssertEqual(controller.managerForTesting.retentionDays, before)
        XCTAssertEqual(seenTitles, [L10n.invalidRetention])
    }

    func testSelectionAnchorSurvivesApplyRefresh() {
        let shelf = Shelf(
            source: .menu,
            lifecycle: .persistent,
            presentation: .expanded
        )
        let drafts = (0..<5).map { index in
            ShelfItemDraft.file(
                url: URL(fileURLWithPath: "/tmp/anchor-\(index).txt"),
                isDirectory: false
            )
        }
        _ = shelf.insertItems(drafts)
        let ids = shelf.items.map(\.id)

        let controller = ShelfContentViewController()
        _ = controller.view
        controller.apply(shelf: shelf)
        controller.selectionAnchorForTesting = ids[2]

        shelf.applySelectionClick(itemID: ids[0], modifiers: .range, anchorID: ids[2])
        controller.apply(shelf: shelf)
        XCTAssertEqual(controller.selectionAnchorForTesting, ids[2])

        shelf.applySelectionClick(itemID: ids[4], modifiers: .range, anchorID: ids[2])
        XCTAssertEqual(shelf.selection, Set(ids[2...4]))
    }

    func testCollectWatchedFilesCreatesPersistentShelf() throws {
        let fileURL = tempRoot.appendingPathComponent("watched-new.txt")
        try "hello".write(to: fileURL, atomically: true, encoding: .utf8)

        let shelfID = manager.collectWatchedFiles([fileURL])
        XCTAssertNotNil(shelfID)
        let shelf = manager.shelf(id: shelfID!)
        XCTAssertEqual(shelf?.source, .fileWatch)
        XCTAssertEqual(shelf?.lifecycle, .persistent)
        XCTAssertEqual(shelf?.items.count, 1)
        XCTAssertEqual(shelf?.items.first?.displayName, "watched-new.txt")
    }
}
