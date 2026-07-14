import Foundation

struct ShelfID: Hashable, Codable, Sendable {
    let rawValue: UUID

    init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

enum DeletionState: String, Codable, Sendable {
    case active
    case pendingDeletion
    case deleted
}

struct TemporaryFileRecord: Codable, Sendable, Equatable {
    let id: UUID
    let relativePath: String
    let createdAt: Date
    var expiresAt: Date
    var activeShelfReferences: Set<ShelfID>
    var deletionState: DeletionState
}

struct RetentionPolicy: Equatable, Sendable {
    static let defaultDays = 30
    static let maximumDays = 120

    var days: Int

    init(days: Int = RetentionPolicy.defaultDays) throws {
        guard days > 0, days <= RetentionPolicy.maximumDays else {
            throw ManagedTemporaryFileStoreError.invalidRetentionDays(days)
        }
        self.days = days
    }
}

enum ManagedTemporaryFileStoreError: Error, Equatable, LocalizedError {
    case invalidRetentionDays(Int)
    case pathEscapesManagedRoot(URL)
    case symlinkEscapeDetected(URL)
    case notManagedFile(URL)
    case stillReferenced(UUID)
    case deleteFailed(URL, String)

    var errorDescription: String? {
        switch self {
        case .invalidRetentionDays(let days):
            return "Retention days must be 1...120, got \(days)."
        case .pathEscapesManagedRoot(let url):
            return "Refusing to delete path outside managed root: \(url.path)"
        case .symlinkEscapeDetected(let url):
            return "Refusing to follow symlink escape: \(url.path)"
        case .notManagedFile(let url):
            return "Path is not a managed temporary file: \(url.path)"
        case .stillReferenced(let id):
            return "Temporary file \(id.uuidString) is still referenced by a shelf."
        case .deleteFailed(let url, let message):
            return "Failed to delete \(url.path): \(message)"
        }
    }
}
