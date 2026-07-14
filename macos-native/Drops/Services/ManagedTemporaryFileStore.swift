import Foundation

/// Owns Drops-managed temporary content under Application Support and enforces safe deletion bounds.
final class ManagedTemporaryFileStore: @unchecked Sendable {
    private let fileManager: FileManager
    private let rootURL: URL
    private let metadataURL: URL
    private let lock = NSLock()
    private var records: [UUID: TemporaryFileRecord] = [:]
    private var retentionPolicy: RetentionPolicy

    var managedRootURL: URL { rootURL }

    init(
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "click.shakepin.macos",
        fileManager: FileManager = .default,
        retentionDays: Int = RetentionPolicy.defaultDays,
        rootURL: URL? = nil
    ) throws {
        self.fileManager = fileManager
        self.retentionPolicy = try RetentionPolicy(days: retentionDays)

        if let rootURL {
            self.rootURL = rootURL
        } else {
            let appSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            self.rootURL = appSupport
                .appendingPathComponent(bundleIdentifier, isDirectory: true)
                .appendingPathComponent("TemporaryContent", isDirectory: true)
        }

        self.metadataURL = self.rootURL.appendingPathComponent("metadata.json", isDirectory: false)
        try fileManager.createDirectory(at: self.rootURL, withIntermediateDirectories: true)
        try loadMetadataIfPresent()
    }

