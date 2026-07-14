import Foundation

/// Runs startup and daily cleanup against managed temporary files.
final class RetentionScheduler {
    private let temporaryStore: ManagedTemporaryFileStore
    private var timer: Timer?

    init(temporaryStore: ManagedTemporaryFileStore) {
        self.temporaryStore = temporaryStore
    }

    func start() {
        stop()
        runCleanup(reason: "startup")
        // Daily check while the app stays open.
        timer = Timer.scheduledTimer(withTimeInterval: 24 * 60 * 60, repeats: true) { [weak self] _ in
            self?.runCleanup(reason: "daily")
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    @discardableResult
    func runCleanup(reason: String) -> [UUID] {
        do {
            let deleted = try temporaryStore.cleanupExpired()
            if !deleted.isEmpty {
                NSLog("[Retention] %@ cleanup deleted %d file(s)", reason, deleted.count)
            }
            return deleted
        } catch {
            NSLog("[Retention] %@ cleanup failed: %@", reason, "\(error)")
            return []
        }
    }

    @discardableResult
    func cleanupNow() throws -> (deleted: [UUID], skippedReferenced: Int) {
        try temporaryStore.cleanupNow()
    }
}
