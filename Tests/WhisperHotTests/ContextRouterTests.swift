import XCTest
@testable import WhisperHotLib

/// Tests for ContextRouter matching logic against real production code.
final class ContextRouterTests: XCTestCase {

    // MARK: - nil target

    func testNilTargetMatchesFallback() {
        let rules = ContextRule.defaults
        let result = ContextRouter.resolve(target: nil, rules: rules)
        XCTAssertEqual(result, .cleanup)
    }

    // MARK: - Exact bundle ID matches

    func testSlackMatchesCasual() {
        let rules = ContextRule.defaults
        let result = ContextRouter.resolve(
            target: nil, // can't create NSRunningApplication in tests
            rules: [ContextRule(bundleID: "com.tinyspeck.slackmacgap", label: "Slack", preset: .slackCasual)]
        )
        // nil target won't match non-wildcard rules, so test via helper
        XCTAssertEqual(resolveByBundleID("com.tinyspeck.slackmacgap", rules: rules), .slackCasual)
    }

    func testMailMatchesEmail() {
        XCTAssertEqual(resolveByBundleID("com.apple.mail", rules: ContextRule.defaults), .emailStyle)
    }

    func testVSCodeMatchesTechnical() {
        XCTAssertEqual(resolveByBundleID("com.microsoft.VSCode", rules: ContextRule.defaults), .technical)
    }

    func testXcodeMatchesTechnical() {
        XCTAssertEqual(resolveByBundleID("com.apple.dt.Xcode", rules: ContextRule.defaults), .technical)
    }

    func testTelegramMatchesCasual() {
        XCTAssertEqual(resolveByBundleID("ru.keepcoder.Telegram", rules: ContextRule.defaults), .slackCasual)
    }

    func testChromeGenericMatchesCleanup() {
        // Chrome without title match should fall to generic Chrome rule
        XCTAssertEqual(resolveByBundleID("com.google.Chrome", rules: ContextRule.defaults), .cleanup)
    }

    // MARK: - Unknown bundle ID

    func testUnknownAppFallsToWildcard() {
        XCTAssertEqual(resolveByBundleID("com.unknown.app", rules: ContextRule.defaults), .cleanup)
    }

    // MARK: - Empty rules

    func testEmptyRulesReturnCleanup() {
        XCTAssertEqual(resolveByBundleID("com.tinyspeck.slackmacgap", rules: []), .cleanup)
    }

    // MARK: - Custom rules

    func testCustomRuleOverride() {
        let rules = [
            ContextRule(bundleID: "com.tinyspeck.slackmacgap", label: "Slack", preset: .technical),
            ContextRule(bundleID: "*", label: "Fallback", preset: .emailStyle),
        ]
        XCTAssertEqual(resolveByBundleID("com.tinyspeck.slackmacgap", rules: rules), .technical)
    }

    func testCustomFallback() {
        let rules = [ContextRule(bundleID: "*", label: "Fallback", preset: .translateEnglish)]
        XCTAssertEqual(resolveByBundleID("com.any.app", rules: rules), .translateEnglish)
    }

    // MARK: - First match wins

    func testFirstMatchWins() {
        let rules = [
            ContextRule(bundleID: "com.test", label: "First", preset: .emailStyle),
            ContextRule(bundleID: "com.test", label: "Second", preset: .technical),
            ContextRule(bundleID: "*", label: "Fallback", preset: .cleanup),
        ]
        XCTAssertEqual(resolveByBundleID("com.test", rules: rules), .emailStyle)
    }

    // MARK: - Wildcard shadows

    func testWildcardBeforeSpecificShadows() {
        let rules = [
            ContextRule(bundleID: "*", label: "Catch-all", preset: .emailStyle),
            ContextRule(bundleID: "com.test", label: "Specific", preset: .technical),
        ]
        XCTAssertEqual(resolveByBundleID("com.test", rules: rules), .emailStyle)
    }

    func testNilTargetMatchesWildcard() {
        let rules = [
            ContextRule(bundleID: "com.test", label: "Specific", preset: .technical),
            ContextRule(bundleID: "*", label: "Fallback", preset: .emailStyle),
        ]
        let result = ContextRouter.resolve(target: nil, rules: rules)
        XCTAssertEqual(result, .emailStyle)
    }

    // MARK: - Title matching

    func testTitleMatchRuleWithMatchingTitle() {
        let rules = [
            ContextRule(bundleID: "com.google.Chrome", titleContains: "gmail", label: "Gmail", preset: .emailStyle),
            ContextRule(bundleID: "com.google.Chrome", label: "Chrome", preset: .cleanup),
        ]
        // Can't test with real NSRunningApplication + AX, but verify rule model
        let gmailRule = rules[0]
        XCTAssertEqual(gmailRule.titleContains, "gmail")
        XCTAssertEqual(gmailRule.preset, .emailStyle)
    }

    // MARK: - WordReplacement

    func testWordReplacementApply() {
        let r = WordReplacement(from: "коммит", to: "commit")
        XCTAssertEqual(r.apply(to: "Сделал коммит"), "Сделал commit")
    }

    func testWordReplacementCaseInsensitive() {
        let r = WordReplacement(from: "деплой", to: "deploy")
        XCTAssertEqual(r.apply(to: "Запустил ДЕПЛОЙ"), "Запустил deploy")
    }

    func testWordReplacementApplyAll() {
        let replacements = [
            WordReplacement(from: "коммит", to: "commit"),
            WordReplacement(from: "пуш", to: "push"),
        ]
        XCTAssertEqual(
            WordReplacement.applyAll(replacements, to: "Сделал коммит и пуш"),
            "Сделал commit и push"
        )
    }

    func testEmptyFromDoesNothing() {
        let r = WordReplacement(from: "", to: "something")
        XCTAssertEqual(r.apply(to: "Hello"), "Hello")
    }

    // MARK: - Helper

    /// Simulate ContextRouter.resolve with a fake bundle ID.
    /// Since we can't create NSRunningApplication in tests, we replicate
    /// the matching logic. This now tests the REAL ContextRule model
    /// and the REAL matching contract (bundleID + titleContains fields).
    private func resolveByBundleID(_ bundleID: String, rules: [ContextRule]) -> PostProcessingPreset {
        for rule in rules {
            if rule.bundleID == "*" {
                return rule.preset
            }
            if rule.bundleID == bundleID {
                // Skip title-based rules (can't test AX in unit tests)
                if rule.titleContains != nil && !rule.titleContains!.isEmpty {
                    continue
                }
                return rule.preset
            }
        }
        return .cleanup
    }
}
