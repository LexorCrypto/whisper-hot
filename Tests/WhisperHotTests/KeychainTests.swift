import XCTest
@testable import WhisperHotLib

/// Round-trip tests for the Keychain wrapper. Uses a unique per-test-run
/// service prefix so test entries cannot collide with the user's real
/// production Keychain. tearDown deletes everything we created so the
/// machine's Keychain is left clean even when assertions fail.
final class KeychainTests: XCTestCase {
    /// Unique service identifier for this test class, set fresh per run via UUID.
    /// All Keychain operations in tests use this service so the user's real
    /// `com.aleksejsupilin.WhisperHot` entries are never touched.
    private var testService: String!

    override func setUp() {
        super.setUp()
        testService = "com.aleksejsupilin.WhisperHot.tests.\(UUID().uuidString)"
    }

    override func tearDown() {
        // Best-effort cleanup of every account we may have created.
        for account in [Keychain.Account.openAI, .openRouter, .groq, .polzaAI, .customEndpoint, .historyEncryptionKey] {
            try? Keychain.delete(account: account, service: testService)
        }
        testService = nil
        super.tearDown()
    }

    // MARK: - String API (save / readAPIKey / delete)

    func testSaveAndReadStringRoundTrip() throws {
        try Keychain.save(apiKey: "sk-test-12345", account: .openAI, service: testService)
        let read = try Keychain.readAPIKey(account: .openAI, service: testService)
        XCTAssertEqual(read, "sk-test-12345")
    }

    func testReadMissingThrowsItemNotFound() {
        XCTAssertThrowsError(try Keychain.readAPIKey(account: .groq, service: testService)) { error in
            guard case Keychain.KeychainError.itemNotFound = error else {
                XCTFail("expected .itemNotFound, got \(error)")
                return
            }
        }
    }

    func testSaveOverwritesExistingValue() throws {
        try Keychain.save(apiKey: "first", account: .openRouter, service: testService)
        try Keychain.save(apiKey: "second", account: .openRouter, service: testService)
        let read = try Keychain.readAPIKey(account: .openRouter, service: testService)
        XCTAssertEqual(read, "second")
    }

    func testDeleteRemovesItem() throws {
        try Keychain.save(apiKey: "to-delete", account: .polzaAI, service: testService)
        try Keychain.delete(account: .polzaAI, service: testService)
        XCTAssertThrowsError(try Keychain.readAPIKey(account: .polzaAI, service: testService))
    }

    func testDeleteMissingItemDoesNotThrow() {
        // Documented contract: delete is idempotent on missing items.
        XCTAssertNoThrow(try Keychain.delete(account: .customEndpoint, service: testService))
    }

    // MARK: - Account isolation

    func testDifferentAccountsHaveIndependentValues() throws {
        try Keychain.save(apiKey: "openai-key", account: .openAI, service: testService)
        try Keychain.save(apiKey: "groq-key", account: .groq, service: testService)
        XCTAssertEqual(try Keychain.readAPIKey(account: .openAI, service: testService), "openai-key")
        XCTAssertEqual(try Keychain.readAPIKey(account: .groq, service: testService), "groq-key")
    }

    func testServiceIsolationPreventsCrossPollution() throws {
        // A different service must not see entries from this test's service.
        let otherService = "\(testService!).other"
        try Keychain.save(apiKey: "lives-only-in-main", account: .openAI, service: testService)
        XCTAssertThrowsError(try Keychain.readAPIKey(account: .openAI, service: otherService)) { error in
            guard case Keychain.KeychainError.itemNotFound = error else {
                XCTFail("expected itemNotFound on other service, got \(error)")
                return
            }
        }
    }

    // MARK: - Data API (saveData / readData) — used by HistoryStore for AES-GCM keys

    func testSaveAndReadDataRoundTrip() throws {
        let payload = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        try Keychain.saveData(payload, account: .historyEncryptionKey, service: testService)
        let read = try Keychain.readData(account: .historyEncryptionKey, service: testService)
        XCTAssertEqual(read, payload)
    }

    func testReadDataMissingThrowsItemNotFound() {
        XCTAssertThrowsError(try Keychain.readData(account: .historyEncryptionKey, service: testService)) { error in
            guard case Keychain.KeychainError.itemNotFound = error else {
                XCTFail("expected .itemNotFound, got \(error)")
                return
            }
        }
    }

    func testSaveDataOverwritesExisting() throws {
        let first = Data([0x01, 0x02, 0x03])
        let second = Data([0x0A, 0x0B, 0x0C])
        try Keychain.saveData(first, account: .historyEncryptionKey, service: testService)
        try Keychain.saveData(second, account: .historyEncryptionKey, service: testService)
        XCTAssertEqual(try Keychain.readData(account: .historyEncryptionKey, service: testService), second)
    }

    // MARK: - Mixed string/data interop on the same account

    func testReadAPIKeyOnNonUTF8DataThrowsInvalidData() throws {
        // Write raw bytes that don't form valid UTF-8 via saveData, then try
        // to read them as a string via readAPIKey. The wrapper must surface
        // .invalidData, not silently produce a corrupt string.
        let invalidUTF8 = Data([0xFF, 0xFE, 0xFD])
        try Keychain.saveData(invalidUTF8, account: .openAI, service: testService)
        XCTAssertThrowsError(try Keychain.readAPIKey(account: .openAI, service: testService)) { error in
            guard case Keychain.KeychainError.invalidData = error else {
                XCTFail("expected .invalidData, got \(error)")
                return
            }
        }
    }
}
