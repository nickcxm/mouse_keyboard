import AppKit

@main
enum MouseKeyboardApp {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        // NSApplication holds its delegate weakly; retain it for the entire event loop.
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}
