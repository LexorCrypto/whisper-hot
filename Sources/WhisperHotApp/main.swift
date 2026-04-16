import AppKit
import WhisperHotLib

Preferences.registerDefaults()
let delegate = AppDelegate()
let app = NSApplication.shared
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
