import Foundation

/// Deletes orphan WAV files left in the recordings cache directory according
/// to the user's `AudioRetention` policy. Called:
///   - at app launch to clean up stragglers from prior sessions
///   - on app quit to honor `.untilQuit`
///   - per-recording by MenuBarController (`.immediate` success cleanup is
///     done inline after finishTranscription, not through this class)
@MainActor
enum AudioRetentionSweeper {
    /// The WAV file for the in-flight recording (if any). MenuBarController
    /// sets this on start and clears it on finish. The sweep and wipe
    /// helpers below never delete this file, so a user who hits "Wipe all"
    /// while recording cannot corrupt their own live session.
    static var activeRecordingURL: URL?

    /// Absolute path to the recordings directory, or nil if it doesn't exist yet.
    private static var recordingsDirectory: URL? {
        let fm = FileManager.default
        guard let caches = try? fm.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else { return nil }
        let dir = caches.appendingPathComponent("WhisperLocal/recordings", isDirectory: true)
        return fm.fileExists(atPath: dir.path) ? dir : nil
    }

    /// Delete files older than the current retention policy's sweep age.
    /// No-op when retention is `.forever` or `.untilQuit`.
    static func sweepStragglers() {
        guard let maxAge = Preferences.audioRetention.sweepMaxAgeSeconds else { return }
        guard let dir = recordingsDirectory else { return }

        let now = Date()
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        guard let enumerator = fm.enumerator(
            at: dir,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else { return }

        var deleted = 0
        while let url = enumerator.nextObject() as? URL {
            if url.standardizedFileURL == activeRecordingURL?.standardizedFileURL {
                continue
            }
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true else { continue }
            guard let modified = values?.contentModificationDate else { continue }
            let age = now.timeIntervalSince(modified)
            if age >= maxAge {
                do {
                    try fm.removeItem(at: url)
                    deleted += 1
                } catch {
                    NSLog("WhisperLocal: failed to delete stale audio \(url.lastPathComponent) → \(error.localizedDescription)")
                }
            }
        }
        if deleted > 0 {
            NSLog("WhisperLocal: retention sweep removed \(deleted) audio file(s)")
        }
    }

    /// Delete every file in the recordings directory. Used by the
    /// Settings "Wipe now" button (with `includingActive: false`, which
    /// preserves a running session) and by AppDelegate's terminate
    /// handler for `.untilQuit` retention (with `includingActive: true`,
    /// which removes every trace regardless of state — shutdown is the
    /// whole point of that policy).
    static func wipeAll(includingActive: Bool = false) {
        guard let dir = recordingsDirectory else { return }
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        var deleted = 0
        for url in contents {
            if !includingActive,
               url.standardizedFileURL == activeRecordingURL?.standardizedFileURL {
                continue
            }
            do {
                try fm.removeItem(at: url)
                deleted += 1
            } catch {
                NSLog("WhisperLocal: failed to wipe \(url.lastPathComponent) → \(error.localizedDescription)")
            }
        }
        if deleted > 0 {
            NSLog("WhisperLocal: retention wipe removed \(deleted) audio file(s)")
        }
    }

    /// Delete a specific file. Safe to call for non-existent URLs.
    static func delete(_ url: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return }
        do {
            try fm.removeItem(at: url)
        } catch {
            NSLog("WhisperLocal: failed to delete \(url.lastPathComponent) → \(error.localizedDescription)")
        }
    }
}
