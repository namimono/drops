import AppKit
import Compression
import FlutterMacOS
import Foundation
import QuickLookUI

enum ImageFormat: Int {
  case png, jpeg, tiff, webp
}

/// Per-shelf window runtime: channels, drop, drag-out, process, paste, QL, overlays.
final class WindowRuntime: NSObject, NSViewToolTipOwner {
  let shelfId: String
  weak var window: ShelfWindow?
  let flutterViewController: FlutterViewController
  let engine: FlutterEngine

  private(set) var channel: FlutterMethodChannel!
  private var settingsChannel: FlutterMethodChannel!
  private var dropdownChannel: FlutterMethodChannel!
  private var tooltipChannel: FlutterMethodChannel!

  private var dropTargets: [DropTarget] = []
  private var externalDragCaptureTarget: DropTarget?
  private var dragSource: DragSource!
  private var processHandler: ProcessHandler!
  private var popover: NSPopover?

  private var dropdownButtons: [String: NSPopUpButton] = [:]
  private var dropdownMenu: NSMenu?
  private var tooltipTags: [String: NSView.ToolTipTag] = [:]
  private var tooltipMap: [NSView.ToolTipTag: String] = [:]

  private var iconCache = NSCache<NSString, NSImage>()
  private var iconDataCache = NSCache<NSString, NSData>()

  private(set) var isFlutterReady = false
  private var pendingDropPaths: [[String]] = []

  /// Called when native drop is accepted (before Flutter delivery).
  var onDropAccepted: (([String]) -> Void)?

  /// Called when Flutter requests closeSelf.
  var onCloseRequested: (() -> Void)?

  init(
    shelfId: String,
    engine: FlutterEngine,
    flutterViewController: FlutterViewController,
    window: ShelfWindow
  ) {
    self.shelfId = shelfId
    self.engine = engine
    self.flutterViewController = flutterViewController
    self.window = window
    super.init()
  }

  func start() {
    channel = FlutterMethodChannel(
      name: "click.shakepin.macos/drop",
      binaryMessenger: engine.binaryMessenger)
    channel.setMethodCallHandler(handleMethodCall)

    dragSource = DragSource(channel: channel)
    flutterViewController.view.addSubview(dragSource, positioned: .below, relativeTo: nil)

    processHandler = ProcessHandler(channel: channel)
    setupSettingsChannel()
    setupNativeDropdownChannel()
    setupTooltipChannel()
    // Permanent window-level drop destination is registered on ShelfWindow so
    // drops work before and after Flutter ready without an overlay that steals clicks.
  }

  private func setupSettingsChannel() {
    settingsChannel = FlutterMethodChannel(
      name: "click.shakepin.macos/settings",
      binaryMessenger: engine.binaryMessenger)
    SettingsBridge.shared.registerChannel(settingsChannel)
    settingsChannel.setMethodCallHandler { call, result in
      SettingsBridge.shared.handleMethodCall(call, result: result)
    }
  }

  func markFlutterReady() {
    isFlutterReady = true
    NSLog("[SHELF] flutterReady shelfId=%@", shelfId)
    window?.revealFlutterContent()
    flushPendingDrops()
  }

  /// Installs a temporary full-window AppKit target for the duration of an
  /// external Finder drag. Flutter's render view can otherwise consume the
  /// destination lookup before NSWindow receives it.
  func beginExternalDragCapture() {
    guard externalDragCaptureTarget == nil else { return }
    let target = DropTarget(
      frame: flutterViewController.view.bounds,
      label: "main-drop-app",
      channel: channel)
    target.autoresizingMask = [.width, .height]
    target.deliversViaCallbackOnly = true
    target.onDropAccepted = { [weak self] paths in
      self?.handleNativeDropAccepted(paths: paths, label: "main-drop-app")
    }
    target.registerForDraggedTypes([
      .fileURL, .png, .tiff, .string, .URL,
    ])
    flutterViewController.view.addSubview(target)
    externalDragCaptureTarget = target
  }

  func endExternalDragCapture() {
    externalDragCaptureTarget?.removeFromSuperview()
    externalDragCaptureTarget = nil
  }

