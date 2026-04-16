import AppKit
import Foundation

/// Resolves which `PostProcessingPreset` to use based on the frontmost
/// application and optionally its window title (Intent Router).
///
/// Rules are evaluated in order; the first matching rule wins. Rules with
/// `titleContains` are checked before generic bundle-ID-only rules because
/// they appear earlier in the defaults array. If no rule matches (including
/// the "*" fallback), returns `.cleanup` as the hardcoded safety net.
///
///     ┌─────────────────┐     ┌──────────────────┐
///     │ recordingTarget  │     │ window title      │
///     │ (NSRunningApp)   │     │ (for browsers)    │
///     └────────┬────────┘     └────────┬─────────┘
///              │ bundleIdentifier       │ contains?
///              ▼                        ▼
///     ┌────────────────────────────────────────┐
///     │  ContextRouter                          │
///     │  1. bundleID + titleContains match      │
///     │  2. bundleID-only match                 │
///     │  3. "*" fallback                        │
///     └────────────────────┬───────────────────┘
///                          ▼
///                    ┌──────────┐
///                    │  preset   │
///                    └──────────┘
enum ContextRouter {
    /// Resolve the best-matching preset for the given recording target.
    /// - Parameter target: The app captured at recording start. Nil means
    ///   WhisperHot itself was frontmost (or no app could be determined).
    /// - Parameter rules: Ordered list of rules to match against.
    /// - Returns: The preset from the first matching rule, or `.cleanup`.
    static func resolve(
        target: NSRunningApplication?,
        rules: [ContextRule]
    ) -> PostProcessingPreset {
        let bundleID = target?.bundleIdentifier
        // Lazy: only query AX when we actually hit a rule that needs title
        var _windowTitle: String?
        var _titleFetched = false
        func getWindowTitle() -> String? {
            if !_titleFetched {
                _windowTitle = windowTitle(for: target)
                _titleFetched = true
            }
            return _windowTitle
        }

        for rule in rules {
            if rule.bundleID == "*" {
                return rule.preset
            }
            guard let bid = bundleID, rule.bundleID == bid else {
                continue
            }
            // If rule has titleContains, check window title
            if let titleFilter = rule.titleContains, !titleFilter.isEmpty {
                if let title = getWindowTitle(),
                   title.localizedCaseInsensitiveContains(titleFilter) {
                    return rule.preset
                }
                // Title filter didn't match — skip this rule, try next
                continue
            }
            // No title filter — bundle ID match is sufficient
            return rule.preset
        }

        return .cleanup
    }

    /// Attempt to read the frontmost window title of the target app
    /// via Accessibility API. Returns nil if not available.
    private static func windowTitle(for app: NSRunningApplication?) -> String? {
        guard let app else { return nil }

        // AXUIElement requires Accessibility permission. If not granted,
        // this silently returns nil and we fall back to bundle-ID-only matching.
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var focusedWindow: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &focusedWindow)
        guard result == .success else { return nil }

        // swiftlint:disable:next force_cast
        let window = focusedWindow as! AXUIElement
        var titleValue: CFTypeRef?
        let titleResult = AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue)
        guard titleResult == .success, let title = titleValue as? String else { return nil }

        return title
    }
}
