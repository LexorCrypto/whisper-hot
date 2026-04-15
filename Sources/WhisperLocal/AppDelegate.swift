import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Retention housekeeping before any recording work starts.
        if Preferences.audioRetention == .untilQuit {
            // .untilQuit means "only keep for the current session". If the
            // prior run force-quit or crashed, `applicationWillTerminate`
            // never fired, so stragglers from that session are still on
            // disk. Wipe them now — this is the launch-side guarantee for
            // the policy. No session is in flight yet, so `includingActive`
            // can be true (there is no active file to protect).
            AudioRetentionSweeper.wipeAll(includingActive: true)
        } else {
            AudioRetentionSweeper.sweepStragglers()
        }

        menuBarController = MenuBarController()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Honor the `.untilQuit` retention policy — wipe every audio file
        // on app quit when the user opted into that setting, INCLUDING
        // any file the sweeper would normally protect as an in-flight
        // recording. At shutdown we are ending the session anyway.
        if Preferences.audioRetention == .untilQuit {
            AudioRetentionSweeper.wipeAll(includingActive: true)
        }
    }
}
