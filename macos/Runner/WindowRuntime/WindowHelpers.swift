import AppKit
import FlutterMacOS
import Foundation

class DragSource: NSView, NSDraggingSource {
  private let channel: FlutterMethodChannel
  var session: NSDraggingSession?
  var dragData: [String: Any] = [:]

  init(channel: FlutterMethodChannel) {
    self.channel = channel
    super.init(frame: .zero)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func draggingSession(
    _ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext
  ) -> NSDragOperation {
    self.session = session
    return [.copy, .move]
  }

  func draggingSession(
    _ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation
  ) {
    NSLog("Drag ended at \(screenPoint)")
    channel.invokeMethod("draggingSessionEnded", arguments: operation.rawValue)
    self.session = nil
  }

  func setDragData(_ data: [String: Any]) {
    self.dragData = data
  }
}

extension DragSource: NSPasteboardItemDataProvider {
  func pasteboard(
    _ pasteboard: NSPasteboard?, item: NSPasteboardItem,
    provideDataForType type: NSPasteboard.PasteboardType
  ) {
    if type == .fileURL,
      let fileURLs = dragData["fileURLs"] as? [String],
      let index = dragData["currentIndex"] as? Int,
      index < fileURLs.count
    {
      let fileURL = fileURLs[index]
      let url = NSURL(fileURLWithPath: fileURL)
      item.setData(url.dataRepresentation, forType: type)
      dragData["currentIndex"] = index + 1
    }
  }
}

extension NSImage {
  func rotated(by angle: CGFloat, opacity: CGFloat) -> NSImage {
    let rotatedImage = NSImage(size: self.size, flipped: false) { rect in
      let context = NSGraphicsContext.current
      context?.saveGraphicsState()
      let transform = NSAffineTransform()
      transform.translateX(by: rect.width / 2, yBy: rect.height / 2)
      transform.rotate(byDegrees: angle)
      transform.translateX(by: -rect.width / 2, yBy: -rect.height / 2)
      transform.concat()
      self.draw(in: rect, from: .zero, operation: .sourceOver, fraction: opacity)
      context?.restoreGraphicsState()
      return true
    }
    return rotatedImage
  }
}

class ShareSuccessDelegate: NSObject, NSSharingServicePickerDelegate {
  private var result: FlutterResult
  private var keepSelf: (() -> Void)?

  init(result: @escaping FlutterResult) {
    self.result = result
  }

  public func keep() -> Self {
    self.keepSelf = { _ = self }
    return self
  }

  public func sharingServicePicker(
    _ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?
  ) {
    result(service != nil ? service!.title : "")
    self.keepSelf = nil
  }
}

class ProcessHandler {
  private struct ProcessRecord {
    let process: Process
    let outputPipe: Pipe
    let errorPipe: Pipe
  }

  private let channel: FlutterMethodChannel
  private var tasks: [String: ProcessRecord] = [:]
  private var isDisposed = false
  private let lock = NSLock()

  init(channel: FlutterMethodChannel) {
    self.channel = channel
  }

  func startProcess(command: String, arguments: [String], result: @escaping FlutterResult) {
    let taskId = UUID().uuidString
    let process = Process()
    let outputPipe = Pipe()
    let errorPipe = Pipe()

    let fullCommand = ([command] + arguments).joined(separator: " ")
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = ["-l", "-c", fullCommand]
    process.standardOutput = outputPipe
    process.standardError = errorPipe

    var collectedOutput = Data()
    var collectedError = Data()

    outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
      let data = handle.availableData
      if !data.isEmpty {
        collectedOutput.append(data)
        if let output = String(data: data, encoding: .utf8) {
          DispatchQueue.main.async {
            guard let self, !self.isDisposed else { return }
            self.channel.invokeMethod("cliOutput", arguments: output)
          }
        }
      }
    }

    errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
      let data = handle.availableData
      if !data.isEmpty {
        collectedError.append(data)
        if let error = String(data: data, encoding: .utf8) {
          DispatchQueue.main.async {
            guard let self, !self.isDisposed else { return }
            self.channel.invokeMethod("cliError", arguments: error)
          }
        }
      }
    }

    process.terminationHandler = { [weak self] process in
      outputPipe.fileHandleForReading.readabilityHandler = nil
      errorPipe.fileHandleForReading.readabilityHandler = nil
      DispatchQueue.main.async {
        self?.removeTask(taskId)
        // Always complete the Flutter result so Dart await does not hang,
        // even if the window/runtime was disposed mid-flight.
        result([
          "exitCode": process.terminationStatus,
          "output": String(data: collectedOutput, encoding: .utf8) ?? "",
          "error": String(data: collectedError, encoding: .utf8) ?? "",
          "taskId": taskId,
        ])
      }
    }

    do {
      try process.run()
    } catch {
      outputPipe.fileHandleForReading.readabilityHandler = nil
      errorPipe.fileHandleForReading.readabilityHandler = nil
      result(
        FlutterError(
          code: "PROCESS_START_FAILED",
          message: "Failed to start process: \(error.localizedDescription)",
          details: nil))
      return
    }

    let pgid = process.processIdentifier
    _ = setpgid(pgid, pgid)

    lock.lock()
    tasks[taskId] = ProcessRecord(
      process: process, outputPipe: outputPipe, errorPipe: errorPipe)
    lock.unlock()
  }

  func cancelProcess(taskId: String? = nil) {
    let records: [ProcessRecord]
    lock.lock()
    if let taskId {
      if let record = tasks.removeValue(forKey: taskId) {
        records = [record]
      } else {
        records = []
      }
    } else {
      records = Array(tasks.values)
      tasks.removeAll()
    }
    lock.unlock()

    for record in records {
      terminate(record)
    }
  }

  func cleanup() {
    isDisposed = true
    cancelProcess(taskId: nil)
  }

  func isProcessRunning() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return tasks.values.contains { $0.process.isRunning }
  }

  private func removeTask(_ taskId: String) {
    lock.lock()
    tasks.removeValue(forKey: taskId)
    lock.unlock()
  }

  private func terminate(_ record: ProcessRecord) {
    let pgid = record.process.processIdentifier
    _ = killpg(pgid, SIGKILL)
    if record.process.isRunning {
      record.process.terminate()
    }
    record.outputPipe.fileHandleForReading.readabilityHandler = nil
    record.errorPipe.fileHandleForReading.readabilityHandler = nil
  }
}
