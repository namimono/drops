import Foundation

/// Appends diagnostic lines to a file under Application Support for the Show Logs menu entry.
final class AppLogStore {
    private let fileURL: URL
    private let queue = DispatchQueue(label: "click.shakepin.macos.applog")

    var logFileURL: URL { fileURL }

    init(
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "click.shakepin.macos",
        fileManager: FileManager = .default
    ) throws {
        let support = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let folder = support
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appendingPathComponent("drops.log", isDirectory: false)
        if !fileManager.fileExists(atPath: fileURL.path) {
            fileManager.createFile(atPath: fileURL.path, contents: nil)
        }
    }

    func append(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        queue.async { [fileURL] in
            guard let data = line.data(using: .utf8),
                  let handle = try? FileHandle(forWritingTo: fileURL) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        }
    }
}
