import XCTest
@testable import WhisperHotLib

/// Tests for HistoryStore. Each test injects:
///   - a temporary directory under /tmp so we never touch the user's real
///     `~/Library/Application Support/WhisperHot/history.bin`,
///   - a unique Keychain `service` prefix so the AES-GCM key generated
///     during fresh-install paths cannot leak into the user's keychain.
@MainActor
final class HistoryStoreTests: XCTestCase {
    private var tempDir: URL!
    private var testKeychainService: String!

    override func setUp() async throws {
        try await super.setUp()
        let id = UUID().uuidString
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WhisperHotHistoryTests-\(id)", isDirectory: true)
        testKeychainService = "com.aleksejsupilin.WhisperHot.tests.\(id)"
    }

    override func tearDown() async throws {
        if let dir = tempDir, FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.removeItem(at: dir)
        }
        if let service = testKeychainService {
            try? Keychain.delete(account: .historyEncryptionKey, service: service)
        }
        tempDir = nil
        testKeychainService = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func makeStore(
        retentionDays: Int = 0,
        maxEntries: Int = 100
    ) -> HistoryStore {
        HistoryStore(
            storageDirectoryOverride: tempDir,
            keychainService: testKeychainService,
            retentionDaysProvider: { retentionDays },
            maxEntriesProvider: { maxEntries }
        )
    }

    private func makeRecord(text: String = "test", at date: Date = Date()) -> TranscriptRecord {
        TranscriptRecord(createdAt: date, text: text, providerModel: "test/model")
    }

    private var historyFile: URL {
        tempDir.appendingPathComponent("history.bin")
    }

    // MARK: - Fresh install path

    func testFreshInstallStartsEmpty() throws {
        let store = makeStore()
        try store.load()
        XCTAssertTrue(store.records.isEmpty)
    }

    func testAppendCreatesEncryptedFile() throws {
        let store = makeStore()
        try store.append(makeRecord(text: "first"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: historyFile.path))

        // Encrypted on disk: the cleartext "first" must not appear in raw bytes.
        let raw = try Data(contentsOf: historyFile)
        XCTAssertFalse(raw.contains("first".data(using: .utf8)!))
    }

    // MARK: - Encrypt/decrypt round trip

    func testRoundTripPreservesRecords() throws {
        let writer = makeStore()
        try writer.append(makeRecord(text: "hello"))
        try writer.append(makeRecord(text: "world"))
        XCTAssertEqual(writer.records.count, 2)

        // Fresh reader instance reads the file back via Keychain key.
        let reader = makeStore()
        try reader.load()
        XCTAssertEqual(reader.records.count, 2)
        // Newest-first: append inserted "world" most recently.
        XCTAssertEqual(reader.records[0].text, "world")
        XCTAssertEqual(reader.records[1].text, "hello")
    }

    // MARK: - Orphan detection

    func testOrphanedHistoryWithoutKeyThrowsDecryptionError() throws {
        // Set up a real encrypted file under the temp dir, then nuke the key
        // from the test Keychain so the next load() sees the orphan state.
        let writer = makeStore()
        try writer.append(makeRecord(text: "orphan"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: historyFile.path))

        try Keychain.delete(account: .historyEncryptionKey, service: testKeychainService)

        let reader = makeStore()
        XCTAssertThrowsError(try reader.load()) { error in
            guard case HistoryStore.HistoryError.decryptionFailed = error else {
                XCTFail("expected .decryptionFailed for orphan history, got \(error)")
                return
            }
        }
    }

    // MARK: - Key length validation

    func testCorruptedKeyLengthThrowsDecryptionError() throws {
        // Plant a wrong-sized "encryption key" in the test Keychain BEFORE
        // any history exists. HistoryStore must reject it instead of using
        // the corrupted bytes.
        let badKey = Data(repeating: 0x42, count: 16) // 16 bytes, not 32
        try Keychain.saveData(badKey, account: .historyEncryptionKey, service: testKeychainService)

        let store = makeStore()
        XCTAssertThrowsError(try store.append(makeRecord())) { error in
            guard case HistoryStore.HistoryError.decryptionFailed = error else {
                XCTFail("expected .decryptionFailed for bad key length, got \(error)")
                return
            }
        }
    }

    // MARK: - Pruning

    func testPruneByRetentionDropsAgedRecords() throws {
        let oldDate = Date().addingTimeInterval(-30 * 86_400) // 30 days ago
        let recentDate = Date().addingTimeInterval(-2 * 86_400) // 2 days ago

        // Retention = 7 days; old should drop, recent should stay.
        let store = makeStore(retentionDays: 7)
        try store.append(makeRecord(text: "old", at: oldDate))
        try store.append(makeRecord(text: "recent", at: recentDate))

        // Force a re-prune through pruneNow().
        try store.pruneNow()
        XCTAssertEqual(store.records.count, 1)
        XCTAssertEqual(store.records.first?.text, "recent")
    }

    func testPruneByMaxEntriesKeepsNewest() throws {
        let store = makeStore(maxEntries: 3)
        // Append in time order; each append inserts at head, then prune trims tail.
        for i in 1...10 {
            try store.append(makeRecord(text: "msg-\(i)"))
        }
        XCTAssertEqual(store.records.count, 3)
        // Newest 3 are msg-10, msg-9, msg-8 (head-of-list = most recent).
        XCTAssertEqual(store.records.map(\.text), ["msg-10", "msg-9", "msg-8"])
    }

    func testPruneRetentionZeroMeansForever() throws {
        let oldDate = Date().addingTimeInterval(-365 * 86_400) // 1 year ago
        let store = makeStore(retentionDays: 0, maxEntries: 100)
        try store.append(makeRecord(text: "ancient", at: oldDate))
        try store.pruneNow()
        // Retention 0 = keep forever, max-entries 100 = no cap pressure.
        XCTAssertEqual(store.records.count, 1)
    }

    // MARK: - Clear

    func testClearRemovesFileAndRecords() throws {
        let store = makeStore()
        try store.append(makeRecord(text: "ephemeral"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: historyFile.path))

        try store.clear()
        XCTAssertTrue(store.records.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: historyFile.path))
    }

    func testClearOnEmptyDirIsNoOp() throws {
        let store = makeStore()
        XCTAssertNoThrow(try store.clear())
        XCTAssertTrue(store.records.isEmpty)
    }
}
