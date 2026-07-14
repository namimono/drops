import XCTest
@testable import Drops

final class ManagedTemporaryFileStoreTests: XCTestCase {
    private var tempRoot: URL!
    private var store: ManagedTemporaryFileStore!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("DropsStage0Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        store = try ManagedTemporaryFileStore(
            bundleIdentifier: "click.shakepin.macos.tests",
            retentionDays: 30,
            rootURL: tempRoot
        )
    }

    override func tearDownWithError() throws {
        if let tempRoot, FileManager.default.fileExists(atPath: tempRoot.path) {
            try FileManager.default.removeItem(at: tempRoot)
        }
        store = nil
        tempRoot = nil
    }

    func testCreateTemporaryFileInsideManagedRoot() throws {
        let shelf = ShelfID()
        let (url, record) = try store.createTemporaryFile(
            named: "note.txt",
            data: Data("hello".utf8),
            referencedBy: shelf
        )

        XCTAssertTrue(url.path.hasPrefix(tempRoot.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(record.activeShelfReferences, [shelf])
        XCTAssertEqual(store.record(for: record.id)?.deletionState, .active)
    }

    func testRejectsInvalidRetentionDays() {
        XCTAssertThrowsError(try RetentionPolicy(days: 0))
        XCTAssertThrowsError(try RetentionPolicy(days: 121))
        XCTAssertNoThrow(try RetentionPolicy(days: 120))
    }

    func testExpiredReferencedFileIsNotDeleted() throws {
        let shelf = ShelfID()
        let created = Date().addingTimeInterval(-40 * 24 * 60 * 60)
        let (url, record) = try store.createTemporaryFile(
            named: "old.txt",
            data: Data("keep".utf8),
            referencedBy: shelf,
            now: created
        )

        let deleted = try store.cleanupExpired(now: Date())
        XCTAssertTrue(deleted.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(store.record(for: record.id)?.deletionState, .pendingDeletion)
    }

    func testExpiredUnreferencedFileIsDeleted() throws {
        let shelf = ShelfID()
        let created = Date().addingTimeInterval(-40 * 24 * 60 * 60)
        let (url, record) = try store.createTemporaryFile(
            named: "stale.txt",
            data: Data("gone".utf8),
            referencedBy: shelf,
            now: created
        )
        store.removeReference(id: record.id, shelfID: shelf)

        let deleted = try store.cleanupExpired(now: Date())
        XCTAssertEqual(deleted, [record.id])
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertNil(store.record(for: record.id))
    }

    func testManualCleanupDeletesUnexpiredUnreferencedAndSkipsReferenced() throws {
        let shelfA = ShelfID()
        let shelfB = ShelfID()
        let (keptURL, kept) = try store.createTemporaryFile(
            named: "kept.txt",
            data: Data("kept".utf8),
            referencedBy: shelfA
        )
        let (freeURL, free) = try store.createTemporaryFile(
            named: "free.txt",
            data: Data("free".utf8),
            referencedBy: shelfB
        )
        store.removeReference(id: free.id, shelfID: shelfB)

        let result = try store.cleanupNow(now: Date())
        XCTAssertEqual(result.deleted, [free.id])
        XCTAssertEqual(result.skippedReferenced, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: keptURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: freeURL.path))
        XCTAssertNotNil(store.record(for: kept.id))
    }

    func testExternalPathCannotBeDeleted() throws {
        let external = FileManager.default.temporaryDirectory
            .appendingPathComponent("drops-external-\(UUID().uuidString).txt")
        try Data("external".utf8).write(to: external)
        defer { try? FileManager.default.removeItem(at: external) }

        XCTAssertThrowsError(try store.securelyDeleteManagedFile(at: external)) { error in
            guard case ManagedTemporaryFileStoreError.pathEscapesManagedRoot = error else {
                return XCTFail("Expected pathEscapesManagedRoot, got \(error)")
            }
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: external.path))
    }

    func testSymlinkEscapeIsRejected() throws {
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("drops-secret-\(UUID().uuidString).txt")
        try Data("secret".utf8).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }

        let link = tempRoot.appendingPathComponent("escape-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)

        XCTAssertThrowsError(try store.securelyDeleteManagedFile(at: link)) { error in
            guard case ManagedTemporaryFileStoreError.symlinkEscapeDetected = error else {
                return XCTFail("Expected symlinkEscapeDetected, got \(error)")
            }
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }

    func testUpdatingRetentionRecalculatesExpiry() throws {
        let shelf = ShelfID()
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let (_, record) = try store.createTemporaryFile(
            named: "recalc.txt",
            data: Data("x".utf8),
            referencedBy: shelf,
            now: created
        )
        try store.updateRetentionDays(10, now: created)
        let updated = try XCTUnwrap(store.record(for: record.id))
        XCTAssertEqual(
            updated.expiresAt.timeIntervalSince1970,
            created.addingTimeInterval(10 * 24 * 60 * 60).timeIntervalSince1970,
            accuracy: 0.001
        )
    }
}
