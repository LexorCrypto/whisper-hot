import Foundation

/// A single mapping from a bundle identifier to a post-processing preset.
/// Rules are matched in order; the first match wins. A `bundleID` of
/// "*" acts as the catch-all fallback and should be last.
///
/// Stored as JSON in UserDefaults so the user can add/remove rules in Settings.
struct ContextRule: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    /// Bundle identifier to match against `NSRunningApplication.bundleIdentifier`.
    /// Exact match. A value of "*" matches everything (fallback).
    var bundleID: String
    /// Optional window title substring match. If set, the rule only matches
    /// when the frontmost window title contains this string (case-insensitive).
    /// Useful for browser-based apps: bundleID=Chrome + titleContains="gmail" → email.
    var titleContains: String?
    /// Human-readable label shown in Settings (e.g. "Slack", "Mail").
    var label: String
    /// The post-processing preset applied when this rule matches.
    var presetRawValue: String

    var preset: PostProcessingPreset {
        PostProcessingPreset(rawValue: presetRawValue) ?? .cleanup
    }

    init(
        id: UUID = UUID(),
        bundleID: String,
        titleContains: String? = nil,
        label: String,
        preset: PostProcessingPreset
    ) {
        self.id = id
        self.bundleID = bundleID
        self.titleContains = titleContains
        self.label = label
        self.presetRawValue = preset.rawValue
    }

    /// Built-in default rules. Returned when UserDefaults has no saved rules.
    static let defaults: [ContextRule] = [
        ContextRule(bundleID: "com.tinyspeck.slackmacgap", label: "Slack", preset: .slackCasual),
        ContextRule(bundleID: "com.apple.mail", label: "Apple Mail", preset: .emailStyle),
        // Browser-specific: title-based matching for web apps (checked before generic browser rules)
        ContextRule(bundleID: "com.google.Chrome", titleContains: "gmail", label: "Gmail (Chrome)", preset: .emailStyle),
        ContextRule(bundleID: "com.google.Chrome", titleContains: "slack", label: "Slack (Chrome)", preset: .slackCasual),
        ContextRule(bundleID: "com.google.Chrome", titleContains: "telegram", label: "Telegram (Chrome)", preset: .slackCasual),
        ContextRule(bundleID: "com.apple.Safari", titleContains: "gmail", label: "Gmail (Safari)", preset: .emailStyle),
        ContextRule(bundleID: "com.apple.Safari", titleContains: "slack", label: "Slack (Safari)", preset: .slackCasual),
        // Generic browser rules (fallback for unmatched browser tabs)
        ContextRule(bundleID: "com.google.Chrome", label: "Chrome", preset: .cleanup),
        ContextRule(bundleID: "com.apple.Safari", label: "Safari", preset: .cleanup),
        ContextRule(bundleID: "org.mozilla.firefox", label: "Firefox", preset: .cleanup),
        ContextRule(bundleID: "company.thebrowser.Browser", label: "Arc", preset: .cleanup),
        ContextRule(bundleID: "com.microsoft.edgemac", label: "Edge", preset: .cleanup),
        ContextRule(bundleID: "com.microsoft.VSCode", label: "VS Code", preset: .technical),
        ContextRule(bundleID: "com.todesktop.230313mzl4w4u92", label: "Cursor", preset: .technical),
        ContextRule(bundleID: "com.apple.dt.Xcode", label: "Xcode", preset: .technical),
        ContextRule(bundleID: "com.apple.iChat", label: "Messages", preset: .slackCasual),
        ContextRule(bundleID: "ru.keepcoder.Telegram", label: "Telegram", preset: .slackCasual),
        ContextRule(bundleID: "*", label: "Everything else", preset: .cleanup),
    ]
}
