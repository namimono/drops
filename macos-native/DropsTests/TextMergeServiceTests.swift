import XCTest
@testable import Drops

final class TextMergeServiceTests: XCTestCase {
    private var tempRoot: URL!
    private var store: ManagedTemporaryFileStore!
    private var service: TextMergeService!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("drops-merge-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        store = try ManagedTemporaryFileStore(retentionDays: 30, rootURL: tempRoot)
        service = TextMergeService(temporaryStore: store)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
        store = nil
        service = nil
        tempRoot = nil
    }

    func testMenuMergeJoinsInShelfOrderWithBlankLine() throws {
        let a = try makeTextItem(named: "a.txt", content: "第一段")
        let b = try makeTextItem(named: "b.txt", content: "第二段")
        let c = try makeTextItem(named: "c.txt", content: "第三段")

        let draft = try service.mergeMenuSelection([b, a, c])
        let text = try String(contentsOf: draft.fileURL!, encoding: .utf8)
        XCTAssertEqual(text, "第二段\n\n第一段\n\n第三段")
        XCTAssertEqual(draft.kind, .text)
        XCTAssertNotNil(draft.managedTemporaryFileID)
    }

    func testDragAppendKeepsTargetFirst() throws {
        let target = try makeTextItem(named: "target.txt", content: "目标")
        let s1 = try makeTextItem(named: "s1.txt", content: "来源一")
        let s2 = try makeTextItem(named: "s2.txt", content: "来源二")

        let draft = try service.mergeDragAppend(target: target, sources: [s1, s2])
        let text = try String(contentsOf: draft.fileURL!, encoding: .utf8)
        XCTAssertEqual(text, "目标\n\n来源一\n\n来源二")
    }

    func testRejectsNonTextInputs() throws {
        let text = try makeTextItem(named: "a.txt", content: "文本")
        let imageURL = tempRoot.appendingPathComponent("image.png")
        try Data([0x89, 0x50]).write(to: imageURL)
        let image = ShelfItem(
            identityKey: imageURL.path,
            displayName: "image.png",
            kind: .image,
            fileURL: imageURL
        )

        XCTAssertThrowsError(try service.mergeMenuSelection([text, image])) { error in
            XCTAssertEqual(error as? TextMergeError, .insufficientPlainTextItems)
        }
    }

    func testReplaceItemsInsertsMergedAtAnchorAndSelectsIt() throws {
        let shelf = Shelf(source: .menu, lifecycle: .persistent)
        let root = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: tempRoot,
            create: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let paths = ["a.txt", "b.txt", "c.txt"].map { root.appendingPathComponent($0) }
        for path in paths {
            try "x".write(to: path, atomically: true, encoding: .utf8)
        }
        _ = shelf.insertItems(paths.map { .file(url: $0, isDirectory: false) })
        // Newest-first: c, b, a
        let ids = shelf.items.map(\.id)
        shelf.setSelection(Set(ids))

        let mergedURL = root.appendingPathComponent("Merged Text.txt")
        try "merged".write(to: mergedURL, atomically: true, encoding: .utf8)
        let draft = ShelfItemDraft.managed(
            url: mergedURL,
            displayName: "Merged Text.txt",
            kind: .text,
            temporaryFileID: UUID()
        )

        let result = shelf.replaceItems(
            removing: Set(ids),
            inserting: draft,
            atAnchorID: ids[1] // b position in newest-first list (index 1)
        )
        XCTAssertEqual(shelf.items.count, 1)
        XCTAssertEqual(shelf.items[0].displayName, "Merged Text.txt")
        XCTAssertEqual(shelf.selection, [result.inserted.id])
        XCTAssertEqual(result.removed.count, 3)
    }

    private func makeTextItem(named name: String, content: String) throws -> ShelfItem {
        let url = tempRoot.appendingPathComponent(name)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return ShelfItem(
            identityKey: url.path,
            displayName: name,
            kind: .text,
            fileURL: url
        )
    }
}
