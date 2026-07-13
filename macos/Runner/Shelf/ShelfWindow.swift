import AppKit
import FlutterMacOS
import QuickLookUI

/// Lightweight AppKit shelf window hosting one Flutter Engine via WindowRuntime.
final class ShelfWindow: NSWindow {
  let shelfId: String
  private(set) var runtime: WindowRuntime?
  private(set) var flutterViewController: FlutterViewController?
  private var engine: FlutterEngine?
  private(set) var engineStarted = false
  private var didRevealFlutterContent = false

  init(shelfId: String, source: ShelfOpenSource, position: NSPoint) {
    self.shelfId = shelfId
    let size = NSSize(width: 200, height: 200)
    let screen = NSScreen.screens.first { NSMouseInRect(position, $0.frame, false) }
    let bounds = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(origin: position, size: size)
    let frame = NSRect(
      x: max(bounds.minX, min(position.x - size.width / 2, bounds.maxX - size.width)),
      y: max(bounds.minY, min(position.y, bounds.maxY - size.height)),
      width: size.width,
      height: size.height
    )
    super.init(
      contentRect: frame,
      styleMask: [.borderless, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    isReleasedWhenClosed = false
    minSize = size
    configureChrome()
    engineStarted = bootstrapEngine(source: source)
    // Assigning a fresh FlutterViewController can temporarily report a zero
    // preferredContentSize and collapse a borderless NSWindow to 0×0. Keep the
    // native creation frame authoritative; Dart may resize it later by mode.
    setFrame(frame, display: false)
  }

  private func configureChrome() {
    // The window is ordered immediately so it can receive an in-flight Finder
    // drop, but remains transparent until Flutter reports its first frame.
    alphaValue = 0
    isOpaque = false
    backgroundColor = .clear
    titleVisibility = .hidden
    titlebarAppearsTransparent = true
    standardWindowButton(.closeButton)?.isHidden = true
    standardWindowButton(.miniaturizeButton)?.isHidden = true
    standardWindowButton(.zoomButton)?.isHidden = true
    level = .floating
    collectionBehavior.insert(.canJoinAllSpaces)
    collectionBehavior.insert(.fullScreenPrimary)
    collectionBehavior.insert(.stationary)
    collectionBehavior.insert(.transient)
    if #available(macOS 13.0, *) {
      collectionBehavior.insert(.canJoinAllApplications)
    }
    contentView?.wantsLayer = true
    contentView?.layer?.cornerRadius = 32
    contentView?.layer?.masksToBounds = true
  }

  @discardableResult
  private func bootstrapEngine(source: ShelfOpenSource) -> Bool {
    let project = FlutterDartProject()
    project.dartEntrypointArguments = [shelfId, source.rawValue]
    let engine = FlutterEngine(name: "shelf-\(shelfId)", project: project)
    self.engine = engine

    // FlutterViewController(engine:) starts an unstarted engine using the
    // default `main` entrypoint. Start the shelf entrypoint first, otherwise a
    // later run(withEntrypoint: "shelfMain") returns false and the shelf is
    // immediately closed.
    guard engine.run(withEntrypoint: "shelfMain") else {
      NSLog("[SHELF] failed to start shelfMain for id=%@", shelfId)
      return false
    }

    // Attach the native view before registering view-dependent plugins such as
    // irondash_engine_context / super_native_extensions.
    let fvc = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
    fvc.backgroundColor = .clear
    self.flutterViewController = fvc
    contentViewController = fvc

    // contentViewController replaces the content view, so clipping configured
    // before engine bootstrap would otherwise be lost and expose square edges.
    contentView?.wantsLayer = true
    contentView?.layer?.backgroundColor = NSColor.clear.cgColor
    contentView?.layer?.cornerRadius = 32
    contentView?.layer?.masksToBounds = true
    fvc.view.wantsLayer = true
    fvc.view.layer?.backgroundColor = NSColor.clear.cgColor
    fvc.view.layer?.cornerRadius = 32
    fvc.view.layer?.masksToBounds = true

    let effectView = NSVisualEffectView()
    effectView.autoresizingMask = [.width, .height]
    effectView.blendingMode = .behindWindow
    effectView.material = .menu
    effectView.state = .active
    effectView.frame = fvc.view.bounds
    effectView.wantsLayer = true
    effectView.layer?.cornerRadius = 32
    effectView.layer?.masksToBounds = true
    fvc.view.addSubview(effectView, positioned: .below, relativeTo: nil)

    // Irondash creates its view context on the next main-queue turn. shelfMain
    // yields once before constructing its widget tree, giving that setup a
    // chance to complete before super_native_extensions asks for the view.
    RegisterGeneratedPlugins(registry: engine)

    let runtime = WindowRuntime(
      shelfId: shelfId,
      engine: engine,
      flutterViewController: fvc,
      window: self
    )
    runtime.onDropAccepted = { [weak self] _ in
      guard let self else { return }
      ShelfManager.shared.markDropAccepted(shelfId: self.shelfId)
    }
    runtime.onCloseRequested = { [weak self] in
      guard let self else { return }
      ShelfManager.shared.closeShelf(id: self.shelfId)
    }
    runtime.start()
    self.runtime = runtime
    registerAsDropDestination()
    if ShelfManager.shared.hasActiveExternalDrag {
      runtime.beginExternalDragCapture()
    }

    return true
  }

  private func registerAsDropDestination() {
    registerForDraggedTypes([
      NSPasteboard.PasteboardType.fileURL,
      NSPasteboard.PasteboardType.png,
      NSPasteboard.PasteboardType.tiff,
      NSPasteboard.PasteboardType.string,
      NSPasteboard.PasteboardType.URL,
    ])
  }

  // MARK: - NSDraggingDestination (permanent full-window target)
  // These are protocol methods on NSWindow, not overridable superclass methods.

  func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    runtime?.draggingEntered(sender) ?? .copy
  }