  /// Dragging destination helpers used by ShelfWindow (permanent full-window target).
  func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    let position = sender.draggingLocation
    channel.invokeMethod(
      "dragEnter", arguments: ["main-drop-app", position.x, position.y])
    return .copy
  }

  func draggingExited(_ sender: NSDraggingInfo?) {
    channel.invokeMethod("dragExited", arguments: "main-drop-app")
  }

  func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
    .copy
  }

  @discardableResult
  func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    let paths = DropTarget.materializePaths(from: sender.draggingPasteboard)
    guard !paths.isEmpty else { return false }
    handleNativeDropAccepted(paths: paths, label: "main-drop-app")
    return true
  }

  func concludeDragOperation(_ sender: NSDraggingInfo?) {
    // Drop delivery already emits dragConclude from handleNativeDropAccepted
    // (or from flushPendingDrops after shelfReady). Avoid a duplicate conclude.
  }

  func handleNativeDropAccepted(paths: [String], label: String) {
    onDropAccepted?(paths)
    if isFlutterReady {
      // Preserve the original drop route so the matching Dart target receives
      // onDragPerform and its hover/conclude animations.
      channel.invokeMethod("dragPerform", arguments: [label, paths])
      channel.invokeMethod("dragConclude", arguments: nil)
    } else {
      pendingDropPaths.append(paths)
      NSLog("[SHELF] queued drop shelfId=%@ count=%d", shelfId, paths.count)
    }
  }

  private func flushPendingDrops() {
    guard isFlutterReady else { return }
    for paths in pendingDropPaths {
      channel.invokeMethod("dragPerform", arguments: ["main-drop-app", paths])
      channel.invokeMethod("dragConclude", arguments: nil)
    }
    pendingDropPaths.removeAll()
  }

  func deliverPaste(_ paths: [String]) {
    guard !ShelfManager.shared.shouldIgnore(shelfId: shelfId) else { return }
    channel.invokeMethod("pastePerform", arguments: paths)
  }

  func invokeMenuTag(_ tag: Int) {
    channel.invokeMethod("menuItemClicked", arguments: tag)
  }

  func dispose() {
    processHandler.cleanup()
    channel?.setMethodCallHandler(nil)
    if settingsChannel != nil {
      SettingsBridge.shared.unregisterChannel(settingsChannel)
      settingsChannel.setMethodCallHandler(nil)
    }
    dropdownChannel?.setMethodCallHandler(nil)
    tooltipChannel?.setMethodCallHandler(nil)
    for target in dropTargets {
      target.removeFromSuperview()
    }
    dropTargets.removeAll()
    endExternalDragCapture()
    dragSource?.removeFromSuperview()
    for (_, button) in dropdownButtons {
      button.removeFromSuperview()
    }
    dropdownButtons.removeAll()
  }

  // MARK: - Method channel

  private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let window else {
      result(FlutterError(code: "NO_WINDOW", message: "Window disposed", details: nil))
      return
    }

    switch call.method {
    case "shelfReady":
      markFlutterReady()
      result(nil)

    case "closeSelf":
      onCloseRequested?()
      result(nil)

    case "cleanup":
      cleanupTempFiles()
      result(nil)

    case "hide":
      window.setIsVisible(false)
      result(nil)

    case "performDragWindow":
      if let event = window.currentEvent {
        window.performDrag(with: event)
      }
      result(nil)

    case "performDragSession":
      let fileURLs = call.arguments as! [String]
      performDragSession(fileURLs: fileURLs, window: window)
      result(nil)

    case "getFileIcon":
      if let path = call.arguments as? String {
        getFileIcon(path: path, result: result)
      } else {
        result(FlutterError(code: "INVALID_ARGUMENT", message: "Path must be a string", details: nil))
      }

    case "quickLook":
      guard let paths = call.arguments as? [String], !paths.isEmpty else {
        result(
          FlutterError(
            code: "INVALID_ARGUMENT", message: "Paths must be a non-empty string array", details: nil
          ))
        return
      }
      let visible = QuickLookPreviewController.shared.toggle(paths: paths)
      result(visible)

    case "setFrame":
      if let args = call.arguments as? [CGFloat?], args.count == 5 {
        let x = args[0] ?? window.frame.origin.x
        let y = args[1] ?? window.frame.origin.y
        let width = args[2] ?? window.frame.width
        let height = args[3] ?? window.frame.height
        let animate = args[4] != 0
        let mouseLocation = NSEvent.mouseLocation
        guard
          let screen = NSScreen.screens.first(where: {
            NSMouseInRect(mouseLocation, $0.frame, false)
          })
        else {
          result(
            FlutterError(code: "NO_SCREEN", message: "Unable to determine current screen", details: nil))
          return
        }
        let screenFrame = screen.visibleFrame
        let constrainedX = max(screenFrame.minX, min(x, screenFrame.maxX - width))
        let constrainedY = max(screenFrame.minY, min(y, screenFrame.maxY - height))
        let constrainedRect = NSRect(x: constrainedX, y: constrainedY, width: width, height: height)
        if animate {
          // NSWindow's proxy animation does not reliably invoke an enclosing
          // NSAnimationContext completion. Waiting for that completion leaves
          // Dart's shelf transition permanently pending: the window grows, but
          // the detail view never replaces the stacked view. NSWindow owns this
          // animation itself, so acknowledge once it has been scheduled.
          window.setFrame(constrainedRect, display: true, animate: true)
          result(nil)
        } else {
          window.setFrame(constrainedRect, display: true)
          result(nil)
        }
      } else {
        result(
          FlutterError(
            code: "INVALID_ARGUMENT", message: "Frame must be an array of 5 numbers", details: nil))
      }

    case "setMinimumSize":
      if let args = call.arguments as? [CGFloat], args.count == 2 {
        window.minSize = NSSize(width: args[0], height: args[1])
        result(nil)
      } else {
        result(
          FlutterError(
            code: "INVALID_ARGUMENT", message: "Minimum size must be an array of 2 numbers",
            details: nil))
      }

    case "setVisible":
      guard let visible = call.arguments as? Bool else {
        result(
          FlutterError(code: "INVALID_ARGUMENT", message: "Visible must be a boolean", details: nil))
        return
      }
      setWindowVisible(visible, activate: true, window: window, result: result)

    case "setVisibleWithoutActivating":
      guard let visible = call.arguments as? Bool else {
        result(
          FlutterError(code: "INVALID_ARGUMENT", message: "Visible must be a boolean", details: nil))
        return
      }
      setWindowVisible(visible, activate: false, window: window, result: result)

    case "orderFront":
      window.orderFront(nil)
      result(nil)

    case "removeDropTarget":
      let args = call.arguments as! [Any]
      let label = args[0] as? String
      if let target = dropTargets.first(where: { $0.label == label }) {
        target.removeFromSuperview()
        dropTargets = dropTargets.filter { $0.label != label }
      }
      result(nil)

    case "setDropTarget":
      let args = call.arguments as! [Any]
      let label = args[4] as! String
      let target = dropTargets.first { $0.label == label }
      let x = args[0] as! CGFloat
      let y = args[1] as! CGFloat
      let width = args[2] as! CGFloat
      let height = args[3] as! CGFloat
      let targetRect = NSRect(
        x: x,
        y: window.frame.height - y - height,
        width: width,
        height: height)

      if let target = target {
        target.frame = targetRect
      } else {
        let newTarget = DropTarget(frame: targetRect, label: label, channel: channel)
        newTarget.onDropAccepted = { [weak self] paths in
          self?.onDropAccepted?(paths)
        }
        // A ready Flutter target uses the original dragPerform route so hover,
        // conclude and item animations all reach the matching Dart listener.
        newTarget.registerForDraggedTypes([
          NSPasteboard.PasteboardType.fileURL,
          NSPasteboard.PasteboardType.png,
          NSPasteboard.PasteboardType.tiff,
          NSPasteboard.PasteboardType.string,
          NSPasteboard.PasteboardType.URL,
        ])
        flutterViewController.view.addSubview(newTarget)
        dropTargets.append(newTarget)
      }
      result(nil)

    case "isVisible":
      result(window.isVisible)

    case "center":
      result([window.frame.midX, window.frame.midY])

    case "convertImage":
      if let args = call.arguments as? [Any], args.count == 2,
        let inputPath = args[0] as? String,
        let formatIndex = args[1] as? Int,
        let format = ImageFormat(rawValue: formatIndex)
      {
        if let outputPath = convertImage(from: inputPath, to: format) {
          result(outputPath)
        } else {
          result(
            FlutterError(
              code: "CONVERSION_FAILED", message: "Failed to convert image", details: nil))
        }
      } else {
        result(
          FlutterError(
            code: "INVALID_ARGUMENT", message: "Invalid arguments for convertImage", details: nil))
      }

    case "showPopover":
      guard let args = call.arguments as? [Any],
        let content = args[0] as? String,
        let edgeIndex = args[1] as? Int
      else {
        result(
          FlutterError(
            code: "INVALID_ARGUMENTS", message: "Invalid arguments for showPopover", details: nil))
        return
      }
      let edge: NSRectEdge =
        switch edgeIndex {
        case 0: .minX
        case 1: .maxX
        case 2: .maxY
        case 3: .minY
        default: .minX
        }
      showPopover(content: content, edge: edge, window: window)
      result(nil)

    case "hidePopover":
      popover?.close()
      result(nil)

    case "getAppVersion":
      result(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")

    case "shareXFiles":
      if let fileURLs = call.arguments as? [String] {
        shareXFiles(fileURLs: fileURLs, window: window, result: result)
      } else {
        result(
          FlutterError(
            code: "INVALID_ARGUMENT", message: "Invalid arguments for shareXFiles", details: nil))
      }

    case "startProcess":
      if let args = call.arguments as? [String: Any],
        let command = args["command"] as? String,
        let arguments = args["arguments"] as? [String]
      {
        processHandler.startProcess(command: command, arguments: arguments, result: result)
      } else {
        result(
          FlutterError(
            code: "INVALID_ARGUMENT",
            message: "Invalid arguments for startProcess",
            details: nil))
      }

    case "startDragging":
      DispatchQueue.main.async {
        if let event = window.currentEvent {
          window.performDrag(with: event)
        }
      }
      result(nil)

    case "cancelProcess":
      if let taskId = call.arguments as? String {
        processHandler.cancelProcess(taskId: taskId)
      } else {
        processHandler.cancelProcess(taskId: nil)
      }
      result(true)

    case "isProcessRunning":
      result(processHandler.isProcessRunning())

    case "setShiftKeyCheckEnabled":
      if let enabled = call.arguments as? Bool {
        GlobalInputCoordinator.shared.shiftKeyCheckEnabled = enabled
        result(nil)
      } else {
        result(
          FlutterError(code: "INVALID_ARGUMENT", message: "Argument must be a boolean", details: nil)
        )
      }

    case "writeToClipboard":
      if let text = call.arguments as? String {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        result(true)
      } else {
        result(
          FlutterError(code: "INVALID_ARGUMENT", message: "Text must be a string", details: nil))
      }

    case "readFromPasteboard":
      result(DropTarget.materializePaths(from: .general))

    case "showNativeAlert":
      showNativeAlert(call: call, window: window, result: result)

    // Host-only methods — no-op / forward for shelf engines
    case "setTrayIcon", "setupMenuBar", "getGlobalHotkeyStatus":
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Helpers (ported from MainFlutterWindow)

  private func setWindowVisible(
    _ visible: Bool, activate: Bool, window: ShelfWindow, result: @escaping FlutterResult
  ) {
    if visible {
      window.alphaValue = 0.0
      window.setIsVisible(true)
      if activate {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
      } else {
        // Shake shelves must not steal Finder drag-source focus.
        window.orderFrontRegardless()
      }
      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.16
        window.animator().alphaValue = 1.0
      } completionHandler: {
        result(nil)
      }
    } else {
      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.16
        window.animator().alphaValue = 0.0
      } completionHandler: {
        window.orderOut(nil)
        window.alphaValue = 1.0
        result(nil)
      }
    }
  }

  private func setupNativeDropdownChannel() {
    dropdownChannel = FlutterMethodChannel(
      name: "com.damywise.flutter_macos_native_dropdown/channel",
      binaryMessenger: engine.binaryMessenger)
    dropdownChannel.setMethodCallHandler { [weak self] call, result in
      self?.handleNativeDropdownMethodCall(call, result: result)
    }
  }

  private func handleNativeDropdownMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "updateNativeDropdown",
      let args = call.arguments as? [String: Any],
      let items = args["items"] as? [[String: Any]],
      let x = args["x"] as? CGFloat,
      let y = args["y"] as? CGFloat,
      let width = args["width"] as? CGFloat,
      let height = args["height"] as? CGFloat,
      let selectedIndex = args["selectedIndex"] as? Int,
      let dropdownId = args["dropdownId"] as? String,
      let enabled = args["enabled"] as? Bool,
      let remove = args["remove"] as? Bool,
      let pullsDown = args["pullsDown"] as? Bool
    else {
      result(
        FlutterError(
          code: "INVALID_ARGUMENTS", message: "Invalid arguments for updateNativeDropdown",
          details: nil))
      return
    }

    if remove {
      if let button = dropdownButtons[dropdownId] {
        button.removeFromSuperview()
        dropdownButtons.removeValue(forKey: dropdownId)
      }
      result(nil)
      return
    }

    let button: NSPopUpButton
    if let existingButton = dropdownButtons[dropdownId] {
      button = existingButton
    } else {
      button = NSPopUpButton.init(popUpMenu: dropdownMenu ?? NSMenu(), target: nil, action: nil)
      button.bezelStyle = .rounded
      button.target = self
      button.action = #selector(handlePopUpButtonAction(_:))
      button.isBordered = false
      button.alphaValue = 0
      flutterViewController.view.addSubview(button)
      dropdownButtons[dropdownId] = button
    }

    let flutterViewHeight = flutterViewController.view.frame.height
    button.frame = NSRect(x: x, y: flutterViewHeight - y - height, width: width, height: height)
    button.menu!.autoenablesItems = false
    if pullsDown { button.pullsDown = true }
    button.removeAllItems()
    for item in items {
      guard let title = item["title"] as? String, let itemEnabled = item["enabled"] as? Bool else {
        continue
      }
      button.menu?.addItem(withTitle: title, action: nil, keyEquivalent: "")
      button.menu?.items.last?.isEnabled = itemEnabled
    }
    if selectedIndex >= 0 && selectedIndex < items.count {
      button.selectItem(at: selectedIndex)
    }
    button.isEnabled = enabled
    result(nil)
  }

  @objc private func handlePopUpButtonAction(_ sender: NSPopUpButton) {
    guard let dropdownId = dropdownButtons.first(where: { $0.value === sender })?.key else {
      return
    }
    dropdownChannel.invokeMethod(
      "onDropdownMenuSelected",
      arguments: ["id": dropdownId, "index": sender.indexOfSelectedItem])
  }

  private func setupTooltipChannel() {
    tooltipChannel = FlutterMethodChannel(
      name: "click.shakepin.macos/tooltip",
      binaryMessenger: engine.binaryMessenger)
    tooltipChannel.setMethodCallHandler { [weak self] call, result in
      self?.handleTooltipMethodCall(call, result: result)
    }
  }

  private func handleTooltipMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "updateTooltip",
      let args = call.arguments as? [String: Any],
      let tooltipId = args["tooltipId"] as? String,
      let x = args["x"] as? CGFloat,
      let y = args["y"] as? CGFloat,
      let width = args["width"] as? CGFloat,
      let height = args["height"] as? CGFloat,
      let text = args["text"] as? String,
      let remove = args["remove"] as? Bool,
      let window
    else {
      result(
        FlutterError(
          code: "INVALID_ARGUMENTS", message: "Invalid arguments for updateTooltip", details: nil))
      return
    }

    if remove {
      if let tag = tooltipTags[tooltipId] {
        window.contentView?.removeToolTip(tag)
        tooltipTags.removeValue(forKey: tooltipId)
        tooltipMap.removeValue(forKey: tag)
      }
      result(nil)
      return
    }

    let flutterViewHeight = flutterViewController.view.frame.height
    let rect = NSRect(x: x, y: flutterViewHeight - y - height, width: width, height: height)
    if let existing = tooltipTags[tooltipId] {
      window.contentView?.removeToolTip(existing)
      tooltipMap.removeValue(forKey: existing)
    }
    if let tag = window.contentView?.addToolTip(
      rect, owner: self, userData: nil)
    {
      tooltipTags[tooltipId] = tag
      tooltipMap[tag] = text
    }
    result(nil)
  }

  func view(
    _ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint,
    userData data: UnsafeMutableRawPointer?
  ) -> String {
    tooltipMap[tag] ?? ""
  }

  private func performDragSession(fileURLs: [String], window: ShelfWindow) {
    let icons = fileURLs.map { fileURL -> NSImage in
      if let cachedIcon = iconCache.object(forKey: fileURL as NSString) {
        return cachedIcon
      }
      let icon = NSWorkspace.shared.icon(forFile: fileURL)
      iconCache.setObject(icon, forKey: fileURL as NSString)
      return icon
    }
    dragSource.setDragData(["fileURLs": fileURLs, "currentIndex": 0])
    let draggingItems = fileURLs.enumerated().map { (index, fileURL) -> NSDraggingItem in
      let pasteboardItem = NSPasteboardItem()
      pasteboardItem.setString(fileURL, forType: .string)
      pasteboardItem.setDataProvider(dragSource, forTypes: [.fileURL])
      let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
      let dragFrame = NSRect(
        x: window.mouseLocationOutsideOfEventStream.x - 25,
        y: window.mouseLocationOutsideOfEventStream.y - 25, width: 50, height: 50)
      let icon = icons[index]
      if index <= 6 {
        if index > 0 {
          let rotationAngle = CGFloat(index - 1) * 10 * (index % 2 == 0 ? 1 : -1)
          draggingItem.setDraggingFrame(
            dragFrame, contents: icon.rotated(by: rotationAngle, opacity: 1.0 - (CGFloat(index) * 0.05)))
        } else {
          draggingItem.setDraggingFrame(dragFrame, contents: icon)
        }
      } else {
        draggingItem.setDraggingFrame(
          NSRect(origin: dragFrame.origin, size: CGSize(width: 1, height: 1)), contents: nil)
      }
      return draggingItem
    }
    dragSource.beginDraggingSession(
      with: draggingItems, event: NSApp.currentEvent!, source: dragSource)
  }

  private func getFileIcon(path: String, result: @escaping FlutterResult) {
    if let cachedData = iconDataCache.object(forKey: path as NSString) {
      result(FlutterStandardTypedData(bytes: cachedData as Data))
      return
    }
    let icon: NSImage
    if let cachedIcon = iconCache.object(forKey: path as NSString) {
      icon = cachedIcon
    } else {
      icon = NSWorkspace.shared.icon(forFile: path)
      iconCache.setObject(icon, forKey: path as NSString)
    }
    guard let cgImage = icon.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
      result(
        FlutterError(
          code: "ICON_CONVERSION_FAILED", message: "Unable to read the file icon", details: path))
      return
    }
    DispatchQueue.global(qos: .userInitiated).async {
      let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
      guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
        DispatchQueue.main.async {
          result(
            FlutterError(
              code: "ICON_CONVERSION_FAILED", message: "Unable to encode the file icon",
              details: path))
        }
        return
      }
      DispatchQueue.main.async {
        self.iconDataCache.setObject(pngData as NSData, forKey: path as NSString)
        result(FlutterStandardTypedData(bytes: pngData))
      }
    }
  }

  private func convertImage(from path: String, to format: ImageFormat) -> String? {
    guard let image = NSImage(contentsOfFile: path),
      let tiffData = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffData)
    else { return nil }

    let fileType: NSBitmapImageRep.FileType
    let fileExtension: String
    switch format {
    case .png: fileType = .png; fileExtension = "png"
    case .jpeg: fileType = .jpeg; fileExtension = "jpg"
    case .tiff: fileType = .tiff; fileExtension = "tiff"
    case .webp: fileType = .png; fileExtension = "webp"
    }
    guard let imageData = bitmap.representation(using: fileType, properties: [:]) else {
      return nil
    }
    let fileName = "temp_file_\(UUID().uuidString).\(fileExtension)"
    let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
    do {
      try imageData.write(to: outputURL)
      return outputURL.path
    } catch {
      return nil
    }
  }

  private func cleanupTempFiles() {
    let fileManager = FileManager.default
    let tempDirectoryURL = fileManager.temporaryDirectory
    do {
      let files = try fileManager.contentsOfDirectory(
        at: tempDirectoryURL, includingPropertiesForKeys: nil, options: [])
      for file in files where file.lastPathComponent.starts(with: "temp_file_") {
        try fileManager.removeItem(at: file)
      }
    } catch {
      NSLog("Error removing temporary files: \(error)")
    }
  }

  private func showPopover(content: String, edge: NSRectEdge, window: ShelfWindow) {
    if popover == nil { popover = NSPopover() }
    if popover?.isShown == true {
      if let existing = popover?.contentViewController?.view.subviews.first as? NSTextField {
        existing.stringValue = content
      }
      return
    }
    let contentViewController = NSViewController()
    let contentView = NSTextField(labelWithString: content)
    contentView.drawsBackground = false
    contentView.lineBreakMode = .byWordWrapping
    contentView.preferredMaxLayoutWidth = 200
    let paddingView = NSView()
    paddingView.addSubview(contentView)
    contentView.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      contentView.topAnchor.constraint(equalTo: paddingView.topAnchor, constant: 10),
      contentView.leadingAnchor.constraint(equalTo: paddingView.leadingAnchor, constant: 10),
      contentView.trailingAnchor.constraint(equalTo: paddingView.trailingAnchor, constant: -10),
      contentView.bottomAnchor.constraint(equalTo: paddingView.bottomAnchor, constant: -10),
    ])
    contentViewController.view = paddingView
    popover?.contentViewController = contentViewController
    popover?.behavior = .transient
    popover?.animates = true
    let mouseLocation = NSEvent.mouseLocation
    popover?.show(
      relativeTo: NSRect(origin: mouseLocation, size: .zero), of: window.contentView!,
      preferredEdge: edge)
  }

  private func shareXFiles(
    fileURLs: [String], window: ShelfWindow, result: @escaping FlutterResult
  ) {
    DispatchQueue.main.async {
      let urls = fileURLs.map { path -> URL in
        if path.starts(with: "http://") || path.starts(with: "https://") {
          return URL(string: path)!
        }
        return URL(fileURLWithPath: path)
      }
      let picker = NSSharingServicePicker(items: urls)
      picker.delegate = ShareSuccessDelegate(result: result).keep()
      if let contentView = window.contentView {
        picker.show(relativeTo: window.frame, of: contentView, preferredEdge: .minY)
      } else {
        result(
          FlutterError(code: "SHARE_ERROR", message: "Unable to show share picker", details: nil))
      }
    }
  }

  private func showNativeAlert(
    call: FlutterMethodCall, window: ShelfWindow, result: @escaping FlutterResult
  ) {
    guard let args = call.arguments as? [String: Any],
      let title = args["title"] as? String,
      let message = args["message"] as? String
    else {
      result(
        FlutterError(code: "INVALID_ARGUMENT", message: "Invalid alert arguments", details: nil))
      return
    }
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.alertStyle = .informational
    if let buttons = args["buttons"] as? [String], !buttons.isEmpty {
      for button in buttons { alert.addButton(withTitle: button) }
    } else {
      alert.addButton(withTitle: "OK")
    }
    let response = alert.runModal()
    result(response.rawValue)
  }
}
