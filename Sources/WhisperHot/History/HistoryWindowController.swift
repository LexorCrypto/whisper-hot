import AppKit
import SwiftUI

extension Notification.Name {
    /// Posted by HistoryWindowController's show() so the hosted SwiftUI
    /// view re-reads the store every time the window appears.
    static let whisperHotHistoryWillShow = Notification.Name("WhisperHot.historyWillShow")
}

@MainActor
final class HistoryWindowController: NSObject, NSWindowDelegate {
    private let store: HistoryStore
    private var window: NSWindow?
    private var previousApp: NSRunningApplication?

    init(store: HistoryStore) {
        self.store = store
        super.init()
    }

    func show() {
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp = front
        } else {
            previousApp = nil
        }

        if window == nil {
            buildWindow()
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: .whisperHotHistoryWillShow, object: nil)
    }

    private func buildWindow() {
        let hosting = NSHostingView(rootView: TranscriptHistoryView(store: store))
        hosting.frame = NSRect(x: 0, y: 0, width: 640, height: 520)

        let w = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        w.title = "WhisperHot History"
        w.isReleasedWhenClosed = false
        w.contentView = hosting
        w.center()
        w.delegate = self
        self.window = w
    }

    func windowWillClose(_ notification: Notification) {
        let ourPID = ProcessInfo.processInfo.processIdentifier
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == ourPID {
            previousApp?.activate(options: [])
        }
        previousApp = nil
    }
}
