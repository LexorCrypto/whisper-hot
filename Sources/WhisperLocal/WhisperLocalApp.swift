import AppKit

@main
enum WhisperLocalApp {
    static let delegate = AppDelegate()

    static func main() {
        Preferences.registerDefaults()
        let app = NSApplication.shared
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
