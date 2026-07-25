import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var controller: ParagondayController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        controller = ParagondayController()
        controller.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.stop()
    }
}