  func draggingExited(_ sender: NSDraggingInfo?) {
    runtime?.draggingExited(sender)
  }

  func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
    runtime?.draggingUpdated(sender) ?? .copy
  }

  func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    runtime?.performDragOperation(sender) ?? false
  }

  func concludeDragOperation(_ sender: NSDraggingInfo?) {
    runtime?.concludeDragOperation(sender)
  }

  func showActivated(activateApp: Bool) {
    setIsVisible(true)
    makeKeyAndOrderFront(nil)
    if activateApp {
      NSApp.activate(ignoringOtherApps: true)
    }
  }

  func showWithoutActivating() {
    // Shake shelves must not steal focus from Finder drag source.
    orderFrontRegardless()
  }

  /// Called by WindowRuntime after Dart has rendered the first clipped frame.
  func revealFlutterContent() {
    guard !didRevealFlutterContent else { return }
    didRevealFlutterContent = true
    invalidateShadow()
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.18
      context.timingFunction = CAMediaTimingFunction(name: .easeOut)
      animator().alphaValue = 1.0
    } completionHandler: { [weak self] in
      // Always commit the final state even if AppKit skips/cancels animation.
      self?.alphaValue = 1.0
    }
  }

  func tearDown() {
    runtime?.dispose()
    runtime = nil
    if let fvc = flutterViewController {
      fvc.engine.shutDownEngine()
      contentViewController = nil
    }
    flutterViewController = nil
    engine = nil
    orderOut(nil)
    close()
  }

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }

  @objc func paste(_ sender: Any?) {
    let paths = DropTarget.materializePaths(from: .general)
    guard !paths.isEmpty else { return }
    runtime?.deliverPaste(paths)
  }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    if flags.contains(.command),
      !flags.contains(.shift),
      !flags.contains(.option),
      !flags.contains(.control),
      event.charactersIgnoringModifiers?.lowercased() == "v"
    {
      if let firstResponder = firstResponder,
        firstResponder is NSTextView || firstResponder is NSTextField
      {
        return super.performKeyEquivalent(with: event)
      }
      let paths = DropTarget.materializePaths(from: .general)
      if !paths.isEmpty {
        runtime?.deliverPaste(paths)
        return true
      }
    }
    return super.performKeyEquivalent(with: event)
  }

  override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

  override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
    let controller = QuickLookPreviewController.shared
    panel.dataSource = controller
    panel.delegate = controller
    panel.reloadData()
  }

  override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
    panel.dataSource = nil
    panel.delegate = nil
  }
}
