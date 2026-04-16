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

        // Temporarily become a regular app so the menu bar shows
        // "WhisperHot" next to the Apple logo and the window gets
        // proper focus behavior. Reverted on close.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)

        NotificationCenter.default.post(name: .whisperHotSettingsWillShow, object: nil)
    }

    // MARK: - Window construction

    private func buildWindow() {
        let hostingView = NSHostingView(rootView: SettingsView())
        // Initial content size matches SettingsView's idealWidth/idealHeight
        // so the window boots at a sensible size. The window is resizable,
        // so the user can grow or shrink it; SwiftUI enforces min/max on
        // the content.
        hostingView.frame = NSRect(x: 0, y: 0, width: 740, height: 600)

        let newWindow = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "WhisperHot Settings"
        newWindow.isReleasedWhenClosed = false
        newWindow.contentView = hostingView
        newWindow.center()
        newWindow.delegate = self

        self.window = newWindow
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        NotificationCenter.default.post(name: .whisperHotSettingsWillClose, object: nil)

        // Return to accessory mode so WhisperHot disappears from the Dock
        // and menu bar, restoring the menu-bar-only behavior.
        NSApp.setActivationPolicy(.accessory)

        let ourPID = ProcessInfo.processInfo.processIdentifier
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == ourPID {
            previousApp?.activate(options: [])
        }
        previousApp = nil
    }
}
