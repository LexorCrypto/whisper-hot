import XCTest

/// Tests for ContextRouter matching logic.
/// Since SwiftPM executable targets can't be @testable imported, we
/// replicate the matching algorithm here. The logic is a direct copy
/// of ContextRouter.resolve — if it changes, these tests must be
/// updated to match.
final class ContextRouterTests: XCTestCase {

    struct Rule {
        let bundleID: String
        let preset: String
    }

    static let defaultRules: [Rule] = [
        Rule(bundleID: "com.tinyspeck.slackmacgap", preset: "slack"),
        Rule(bundleID: "com.apple.mail", preset: "email"),
        Rule(bundleID: "com.google.Chrome", preset: "cleanup"),
        Rule(bundleID: "com.apple.Safari", preset: "cleanup"),
        Rule(bundleID: "org.mozilla.firefox", preset: "cleanup"),
        Rule(bundleID: "company.thebrowser.Browser", preset: "cleanup"),
        Rule(bundleID: "com.microsoft.edgemac", preset: "cleanup"),
        Rule(bundleID: "com.microsoft.VSCode", preset: "technical"),
        Rule(bundleID: "com.todesktop.230313mzl4w4u92", preset: "technical"),
        Rule(bundleID: "com.apple.dt.Xcode", preset: "technical"),
        Rule(bundleID: "com.apple.iChat", preset: "slack"),
        Rule(bundleID: "ru.keepcoder.Telegram", preset: "slack"),
        Rule(bundleID: "*", preset: "cleanup"),
    ]

    /// Replicate ContextRouter.resolve matching logic.
    func resolve(_ bundleID: String?, rules: [Rule]) -> String {
        for rule in rules {
            if rule.bundleID == "*" {
                return rule.preset
            }
            if let bid = bundleID, rule.bundleID == bid {
                return rule.preset
            }
        }
        return "cleanup"
    }

    // MARK: - nil target

    func testNilTargetMatchesFallback() {
        XCTAssertEqual(resolve(nil, rules: Self.defaultRules), "cleanup")
    }

    // MARK: - Exact matches

    func testSlackMatchesCasual() {
        XCTAssertEqual(resolve("com.tinyspeck.slackmacgap", rules: Self.defaultRules), "slack")
    }

    func testMailMatchesEmail() {
        XCTAssertEqual(resolve("com.apple.mail", rules: Self.defaultRules), "email")
    }

    func testVSCodeMatchesTechnical() {
        XCTAssertEqual(resolve("com.microsoft.VSCode", rules: Self.defaultRules), "technical")
    }

    func testXcodeMatchesTechnical() {
        XCTAssertEqual(resolve("com.apple.dt.Xcode", rules: Self.defaultRules), "technical")
    }

    func testTelegramMatchesCasual() {
        XCTAssertEqual(resolve("ru.keepcoder.Telegram", rules: Self.defaultRules), "slack")
    }

    func testChromeMatchesCleanup() {
        XCTAssertEqual(resolve("com.google.Chrome", rules: Self.defaultRules), "cleanup")
    }

    func testSafariMatchesCleanup() {
        XCTAssertEqual(resolve("com.apple.Safari", rules: Self.defaultRules), "cleanup")
    }

    // MARK: - Unknown bundle ID

    func testUnknownAppFallsToWildcard() {
        XCTAssertEqual(resolve("com.unknown.app", rules: Self.defaultRules), "cleanup")
    }

    // MARK: - Empty rules

    func testEmptyRulesReturnCleanup() {
        XCTAssertEqual(resolve("com.tinyspeck.slackmacgap", rules: []), "cleanup")
    }

    // MARK: - Custom rules

    func testCustomRuleOverride() {
        let rules = [
            Rule(bundleID: "com.tinyspeck.slackmacgap", preset: "technical"),
            Rule(bundleID: "*", preset: "email"),
        ]
        XCTAssertEqual(resolve("com.tinyspeck.slackmacgap", rules: rules), "technical")
    }

    func testCustomFallback() {
        let rules = [Rule(bundleID: "*", preset: "translate_en")]
        XCTAssertEqual(resolve("com.any.app", rules: rules), "translate_en")
    }

    // MARK: - First match wins

    func testFirstMatchWins() {
        let rules = [
            Rule(bundleID: "com.test", preset: "email"),
            Rule(bundleID: "com.test", preset: "technical"),
            Rule(bundleID: "*", preset: "cleanup"),
        ]
        XCTAssertEqual(resolve("com.test", rules: rules), "email")
    }

    // MARK: - Wildcard shadows

    func testWildcardBeforeSpecificShadows() {
        let rules = [
            Rule(bundleID: "*", preset: "email"),
            Rule(bundleID: "com.test", preset: "technical"),
        ]
        XCTAssertEqual(resolve("com.test", rules: rules), "email")
    }

    func testNilTargetMatchesWildcard() {
        let rules = [
            Rule(bundleID: "com.test", preset: "technical"),
            Rule(bundleID: "*", preset: "email"),
        ]
        XCTAssertEqual(resolve(nil, rules: rules), "email")
    }
}
