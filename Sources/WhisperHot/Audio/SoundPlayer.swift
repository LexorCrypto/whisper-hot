import AudioToolbox
import Foundation

/// Plays short UI chimes via AudioServicesPlaySystemSound.
///
/// Looks for custom AIFF files in the app bundle's Resources/Sounds/
/// directory first. Falls back to built-in macOS system sounds if custom
/// sounds are not found (e.g. when running from SwiftPM debug build
/// without the full app bundle).
@MainActor
final class SoundPlayer {
    enum Chime {
        case start
        case stop
        case done

        var customFileName: String {
            switch self {
            case .start: return "start"
            case .stop: return "stop"
            case .done: return "done"
            }
        }

        var systemSoundName: String {
            switch self {
            case .start: return "Morse"
            case .stop: return "Tink"
            case .done: return "Glass"
            }
        }
    }

    private var soundIDs: [Chime: SystemSoundID] = [:]
    private let systemSoundsRoot = URL(fileURLWithPath: "/System/Library/Sounds")

    init() {
        register(.start)
        register(.stop)
        register(.done)
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

    private func register(_ chime: Chime) {
        // Try custom sound from app bundle first
        if let customURL = customSoundURL(for: chime),
           let sid = createSoundID(from: customURL) {
            soundIDs[chime] = sid
            return
        }

        // Fall back to system sound
        let systemURL = systemSoundsRoot.appendingPathComponent("\(chime.systemSoundName).aiff")
        if let sid = createSoundID(from: systemURL) {
            soundIDs[chime] = sid
        } else {
            NSLog("WhisperHot: no sound available for \(chime)")
        }
    }

    private func customSoundURL(for chime: Chime) -> URL? {
        // Fallback: app bundle (Contents/Resources/Sounds/ via build.sh)
        if let url = Bundle.main.url(forResource: chime.customFileName, withExtension: "aiff", subdirectory: "Sounds") {
            return url
        }
        if let url = Bundle.main.url(forResource: chime.customFileName, withExtension: "aiff") {
            return url
        }
        return nil
    }

    private func createSoundID(from url: URL) -> SystemSoundID? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        var sid: SystemSoundID = 0
        let status = AudioServicesCreateSystemSoundID(url as CFURL, &sid)
        guard status == kAudioServicesNoError else {
            NSLog("WhisperHot: AudioServicesCreateSystemSoundID failed for \(url.lastPathComponent) with OSStatus \(status)")
            return nil
        }
        return sid
    }
}
