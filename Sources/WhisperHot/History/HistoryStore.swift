import CryptoKit
import Foundation

/// Append-only transcript history persisted to
/// `~/Library/Application Support/WhisperHot/history.bin` and encrypted
/// at rest with AES-GCM. The symmetric key lives in the macOS Keychain
/// (account `.historyEncryptionKey`), generated lazily on first use.
///
/// Off by default — MenuBarController only appends records when
/// `Preferences.historyEnabled` is true.
@MainActor
final class HistoryStore {
    enum HistoryError: LocalizedError {
        case encryptionFailed(underlying: Error)
        case decryptionFailed(underlying: Error)
        case storageWriteFailed(underlying: Error)
        case storageReadFailed(underlying: Error)
        case decodingFailed(underlying: Error)

        var errorDescription: String? {
            switch self {
            case .encryptionFailed(let e): return "Could not encrypt history: \(e.localizedDescription)"
            case .decryptionFailed(let e): return "Could not decrypt history: \(e.localizedDescription)"
            case .storageWriteFailed(let e): return "Could not write history file: \(e.localizedDescription)"
            case .storageReadFailed(let e): return "Could not read history file: \(e.localizedDescription)"
            case .decodingFailed(let e): return "Could not decode history: \(e.localizedDescription)"
            }
        }
    }

    private(set) var records: [TranscriptRecord] = []
    private var loaded = false

    private let fileManager = FileManager.default
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: - Paths

