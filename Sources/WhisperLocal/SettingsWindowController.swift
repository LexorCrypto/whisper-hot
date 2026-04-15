import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var previousApp: NSRunningApplication?

    func show() {
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp = front
        }

        if window == nil {
            buildWindow()
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)

        // Tell the hosted SwiftUI view to re-read Keychain state. The hosting
        // view is built once and reused, so `.onAppear` only fires on first
        // show — without this nudge, Settings would display stale API-key
        // state across subsequent open/close cycles.
        NotificationCenter.default.post(name: .whisperLocalSettingsWillShow, object: nil)
    }

    // MARK: - Window construction

    private func buildWindow() {
        let hostingView = NSHostingView(rootView: SettingsView())
        // Initial content size matches SettingsView's idealWidth/idealHeight
        // so the window boots at a sensible size. The window is resizable,
        // so the user can grow or shrink it; SwiftUI enforces min/max on
        // the content.
        hostingView.frame = NSRect(x: 0, y: 0, width: 640, height: 560)

        let newWindow = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "WhisperLocal Settings"
        newWindow.isReleasedWhenClosed = false
        newWindow.contentView = hostingView
        newWindow.center()
        newWindow.delegate = self

        self.window = newWindow
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // Tell the hosted SwiftUI views (specifically `HotkeyRecorderView`)
        // to drop their NSEvent monitors. The hosting view is reused across
        // open/close cycles, so `.onDisappear` is not reliable here.
        NotificationCenter.default.post(name: .whisperLocalSettingsWillClose, object: nil)

        // Only restore the previously-focused app if WhisperLocal is still
        // frontmost at close time. Same focus-preservation rule as the
        // onboarding window (see Block 7 review).
        let ourPID = ProcessInfo.processInfo.processIdentifier
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == ourPID {
            previousApp?.activate(options: [])
        }
        previousApp = nil
    }
}
