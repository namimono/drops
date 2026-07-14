import AppKit
import XCTest
@testable import Drops

final class PasteboardMaterializerTests: XCTestCase {
    private var tempRoot: URL!
    private var store: ManagedTemporaryFileStore!
    private var materializer: PasteboardMaterializer!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("DropsPasteboardTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        store = try ManagedTemporaryFileStore(
            bundleIdentifier: "click.shakepin.macos.tests",
            retentionDays: 30,
            rootURL: tempRoot
        )
        materializer = PasteboardMaterializer(temporaryStore: store)
    }

    override func tearDownWithError() throws {
        if let tempRoot, FileManager.default.fileExists(atPath: tempRoot.path) {
            try FileManager.default.removeItem(at: tempRoot)
        }
        store = nil
        materializer = nil
        tempRoot = nil
    }

    func testMaterializesPlainTextAsManagedTxt() throws {
        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }
        pb.clearContents()
        pb.setString("Hello shelf paste", forType: .string)

        let result = try materializer.materialize(from: pb, shelfID: ShelfID())
        XCTAssertEqual(result.drafts.count, 1)
        let draft = try XCTUnwrap(result.drafts.first)
        XCTAssertEqual(draft.kind, .text)
        XCTAssertNotNil(draft.managedTemporaryFileID)
        XCTAssertTrue(draft.displayName.hasSuffix(".txt"))
        XCTAssertTrue(draft.fileURL!.path.hasPrefix(tempRoot.path))
        let body = try String(contentsOf: draft.fileURL!, encoding: .utf8)
        XCTAssertEqual(body, "Hello shelf paste")
        XCTAssertEqual(result.newlyCreatedTemporaryFileIDs, [draft.managedTemporaryFileID!])
        XCTAssertTrue(store.record(for: draft.managedTemporaryFileID!)!.activeShelfReferences.isEmpty)
    }

    func testMaterializesPNGImage() throws {
        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }
        pb.clearContents()
        // 1x1 PNG
        let png = Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        )!
        pb.setData(png, forType: .png)

        let result = try materializer.materialize(from: pb, shelfID: ShelfID())
        XCTAssertEqual(result.drafts.count, 1)
        XCTAssertEqual(result.drafts[0].kind, .image)
        XCTAssertEqual(result.drafts[0].displayName, "Image.png")
        XCTAssertNotNil(result.drafts[0].managedTemporaryFileID)
    }

    func testMaterializesFileURLWithoutCopying() throws {
        // Place outside managed root so it is treated as an external file reference.
        let externalRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("DropsExternal-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: externalRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: externalRoot) }
        let external = externalRoot.appendingPathComponent("external.txt")
        try Data("keep".utf8).write(to: external)

        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }
        pb.clearContents()
        pb.writeObjects([external as NSURL])

        let result = try materializer.materialize(from: pb, shelfID: ShelfID())
        XCTAssertEqual(result.drafts.count, 1)
        XCTAssertEqual(result.drafts[0].kind, .file)
        XCTAssertNil(result.drafts[0].managedTemporaryFileID)
        XCTAssertEqual(result.drafts[0].fileURL?.standardizedFileURL, external.standardizedFileURL)
    }

    func testMaterializesWebLink() throws {
        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }
        pb.clearContents()
        let url = URL(string: "https://example.com/path")!
        pb.setString(url.absoluteString, forType: .URL)

        let result = try materializer.materialize(from: pb, shelfID: ShelfID())
        XCTAssertEqual(result.drafts.count, 1)
        XCTAssertEqual(result.drafts[0].kind, .link)
        XCTAssertEqual(result.drafts[0].linkURL, url)
        XCTAssertNil(result.drafts[0].managedTemporaryFileID)
    }

    func testPrefersRTFOverSynthesizedPlainTextAndMaterializesPDF() throws {
        let rtf = try NSAttributedString(string: "rich").data(
            from: NSRange(location: 0, length: 4),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )

        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }
        pb.clearContents()
        // AppKit synthesizes utf8-plain-text alongside RTF; keep explicit RTF (REV-S2-008).
        let rtfItem = NSPasteboardItem()
        rtfItem.setData(rtf, forType: .rtf)
        pb.writeObjects([rtfItem])
        let rtfResult = try materializer.materialize(from: pb, shelfID: ShelfID())
        XCTAssertEqual(rtfResult.drafts.first?.kind, .rtf)
        XCTAssertTrue(rtfResult.drafts.first?.displayName.hasSuffix(".rtf") ?? false)

        let pb2 = NSPasteboard.withUniqueName()
        defer { pb2.releaseGlobally() }
        pb2.clearContents()
        let pdfItem = NSPasteboardItem()
        let pdf = Data("%PDF-1.4\n1 0 obj<<>>endobj\ntrailer<<>>\n%%EOF\n".utf8)
        pdfItem.setData(pdf, forType: .pdf)
        pb2.writeObjects([pdfItem])
        let pdfResult = try materializer.materialize(from: pb2, shelfID: ShelfID())
        XCTAssertEqual(pdfResult.drafts.first?.kind, .pdf)
        XCTAssertEqual(pdfResult.drafts.first?.displayName, "Document.pdf")
    }

    func testFileURLWinsOverImagePreviewOnSameItem() throws {
        let externalRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("DropsMixed-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: externalRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: externalRoot) }
        let file = externalRoot.appendingPathComponent("photo.png")
        try Data("png-bytes".utf8).write(to: file)

        let item = NSPasteboardItem()
        item.setString(file.absoluteString, forType: .fileURL)
        item.setData(Data("fake-tiff".utf8), forType: .tiff)

        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }
        pb.clearContents()
        pb.writeObjects([item])

        let result = try materializer.materialize(from: pb, shelfID: ShelfID())
        XCTAssertEqual(result.drafts.count, 1)
        XCTAssertEqual(result.drafts[0].kind, .file)
        XCTAssertNil(result.drafts[0].managedTemporaryFileID)
        XCTAssertEqual(result.drafts[0].fileURL?.standardizedFileURL, file.standardizedFileURL)
        XCTAssertTrue(result.newlyCreatedTemporaryFileIDs.isEmpty)
    }

    func testManagedPasteboardTypeRestoresManagedIdentity() throws {
        let (url, record) = try store.createTemporaryFile(
            named: "note.txt",
            data: Data("shared".utf8),
            referencedBy: nil
        )

        let item = NSPasteboardItem()
        item.setString(url.absoluteString, forType: .fileURL)
        item.setString(record.id.uuidString, forType: PasteboardMaterializer.managedTemporaryFileType)

        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }
        pb.clearContents()
        pb.writeObjects([item])

        let result = try materializer.materialize(from: pb, shelfID: ShelfID())
        XCTAssertEqual(result.drafts.count, 1)
        XCTAssertEqual(result.drafts[0].managedTemporaryFileID, record.id)
        XCTAssertTrue(result.newlyCreatedTemporaryFileIDs.isEmpty)
    }

    func testDuplicateNamesInSamePasteGetSuffix() throws {
        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }
        pb.clearContents()
        let item1 = NSPasteboardItem()
        item1.setData(Data("a".utf8), forType: .png)
        let item2 = NSPasteboardItem()
        item2.setData(Data("b".utf8), forType: .png)
        pb.writeObjects([item1, item2])

        let result = try materializer.materialize(from: pb, shelfID: ShelfID())
        XCTAssertEqual(result.drafts.count, 2)
        XCTAssertEqual(result.drafts[0].displayName, "Image.png")
        XCTAssertEqual(result.drafts[1].displayName, "Image 2.png")
    }
}
