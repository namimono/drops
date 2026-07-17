import XCTest
@testable import Drops

final class FolderWatchServiceTests: XCTestCase {
    func testShouldIgnoreHiddenIncompleteAndSyncSidecars() {
        XCTAssertTrue(FolderWatchService.shouldIgnorePath("/tmp/.hidden"))
        XCTAssertTrue(FolderWatchService.shouldIgnorePath("/tmp/.DS_Store"))
        XCTAssertTrue(FolderWatchService.shouldIgnorePath("/tmp/report.pdf.crdownload"))
        XCTAssertTrue(FolderWatchService.shouldIgnorePath("/tmp/video.part"))
        XCTAssertTrue(FolderWatchService.shouldIgnorePath("/tmp/lastsyncafterlaunch.plist"))
        XCTAssertTrue(FolderWatchService.shouldIgnorePath("/tmp/LastSyncState.bin"))
        XCTAssertTrue(FolderWatchService.shouldIgnorePath("/tmp/~$Document.docx"))
        XCTAssertFalse(FolderWatchService.shouldIgnorePath("/tmp/report.pdf"))
        XCTAssertFalse(FolderWatchService.shouldIgnorePath("/tmp/Notes"))
        XCTAssertFalse(FolderWatchService.shouldIgnorePath("/tmp/settings.plist"))
    }

    func testIsUnderWatchedRootExcludesRootItself() {
        let roots = ["/Users/me/Downloads"]
        XCTAssertFalse(FolderWatchService.isUnderWatchedRoot("/Users/me/Downloads", roots: roots))
        XCTAssertTrue(
            FolderWatchService.isUnderWatchedRoot("/Users/me/Downloads/a.pdf", roots: roots)
        )
        XCTAssertTrue(
            FolderWatchService.isUnderWatchedRoot("/Users/me/Downloads/sub/b.txt", roots: roots)
        )
        XCTAssertFalse(
            FolderWatchService.isUnderWatchedRoot("/Users/me/Documents/a.pdf", roots: roots)
        )
    }

    func testIsDirectChildOnly() {
        let roots = ["/Users/me/Downloads"]
        XCTAssertTrue(FolderWatchService.isDirectChild("/Users/me/Downloads/a.pdf", roots: roots))
        XCTAssertFalse(
            FolderWatchService.isDirectChild("/Users/me/Downloads/sub/b.txt", roots: roots)
        )
        XCTAssertFalse(FolderWatchService.isDirectChild("/Users/me/Downloads", roots: roots))
    }

    func testFilterNewPathsSkipsKnownIgnoredAndNested() {
        let roots = ["/tmp/watch-root"]
        let known: Set<String> = ["/tmp/watch-root/existing.txt"]
        let candidates = [
            "/tmp/watch-root/existing.txt",
            "/tmp/watch-root/new.txt",
            "/tmp/watch-root/.DS_Store",
            "/tmp/watch-root/lastsyncafterlaunch.plist",
            "/tmp/watch-root/sub/nested.txt",
            "/tmp/other/new.txt",
        ]
        let result = FolderWatchService.filterNewPaths(
            candidates: candidates,
            known: known,
            roots: roots
        )
        XCTAssertEqual(result.newPaths, ["/tmp/watch-root/new.txt"])
        XCTAssertTrue(result.updatedKnown.contains("/tmp/watch-root/new.txt"))
        XCTAssertTrue(result.updatedKnown.contains("/tmp/watch-root/existing.txt"))
        XCTAssertFalse(result.updatedKnown.contains("/tmp/watch-root/sub/nested.txt"))
    }

    func testSnapshotAndLiveDetectionInTempDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("drops-watch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let existing = root.appendingPathComponent("seed.txt")
        try "seed".write(to: existing, atomically: true, encoding: .utf8)

        // Nested file must not be reported (shallow watch).
        let nestedDir = root.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedDir, withIntermediateDirectories: true)

        let expectation = expectation(description: "new file reported")
        expectation.assertForOverFulfill = true
        var reported: [URL] = []

        let service = FolderWatchService()
        service.debounceInterval = 0.15
        service.stabilityInterval = 0.1
        service.start(folders: [root.path], enabled: true) { urls in
            reported = urls
            expectation.fulfill()
        }

        let nested = nestedDir.appendingPathComponent("nested.txt")
        try "nested".write(to: nested, atomically: true, encoding: .utf8)

        let fresh = root.appendingPathComponent("fresh.txt")
        try "fresh".write(to: fresh, atomically: true, encoding: .utf8)

        wait(for: [expectation], timeout: 4.0)
        service.stop()

        XCTAssertEqual(reported.map(\.lastPathComponent), ["fresh.txt"])
        XCTAssertFalse(reported.contains(where: { $0.lastPathComponent == "seed.txt" }))
        XCTAssertFalse(reported.contains(where: { $0.lastPathComponent == "nested.txt" }))
    }

    func testDisabledOrEmptyFoldersDoNotStart() {
        let service = FolderWatchService()
        var called = false
        service.start(folders: ["/tmp"], enabled: false) { _ in called = true }
        service.stop()
        service.start(folders: [], enabled: true) { _ in called = true }
        service.stop()
        XCTAssertFalse(called)
    }
}