    /// Creates a managed temporary file and returns its absolute URL plus record.
    @discardableResult
    func createTemporaryFile(
        named fileName: String,
        data: Data,
        referencedBy shelfID: ShelfID,
        now: Date = Date()
    ) throws -> (url: URL, record: TemporaryFileRecord) {
        lock.lock()
        defer { lock.unlock() }

        let id = UUID()
        let folder = rootURL.appendingPathComponent(id.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let relativePath = "\(id.uuidString)/\(fileName)"
        let fileURL = rootURL.appendingPathComponent(relativePath)

        try data.write(to: fileURL, options: .atomic)
        let record = TemporaryFileRecord(
            id: id,
            relativePath: relativePath,
            createdAt: now,
            expiresAt: now.addingTimeInterval(TimeInterval(retentionPolicy.days * 24 * 60 * 60)),
            activeShelfReferences: [shelfID],
            deletionState: .active
        )
        records[id] = record
        try persistMetadataLocked()
        return (fileURL, record)
    }

    func updateRetentionDays(_ days: Int, now: Date = Date()) throws {
        lock.lock()
        defer { lock.unlock() }
        retentionPolicy = try RetentionPolicy(days: days)
        let interval = TimeInterval(retentionPolicy.days * 24 * 60 * 60)
        for key in records.keys {
            guard var record = records[key] else { continue }
            record.expiresAt = record.createdAt.addingTimeInterval(interval)
            if record.expiresAt <= now, !record.activeShelfReferences.isEmpty {
                record.deletionState = .pendingDeletion
            }
            records[key] = record
        }
        try persistMetadataLocked()
    }

    func addReference(id: UUID, shelfID: ShelfID) {
        lock.lock()
        defer { lock.unlock() }
        records[id]?.activeShelfReferences.insert(shelfID)
        try? persistMetadataLocked()
    }

    func removeReference(id: UUID, shelfID: ShelfID) {
        lock.lock()
        defer { lock.unlock() }
        records[id]?.activeShelfReferences.remove(shelfID)
        try? persistMetadataLocked()
    }

    /// Automatic cleanup: only expired + unreferenced managed files.
    @discardableResult
    func cleanupExpired(now: Date = Date()) throws -> [UUID] {
        try cleanup(now: now, includeUnexpiredUnreferenced: false)
    }

    /// Manual cleanup: may delete unexpired files that have no active shelf references.
    @discardableResult
    func cleanupNow(now: Date = Date()) throws -> (deleted: [UUID], skippedReferenced: Int) {
        let deleted = try cleanup(now: now, includeUnexpiredUnreferenced: true)
        lock.lock()
        let skipped = records.values.filter { !$0.activeShelfReferences.isEmpty }.count
        lock.unlock()
        return (deleted, skipped)
    }

    /// Validates and deletes a concrete path if and only if it stays inside the managed root.
    func securelyDeleteManagedFile(at url: URL) throws {
        let validated = try validateManagedURL(url)
        do {
            try fileManager.removeItem(at: validated)
        } catch {
            throw ManagedTemporaryFileStoreError.deleteFailed(validated, error.localizedDescription)
        }
    }

    func record(for id: UUID) -> TemporaryFileRecord? {
        lock.lock()
        defer { lock.unlock() }
        return records[id]
    }

    func allRecords() -> [TemporaryFileRecord] {
        lock.lock()
        defer { lock.unlock() }
        return Array(records.values)
    }

    // MARK: - Safety

    /// Resolves symlinks and rejects any path that escapes the managed root.
    func validateManagedURL(_ url: URL) throws -> URL {
        let standardizedRoot = rootURL.standardizedFileURL
        let candidate = url.standardizedFileURL

        // Reject before resolution if the logical path already escapes.
        guard isPath(candidate.path, inside: standardizedRoot.path) else {
            throw ManagedTemporaryFileStoreError.pathEscapesManagedRoot(candidate)
        }

        let resolved = candidate.resolvingSymlinksInPath().standardizedFileURL
        guard isPath(resolved.path, inside: standardizedRoot.path) else {
            throw ManagedTemporaryFileStoreError.symlinkEscapeDetected(candidate)
        }

        // Ensure the path corresponds to a known managed relative location when under root.
        let relative = String(resolved.path.dropFirst(standardizedRoot.path.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if relative.isEmpty {
            throw ManagedTemporaryFileStoreError.notManagedFile(resolved)
        }
        return resolved
    }

    // MARK: - Private

    private func cleanup(now: Date, includeUnexpiredUnreferenced: Bool) throws -> [UUID] {
        lock.lock()
        defer { lock.unlock() }

        var deletedIDs: [UUID] = []
        for (id, record) in records {
            if !record.activeShelfReferences.isEmpty {
                if record.expiresAt <= now {
                    records[id]?.deletionState = .pendingDeletion
                }
                continue
            }

            let shouldDelete: Bool
            if includeUnexpiredUnreferenced {
                shouldDelete = true
            } else {
                shouldDelete = record.expiresAt <= now
            }
            guard shouldDelete else { continue }

            let fileURL = rootURL.appendingPathComponent(record.relativePath)
            do {
                let validated = try validateManagedURL(fileURL)
                if fileManager.fileExists(atPath: validated.path) {
                    try fileManager.removeItem(at: validated)
                }
                // Also remove the UUID folder if empty.
                let folder = validated.deletingLastPathComponent()
                if folder.path.hasPrefix(rootURL.path),
                   let contents = try? fileManager.contentsOfDirectory(atPath: folder.path),
                   contents.isEmpty {
                    try? fileManager.removeItem(at: folder)
                }
                records[id]?.deletionState = .deleted
                records.removeValue(forKey: id)
                deletedIDs.append(id)
            } catch {
                // Keep the record for retry; do not pretend success.
                NSLog("[ManagedTemporaryFileStore] delete failed for %@: %@", id.uuidString, "\(error)")
                throw error
            }
        }
        try persistMetadataLocked()
        return deletedIDs
    }

    private func isPath(_ path: String, inside root: String) -> Bool {
        let normalizedPath = (path as NSString).standardizingPath
        let normalizedRoot = (root as NSString).standardizingPath
        if normalizedPath == normalizedRoot { return false }
        return normalizedPath.hasPrefix(normalizedRoot.hasSuffix("/") ? normalizedRoot : normalizedRoot + "/")
    }

    private func loadMetadataIfPresent() throws {
        guard fileManager.fileExists(atPath: metadataURL.path) else { return }
        let data = try Data(contentsOf: metadataURL)
        let decoded = try JSONDecoder().decode([TemporaryFileRecord].self, from: data)
        records = Dictionary(uniqueKeysWithValues: decoded.map { ($0.id, $0) })
    }

    private func persistMetadataLocked() throws {
        let payload = Array(records.values)
        let data = try JSONEncoder().encode(payload)
        try data.write(to: metadataURL, options: .atomic)
    }
}
