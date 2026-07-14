import AppKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var demoController: Stage0DemoController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = Stage0DemoController()
        demoController = controller
        controller.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
