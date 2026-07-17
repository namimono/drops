import CoreServices
import Foundation

/// Watches configured folders via FSEvents and reports newly created files/folders.
/// Only **direct children** of watched roots are collected (not deep subfolders).
/// Baseline paths present at start (or after a folder-list change) are not reported.
final class FolderWatchService {
    /// Debounce so download rename / multi-event creates coalesce into one callback.
    var debounceInterval: TimeInterval = 0.8
    /// Second sample delay to skip files that appear then vanish (sync sidecars, etc.).
    var stabilityInterval: TimeInterval = 0.35

    private let queue = DispatchQueue(label: "click.shakepin.folder-watch")
    private var stream: FSEventStreamRef?
    private var watchedRoots: [String] = []
    private var knownPaths = Set<String>()
    private var pendingPaths = Set<String>()
    private var debounceWorkItem: DispatchWorkItem?
    private var onNewFiles: (([URL]) -> Void)?

    /// Starts or restarts watching. Empty `folders` / `enabled == false` stops the stream.
    func start(folders: [String], enabled: Bool, onNewFiles: @escaping ([URL]) -> Void) {
        stop()
        self.onNewFiles = onNewFiles
        guard enabled else { return }

        let roots = folders
            .map { ($0 as NSString).standardizingPath }
            .filter { FileManager.default.fileExists(atPath: $0) }
        guard !roots.isEmpty else { return }

        watchedRoots = roots
        knownPaths = Self.snapshotPaths(in: roots)

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, numEvents, eventPaths, eventFlags, _ in
            guard let info else { return }
            let service = Unmanaged<FolderWatchService>.fromOpaque(info).takeUnretainedValue()
            let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] ?? []
            let count = Int(numEvents)
            var flags: [FSEventStreamEventFlags] = []
            flags.reserveCapacity(count)
            for index in 0..<count {
                flags.append(eventFlags[index])
            }
            service.queue.async {
                service.handleEvents(paths: Array(paths.prefix(count)), flags: flags)
            }
        }

        let pathsToWatch = roots as CFArray
        stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.25,
            FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagUseCFTypes
                    | kFSEventStreamCreateFlagFileEvents
                    | kFSEventStreamCreateFlagNoDefer
            )
        )
        guard let stream else {
            NSLog("[FolderWatch] FSEventStreamCreate failed")
            return
        }

        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            NSLog("[FolderWatch] FSEventStreamStart failed")
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
            return
        }
        NSLog("[FolderWatch] watching %d folder(s) (shallow)", roots.count)
    }

    func stop() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        pendingPaths.removeAll()
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
        watchedRoots = []
        knownPaths.removeAll()
        onNewFiles = nil
    }

    deinit {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    // MARK: - Event handling

    private func handleEvents(paths: [String], flags: [FSEventStreamEventFlags]) {
        guard !watchedRoots.isEmpty else { return }

        for (index, path) in paths.enumerated() {
            let flag = index < flags.count ? flags[index] : 0
            if Self.shouldIgnoreEvent(flags: flag) { continue }

            let standardized = (path as NSString).standardizingPath

            // Nested paths: ignore (shallow watch only).
            if Self.isUnderWatchedRoot(standardized, roots: watchedRoots),
               !Self.isDirectChild(standardized, roots: watchedRoots) {
                continue
            }
            guard Self.isDirectChild(standardized, roots: watchedRoots) else { continue }
            if Self.shouldIgnorePath(standardized) { continue }

            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: standardized, isDirectory: &isDirectory)
            if !exists {
                knownPaths.remove(standardized)
                continue
            }

            if knownPaths.insert(standardized).inserted {
                pendingPaths.insert(standardized)
            }
        }

        scheduleFlush()
    }

    private func scheduleFlush() {
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.flushPending()
        }
        debounceWorkItem = work
        queue.asyncAfter(deadline: .now() + debounceInterval, execute: work)
    }

    private func flushPending() {
        let candidates = pendingPaths
        pendingPaths.removeAll()
        guard !candidates.isEmpty else { return }

        // First pass: still present and not ignored.
        var firstPass: [(path: String, size: UInt64?, isDirectory: Bool)] = []
        for path in candidates {
            if Self.shouldIgnorePath(path) {
                knownPaths.remove(path)
                continue
            }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
                knownPaths.remove(path)
                continue
            }
            let size = isDirectory.boolValue ? nil : Self.fileSize(at: path)
            firstPass.append((path, size, isDirectory.boolValue))
        }
        guard !firstPass.isEmpty else { return }

        // Stability pass: skip items that vanish or are still being written.
        let settle = stabilityInterval
        queue.asyncAfter(deadline: .now() + settle) { [weak self] in
            guard let self else { return }
            let urls: [URL] = firstPass.compactMap { entry in
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: entry.path, isDirectory: &isDirectory) else {
                    self.knownPaths.remove(entry.path)
                    return nil
                }
                if Self.shouldIgnorePath(entry.path) {
                    self.knownPaths.remove(entry.path)
                    return nil
                }
                if !entry.isDirectory {
                    let sizeNow = Self.fileSize(at: entry.path)
                    // Still growing → wait for a later event / ignore this burst.
                    if let before = entry.size, let sizeNow, sizeNow != before {
                        self.knownPaths.remove(entry.path)
                        self.pendingPaths.insert(entry.path)
                        return nil
                    }
                }
                return URL(fileURLWithPath: entry.path, isDirectory: isDirectory.boolValue)
                    .standardizedFileURL
            }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }

            if !self.pendingPaths.isEmpty {
                self.scheduleFlush()
            }
            guard !urls.isEmpty else { return }
            let callback = self.onNewFiles
            DispatchQueue.main.async {
                callback?(urls)
            }
        }
    }

    // MARK: - Pure helpers (unit-tested)

    static func shouldIgnorePath(_ path: String) -> Bool {
        let name = (path as NSString).lastPathComponent
        if name.isEmpty { return true }
        if name.hasPrefix(".") { return true }
        if name == "Icon\r" { return true }

        let lower = name.lowercased()

        // Office / editor lock & swap files
        if lower.hasPrefix("~$") { return true }
        if lower.hasPrefix(".~") { return true }

        // Sync / launcher sidecars that appear then disappear in Downloads-like folders.
        if lower.hasPrefix("lastsync") { return true }
        if lower.contains("lastsync") { return true }
        if lower.hasPrefix("synologydrive") { return true }
        if lower == "thumbs.db" || lower == "desktop.ini" { return true }

        let ignoredSuffixes = [
            ".ds_store",
            ".crdownload",
            ".download",
            ".part",
            ".tmp",
            ".temp",
            ".partial",
            ".swp",
            ".swo",
            ".bak",
            ".metadata_never_index",
        ]
        if ignoredSuffixes.contains(where: { lower.hasSuffix($0) }) { return true }
        return false
    }

    static func shouldIgnoreEvent(flags: FSEventStreamEventFlags) -> Bool {
        let ignored =
            UInt32(kFSEventStreamEventFlagHistoryDone)
            | UInt32(kFSEventStreamEventFlagMount)
            | UInt32(kFSEventStreamEventFlagUnmount)
            | UInt32(kFSEventStreamEventFlagRootChanged)
        return flags & ignored != 0
    }

    /// True when `path` is anywhere under a watched root (not the root itself).
    static func isUnderWatchedRoot(_ path: String, roots: [String]) -> Bool {
        let standardized = (path as NSString).standardizingPath
        for root in roots {
            let rootPath = (root as NSString).standardizingPath
            if standardized == rootPath { return false }
            if standardized.hasPrefix(rootPath.hasSuffix("/") ? rootPath : rootPath + "/") {
                return true
            }
        }
        return false
    }

    /// True when `path` is a direct child of one of the watched roots.
    static func isDirectChild(_ path: String, roots: [String]) -> Bool {
        let standardized = (path as NSString).standardizingPath
        let parent = (standardized as NSString).deletingLastPathComponent
        let standardizedParent = (parent as NSString).standardizingPath
        return roots.contains { ($0 as NSString).standardizingPath == standardizedParent }
    }

    /// New **direct-child** paths among `candidates` that are not already in `known`.
    static func filterNewPaths(
        candidates: [String],
        known: Set<String>,
        roots: [String]
    ) -> (newPaths: [String], updatedKnown: Set<String>) {
        var updated = known
        var found: [String] = []
        for path in candidates {
            let standardized = (path as NSString).standardizingPath
            guard isDirectChild(standardized, roots: roots) else { continue }
            guard !shouldIgnorePath(standardized) else { continue }
            if updated.insert(standardized).inserted {
                found.append(standardized)
            }
        }
        return (found, updated)
    }

    static func snapshotPaths(in roots: [String]) -> Set<String> {
        var result = Set<String>()
        for root in roots {
            for path in enumerateDirectChildren(at: root) where !shouldIgnorePath(path) {
                result.insert(path)
            }
        }
        return result
    }

    static func enumerateDirectChildren(at root: String) -> [String] {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: root, isDirectory: &isDirectory), isDirectory.boolValue else {
            return []
        }
        guard let names = try? fm.contentsOfDirectory(atPath: root) else { return [] }
        return names.map { (root as NSString).appendingPathComponent($0) }
            .map { ($0 as NSString).standardizingPath }
    }

    private static func fileSize(at path: String) -> UInt64? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let number = attrs[.size] as? NSNumber else {
            return nil
        }
        return number.uint64Value
    }
}
