import AppKit

@main
enum WhisperHotApp {
    static let delegate = AppDelegate()

    static func main() {
        Preferences.registerDefaults()
        let app = NSApplication.shared
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
