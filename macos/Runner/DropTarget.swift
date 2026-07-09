import AppKit
import FlutterMacOS
import Foundation

class DropTarget: NSView {

    let label: String
    private let channel: FlutterMethodChannel

    init(frame: NSRect, label: String, channel: FlutterMethodChannel) {
        self.label = label
        self.channel = channel
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let position = sender.draggingLocation
        channel.invokeMethod("dragEnter", arguments: [label, position.x, position.y])
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        channel.invokeMethod("dragExited", arguments: label)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let position = sender.draggingLocation
        channel.invokeMethod("dragUpdated", arguments: [label, position.x, position.y])
        return .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let paths = Self.materializePaths(from: sender.draggingPasteboard)

        if !paths.isEmpty {
            channel.invokeMethod("dragPerform", arguments: [label, paths])
            return true
        }

        return false
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        channel.invokeMethod("dragConclude", arguments: nil)
    }

    // MARK: - Pasteboard materialization
    //
    // Every dropped/pasted item that doesn't already have a file on disk is
    // materialized under `FileManager.default.temporaryDirectory`. When App
    // Sandbox is actually in effect, that API resolves to this app's own
    // container tmp dir (e.g. `~/Library/Containers/<bundle-id>/Data/tmp/`),
    // which is isolated from other apps and cleaned up together with the
    // container. Each drop/paste gets its own UUID-named sub-directory so the
    // files it contains can use human-readable names instead of encoding a
    // UUID into the file name itself.

    /// Reads items from any pasteboard (drag or general clipboard) and returns
    /// file paths / URL strings suitable for the shelf.
    static func materializePaths(from pasteboard: NSPasteboard) -> [String] {
        var paths: [String] = []
        let dropDirectory = makeDropDirectory()

        for item in pasteboard.pasteboardItems ?? [] {
            if let imageData = item.data(forType: .tiff) {
                let path = saveDataToTemp(data: imageData, directory: dropDirectory, fileName: "图片.tiff")
                if !path.isEmpty { paths.append(path) }
                NSLog("Saved TIFF image: \(path)")
            } else if let imageData = item.data(forType: .png) {
                let path = saveDataToTemp(data: imageData, directory: dropDirectory, fileName: "图片.png")
                if !path.isEmpty { paths.append(path) }
                NSLog("Saved PNG image: \(path)")
            } else if let urlString = item.string(forType: .fileURL),
                let url = URL(string: urlString)
            {
                paths.append(url.standardized.path)
                NSLog("Added file URL path: \(url.standardized.path)")
            } else if let urlString = item.string(forType: .URL), let url = URL(string: urlString) {
                paths.append(url.absoluteString)
                NSLog("Added URL path: \(url.absoluteString)")
            } else if let string = item.string(forType: .string) {
                // Prefer plain text over HTML/RTF — many apps put both on the
                // pasteboard (e.g. browsers, Codex), and users usually want txt.
                let path = saveStringToTemp(string: string, directory: dropDirectory, fileName: "文字档.txt")
                if !path.isEmpty { paths.append(path) }
                NSLog("Saved string: \(path)")
            } else if let rtfData = item.data(forType: .rtf) {
                let path = saveDataToTemp(data: rtfData, directory: dropDirectory, fileName: "富文本.rtf")
                if !path.isEmpty { paths.append(path) }
                NSLog("Saved RTF data: \(path)")
            } else if let rtfdData = item.data(forType: .rtfd) {
                let path = saveDataToTemp(data: rtfdData, directory: dropDirectory, fileName: "富文本.rtfd")
                if !path.isEmpty { paths.append(path) }
                NSLog("Saved RTFD data: \(path)")
            } else if let htmlData = item.data(forType: .html) {
                let path = saveDataToTemp(data: htmlData, directory: dropDirectory, fileName: "网页.html")
                if !path.isEmpty { paths.append(path) }
                NSLog("Saved HTML data: \(path)")
            } else if let pdfData = item.data(forType: .pdf) {
                let path = saveDataToTemp(data: pdfData, directory: dropDirectory, fileName: "文档.pdf")
                if !path.isEmpty { paths.append(path) }
                NSLog("Saved PDF data: \(path)")
            } else if let tabularText = item.string(forType: .tabularText) {
                let path = saveStringToTemp(
                    string: tabularText, directory: dropDirectory, fileName: "表格.txt")
                if !path.isEmpty { paths.append(path) }
                NSLog("Saved tabular text: \(path)")
            } else if let soundData = item.data(forType: .sound) {
                let path = saveDataToTemp(data: soundData, directory: dropDirectory, fileName: "声音.aiff")
                if !path.isEmpty { paths.append(path) }
                NSLog("Saved sound data: \(path)")
            } else if let fileContents = item.data(forType: .fileContents) {
                let path = saveDataToTemp(
                    data: fileContents, directory: dropDirectory, fileName: "文件.dat")
                if !path.isEmpty { paths.append(path) }
                NSLog("Saved file contents: \(path)")
            } else {
                NSLog("Unhandled pasteboard item type")
            }
        }

        return paths
    }

    /// Creates (and returns) a fresh sub-directory under the temp root to
    /// hold every file produced by a single drag/drop or paste operation.
    private static func makeDropDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
        } catch {
            NSLog("Error creating drop directory: \(error)")
        }
        return directory
    }

    /// Resolves a collision-free destination URL for `fileName` inside
    /// `directory`, appending a numeric suffix if needed (e.g. when a single
    /// drop contains more than one image).
    private static func resolveDestination(directory: URL, fileName: String) -> URL {
        let fileURL = directory.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return fileURL
        }

        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        var index = 2
        while true {
            let candidateName = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            let candidateURL = directory.appendingPathComponent(candidateName)
            if !FileManager.default.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
            index += 1
        }
    }

    private static func saveDataToTemp(data: Data, directory: URL, fileName: String) -> String {
        let fileURL = resolveDestination(directory: directory, fileName: fileName)

        do {
            try data.write(to: fileURL)
            return fileURL.path
        } catch {
            NSLog("Error saving data: \(error)")
            return ""
        }
    }

    private static func saveStringToTemp(string: String, directory: URL, fileName: String) -> String {
        let fileURL = resolveDestination(directory: directory, fileName: fileName)

        do {
            try string.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL.standardized.path
        } catch {
            NSLog("Error saving string: \(error)")
            return ""
        }
    }

    private static func saveColorToTemp(color: NSColor, directory: URL) -> String {
        let colorString =
            "R: \(color.redComponent), G: \(color.greenComponent), B: \(color.blueComponent), A: \(color.alphaComponent)"
        return saveStringToTemp(string: colorString, directory: directory, fileName: "颜色.txt")
    }

    private static func saveFontToTemp(font: NSFont, directory: URL) -> String {
        let fontString = "Font Name: \(font.fontName), Size: \(font.pointSize)"
        return saveStringToTemp(string: fontString, directory: directory, fileName: "字体.txt")
    }
}
