import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    let controller = AppController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.start()
    }

    /// The hotkey keeps working with the main window closed; quitting is
    /// explicit (⌘Q / menu).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Clicking the Dock icon reopens the main window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in sender.windows where !(window is NSPanel) {
                window.makeKeyAndOrderFront(nil)
            }
        }
        return true
    }
}
