import XCTest
@testable import WhisperHotLib

/// Tests for WordReplacement.apply / applyAll, the post-STT find-and-replace
/// pass that fixes common Russian/English tech term mis-transcriptions.
final class WordReplacementTests: XCTestCase {

    // MARK: - Single replacement

    func testApplyReplacesExactMatch() {
        let r = WordReplacement(from: "foo", to: "bar")
        XCTAssertEqual(r.apply(to: "foo"), "bar")
    }

    func testApplyIsCaseInsensitive() {
        let r = WordReplacement(from: "foo", to: "bar")
        XCTAssertEqual(r.apply(to: "FOO Foo fOo"), "bar bar bar")
    }

    /// The defaults are Russian terms; the case-insensitive contract MUST hold
    /// for Cyrillic uppercase too, not just ASCII. Locks in unicode-aware
    /// matching so a future switch to a non-Foundation matcher cannot
    /// silently regress on `ДЕПЛОЙ` / `КОММИТ` etc.
    func testApplyIsCaseInsensitiveForCyrillic() {
        let r = WordReplacement(from: "деплой", to: "deploy")
        XCTAssertEqual(r.apply(to: "Запустил ДЕПЛОЙ"), "Запустил deploy")
    }

    func testApplyReplacesAllOccurrences() {
        let r = WordReplacement(from: "x", to: "y")
        XCTAssertEqual(r.apply(to: "xxx"), "yyy")
    }

    func testApplyEmptyFromIsNoOp() {
        let r = WordReplacement(from: "", to: "anything")
        XCTAssertEqual(r.apply(to: "untouched text"), "untouched text")
    }

    func testApplyEmptyToDeletesMatch() {
        let r = WordReplacement(from: "noise", to: "")
        XCTAssertEqual(r.apply(to: "before noise after"), "before  after")
    }

    func testApplyPreservesNonMatchingText() {
        let r = WordReplacement(from: "коммит", to: "commit")
        XCTAssertEqual(
            r.apply(to: "Сделай коммит и пуш"),
            "Сделай commit и пуш"
        )
    }

    // MARK: - applyAll

    func testApplyAllEmptyListReturnsOriginal() {
        let result = WordReplacement.applyAll([], to: "untouched")
        XCTAssertEqual(result, "untouched")
    }

    func testApplyAllRunsRulesInOrder() {
        // Order matters for chained replacements: a→b, b→c should yield c.
        let rules = [
            WordReplacement(from: "a", to: "b"),
            WordReplacement(from: "b", to: "c"),
        ]
        XCTAssertEqual(WordReplacement.applyAll(rules, to: "a"), "c")
    }

    func testApplyAllOnDefaultsTransformsRussianTechTerms() {
        // Exact-equality assertion catches drift more reliably than contains().
        let raw = "Сделай коммит, потом пуш и деплой"
        let result = WordReplacement.applyAll(WordReplacement.defaults, to: raw)
        XCTAssertEqual(result, "Сделай commit, потом push и deploy")
    }

    func testApplyAllPreservesUnaffectedText() {
        let rules = [WordReplacement(from: "foo", to: "bar")]
        let text = "no match here"
        XCTAssertEqual(WordReplacement.applyAll(rules, to: text), text)
    }

    /// Pins the current production behavior: replacements are substring-based,
    /// not word-bounded. With the default `пуш → push` rule, ordinary Russian
    /// words like `пушка` (cannon) get mangled into `pushка`. This is a known
    /// limitation that is acceptable today for a personal app — the test exists
    /// so any future change to word-boundary matching is a deliberate decision,
    /// not a silent regression.
    func testApplyAllDefaultsCorruptSubstringMatches() {
        let raw = "у меня пушка"
        let result = WordReplacement.applyAll(WordReplacement.defaults, to: raw)
        XCTAssertEqual(result, "у меня pushка")
    }
}