    /// Throws if the Application Support directory cannot be resolved or
    /// our subdirectory cannot be created. Surfaces the real error to
    /// callers instead of silently degrading into a later read/write
    /// failure with no context.
    private func resolveStorageDirectory() throws -> URL {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = base.appendingPathComponent("WhisperHot", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func resolveStorageURL() throws -> URL {
        try resolveStorageDirectory().appendingPathComponent("history.bin")
    }

    /// Non-throwing convenience for code paths that can tolerate "no path"
    /// (e.g., the encryption-key orphan check).
    private var storageURLIfAvailable: URL? {
        try? resolveStorageURL()
    }

    // MARK: - Public API

    func loadIfNeeded() throws {
        guard !loaded else { return }
        try load()
    }

    func load() throws {
        let url: URL
        do {
            url = try resolveStorageURL()
        } catch {
            throw HistoryError.storageReadFailed(underlying: error)
        }
        guard fileManager.fileExists(atPath: url.path) else {
            records = []
            loaded = true
            return
        }
        let ciphertext: Data
        do {
            ciphertext = try Data(contentsOf: url)
        } catch {
            throw HistoryError.storageReadFailed(underlying: error)
        }
        let key = try encryptionKey()
        let plaintext: Data
        do {
            let box = try AES.GCM.SealedBox(combined: ciphertext)
            plaintext = try AES.GCM.open(box, using: key)
        } catch {
            throw HistoryError.decryptionFailed(underlying: error)
        }
        do {
            records = try decoder.decode([TranscriptRecord].self, from: plaintext)
        } catch {
            throw HistoryError.decodingFailed(underlying: error)
        }
        loaded = true
    }

    /// Inserts `record` at the head (newest first), prunes by retention +
    /// max-entries policy, and persists the new state atomically.
    func append(_ record: TranscriptRecord) throws {
        try loadIfNeeded()
        records.insert(record, at: 0)
        prune()
        try persist()
    }

    func clear() throws {
        records.removeAll()
        loaded = true
        let url: URL
        do {
            url = try resolveStorageURL()
        } catch {
            throw HistoryError.storageWriteFailed(underlying: error)
        }
        guard fileManager.fileExists(atPath: url.path) else { return }
        do {
            try fileManager.removeItem(at: url)
        } catch {
            throw HistoryError.storageWriteFailed(underlying: error)
        }
    }

    func pruneNow() throws {
        try loadIfNeeded()
        let before = records.count
        prune()
        if records.count != before {
            try persist()
        }
    }

    // MARK: - Internals

    private func prune() {
        // Age cutoff
        let retentionDays = Preferences.historyRetentionDays
        if retentionDays > 0 {
            let cutoff = Date().addingTimeInterval(-Double(retentionDays) * 86_400)
            records = records.filter { $0.createdAt >= cutoff }
        }
        // Size cap
        let maxEntries = max(Preferences.historyMaxEntries, 1)
        if records.count > maxEntries {
            records = Array(records.prefix(maxEntries))
        }
    }

    private func persist() throws {
        let url: URL
        do {
            url = try resolveStorageURL()
        } catch {
            throw HistoryError.storageWriteFailed(underlying: error)
        }
        let plaintext: Data
        do {
            plaintext = try encoder.encode(records)
        } catch {
            throw HistoryError.storageWriteFailed(underlying: error)
        }
        let key = try encryptionKey()
        let ciphertext: Data
        do {
            let sealed = try AES.GCM.seal(plaintext, using: key)
            guard let combined = sealed.combined else {
                throw NSError(
                    domain: "WhisperHot.HistoryStore",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "AES.GCM returned nil combined payload"]
                )
            }
            ciphertext = combined
        } catch {
            throw HistoryError.encryptionFailed(underlying: error)
        }
        do {
            try ciphertext.write(to: url, options: [.atomic])
        } catch {
            throw HistoryError.storageWriteFailed(underlying: error)
        }
    }

    /// Loads the AES-GCM key from the Keychain, generating + storing a new
    /// 256-bit random key ONLY on a genuine first-use path (Keychain empty
    /// AND history.bin not yet on disk). Any other state — Keychain read
    /// error, length mismatch, or orphaned history.bin with a missing key
    /// — is surfaced so we never silently replace a key that would leave
    /// existing ciphertext un-decryptable.
    private func encryptionKey() throws -> SymmetricKey {
        // Step 1: try to fetch the existing key. Distinguish between
        // "item genuinely not there" and "Keychain hiccuped".
        let existing: Data?
        do {
            existing = try Keychain.readData(account: .historyEncryptionKey)
        } catch Keychain.KeychainError.itemNotFound {
            existing = nil
        } catch {
            throw HistoryError.encryptionFailed(underlying: error)
        }

        // Step 2: if we got a key back, validate length and return it.
        if let existing {
            guard existing.count == 32 else {
                throw HistoryError.decryptionFailed(
                    underlying: NSError(
                        domain: "WhisperHot.HistoryStore",
                        code: -3,
                        userInfo: [
                            NSLocalizedDescriptionKey: "History encryption key is \(existing.count) bytes; expected 32. Use Settings → History → Clear all to reset."
                        ]
                    )
                )
            }
            return SymmetricKey(data: existing)
        }

        // Step 3: no key in the Keychain. Safe to mint a new one ONLY if
        // history.bin also does not exist. Otherwise the existing
        // ciphertext would be orphaned forever.
        if let url = storageURLIfAvailable, fileManager.fileExists(atPath: url.path) {
            throw HistoryError.decryptionFailed(
                underlying: NSError(
                    domain: "WhisperHot.HistoryStore",
                    code: -4,
                    userInfo: [
                        NSLocalizedDescriptionKey: "History encryption key is missing from the Keychain but history.bin exists. The existing history cannot be decrypted. Use Settings → History → Clear all to delete it and start fresh."
                    ]
                )
            )
        }

        // Step 4: genuine first use. Mint, persist, return.
        let newKey = SymmetricKey(size: .bits256)
        let keyData = newKey.withUnsafeBytes { Data($0) }
        precondition(keyData.count == 32, "SymmetricKey size: .bits256 must yield 32 bytes")
        do {
            try Keychain.saveData(keyData, account: .historyEncryptionKey)
        } catch {
            throw HistoryError.encryptionFailed(underlying: error)
        }
        return newKey
    }
}
