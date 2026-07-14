import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var applicationController: ApplicationController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = ApplicationController()
        applicationController = controller
        controller.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
