import AudioToolbox
import Foundation

/// Plays short UI chimes via AudioServicesPlaySystemSound.
/// Uses built-in macOS system sounds from /System/Library/Sounds/ so no
/// custom .caf files need to be bundled. Custom sounds can be substituted
/// later by pointing `fileURL` at bundled resources instead.
@MainActor
final class SoundPlayer {
    enum Chime {
        case start
        case stop
        case done
    }

    private var soundIDs: [Chime: SystemSoundID] = [:]
    private let systemSoundsRoot = URL(fileURLWithPath: "/System/Library/Sounds")

    init() {
        register(.start, named: "Morse")
        register(.stop, named: "Tink")
        register(.done, named: "Glass")
    }

    deinit {
        for (_, sid) in soundIDs {
            AudioServicesDisposeSystemSoundID(sid)
        }
    }

    /// Fire-and-forget. Non-blocking. Safe to call from the main thread.
    func play(_ chime: Chime) {
        guard let sid = soundIDs[chime] else { return }
        AudioServicesPlaySystemSound(sid)
    }

    // MARK: - Private

    private func register(_ chime: Chime, named baseName: String) {
        let url = systemSoundsRoot.appendingPathComponent("\(baseName).aiff")
        guard FileManager.default.fileExists(atPath: url.path) else {
            NSLog("WhisperHot: system sound missing at \(url.path)")
            return
        }
        var sid: SystemSoundID = 0
        let status = AudioServicesCreateSystemSoundID(url as CFURL, &sid)
        guard status == kAudioServicesNoError else {
            NSLog("WhisperHot: AudioServicesCreateSystemSoundID failed for \(baseName) with OSStatus \(status)")
            return
        }
        soundIDs[chime] = sid
    }
}
