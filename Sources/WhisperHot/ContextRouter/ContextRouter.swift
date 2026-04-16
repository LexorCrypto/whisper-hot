import AppKit
import Foundation

/// Resolves which `PostProcessingPreset` to use based on the frontmost
/// application that was active when recording started (`recordingTarget`).
///
/// Rules are evaluated in order; the first matching rule wins. If no rule
/// matches (including the "*" fallback), returns `.cleanup` as the
/// hardcoded safety net.
///
///     ┌─────────────────┐
///     │ recordingTarget  │
///     │ (NSRunningApp)   │
///     └────────┬────────┘
///              │ bundleIdentifier
///              ▼
///     ┌─────────────────┐     ┌──────────┐
///     │  ContextRouter   │────►│  preset   │
///     │  rules[] scan    │     └──────────┘
///     └─────────────────┘
///
enum ContextRouter {
    /// Resolve the best-matching preset for the given recording target.
    /// - Parameter target: The app captured at recording start. Nil means
    ///   WhisperHot itself was frontmost (or no app could be determined).
    /// - Parameter rules: Ordered list of rules to match against. Pass
    ///   `Preferences.contextRules` for the live configuration.
    /// - Returns: The preset from the first matching rule, or `.cleanup`.
    static func resolve(
        target: NSRunningApplication?,
        rules: [ContextRule]
    ) -> PostProcessingPreset {
        let bundleID = target?.bundleIdentifier

        // Scan rules in order. "*" matches anything including nil bundleID
        // (WhisperHot frontmost or unknown app). Exact match otherwise.
        for rule in rules {
            if rule.bundleID == "*" {
                return rule.preset
            }
            if let bid = bundleID, rule.bundleID == bid {
                return rule.preset
            }
        }

        // No rule matched at all (user deleted the fallback "*" rule).
        return .cleanup
    }
}
