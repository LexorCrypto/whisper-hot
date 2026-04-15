import Foundation
import ServiceManagement

/// Thin wrapper over `SMAppService.mainApp` (macOS 13+). Registers the
/// current bundled app as a login item so WhisperHot launches when the
/// user signs in.
///
/// SMAppService manages its own persistent state in
/// `~/Library/LaunchAgents/...` under the hood, so we do NOT store a
/// parallel bool in UserDefaults. The Settings toggle is driven directly
/// by `SMAppService.mainApp.status`.
///
/// Works only when the .app is launched from a location macOS considers a
/// valid install (typically /Applications or ~/Applications). When the
/// app is running out of a build cache the status can report `.notFound`
/// or the `register()` call can fail — surface those states to the user
/// rather than pretending they worked.
@MainActor
enum LaunchAtLoginController {
    static var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    static var isEnabled: Bool {
        status == .enabled
    }

    /// Enable or disable launch-at-login. Throws if SMAppService refuses
    /// to register/unregister (e.g. the app isn't in a valid install path,
    /// or the user previously denied Login Items approval).
    static func setEnabled(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        if enabled {
            try service.register()
        } else {
            try service.unregister()
        }
    }

    /// Human-readable summary of the current status for display in Settings.
    static var statusDescription: String {
        switch status {
        case .notRegistered:
            return "Not registered — toggle on to enable."
        case .enabled:
            return "Enabled."
        case .requiresApproval:
            return "Pending approval in System Settings → General → Login Items."
        case .notFound:
            return "Not found — macOS cannot manage this copy of WhisperHot as a login item. Move the app to a stable install path (for example /Applications) and try again."
        @unknown default:
            return "Unknown launch-at-login state."
        }
    }

    /// Maps a thrown SMAppService error to a user-facing message. Prefixes
    /// the localized description with a clear "Failed:" marker so the
    /// status caption does not read like a passive success.
    static func describe(error: Error) -> String {
        let ns = error as NSError
        // SMAppService throws NSError with a descriptive `localizedDescription`
        // even when the underlying code is in ServiceManagement's own
        // domain. Prefix it so the caption makes the failure obvious.
        return "Failed: \(ns.localizedDescription) (code \(ns.code))"
    }
}
