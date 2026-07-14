import AppKit

/// Explicit entry for a storyboard-less AppKit app.
/// `NSApplication.delegate` is weak; keep a process-lifetime strong reference.
private let appDelegate = AppDelegate()

autoreleasepool {
    let app = NSApplication.shared
    app.delegate = appDelegate
    app.run()
}
