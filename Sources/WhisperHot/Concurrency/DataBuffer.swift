import Foundation

/// Thread-safe byte accumulator used by subprocess pipe drain handlers.
/// Wraps a `Data` value in NSLock so that `readabilityHandler` callbacks
/// (which fire on private dispatch queues) can append concurrently and the
/// `terminationHandler` can snapshot the result without tripping Swift 6
/// Sendable captures on a local `var Data`.
final class DataBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func append(_ chunk: Data) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(chunk)
    }

    func snapshot() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
