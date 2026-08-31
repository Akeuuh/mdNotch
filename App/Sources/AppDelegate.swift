import AppKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBar: StatusBarController?
    private var notch: NotchWindowController?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // LSUIElement in Info.plist already hides the Dock icon; this keeps
        // behavior correct when launched from Xcode or a debug build.
        NSApp.setActivationPolicy(.accessory)

        statusBar = StatusBarController()

        let notch = NotchWindowController()
        notch.onFilesDropped = { urls in
            NSLog("mdNotch: received drop: %@", urls.map(\.lastPathComponent).joined(separator: ", "))
        }
        notch.start()
        self.notch = notch
    }
}
