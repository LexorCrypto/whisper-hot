import Foundation

/// Thread-safe byte accumulator for pipe drain handlers.
private final class DataBuffer: @unchecked Sendable {
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

/// Manages one-click installation of whisper.cpp binary (via Homebrew)
/// and GGML model download (from HuggingFace).
///
/// Usage:
///   1. Check status via `WhisperInstaller.status`
///   2. Call `install()` to run brew install + model download
///   3. Observe `progress` and `status` for UI updates
///
/// All state is @MainActor so SwiftUI can bind directly.
@MainActor
final class WhisperInstaller: ObservableObject {
    enum Status: Equatable {
        case notInstalled
        case installing(step: String)
        case downloading(progress: Double) // 0.0...1.0
        case installed
        case failed(message: String)
    }

    @Published private(set) var status: Status = .notInstalled

    private let modelsDir: URL
    private let defaultModelName = "ggml-base.bin"
    private let modelURL = URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin")!

    /// Known Homebrew binary paths (ARM64 + Intel fallback)
    private let brewPaths = [
        "/opt/homebrew/bin/brew",
        "/usr/local/bin/brew"
    ]

    /// Known whisper-cli binary paths after Homebrew install
    private let whisperPaths = [
        "/opt/homebrew/bin/whisper-cli",
        "/usr/local/bin/whisper-cli",
        "/opt/homebrew/bin/whisper",
        "/usr/local/bin/whisper"
    ]

    private var downloadTask: URLSessionDownloadTask?

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        modelsDir = appSupport.appendingPathComponent("WhisperHot/models", isDirectory: true)
        refreshStatus()
    }

    // MARK: - Public

    /// Refresh installation status by checking filesystem.
    func refreshStatus() {
        if let _ = findWhisperBinary(), modelExists() {
            status = .installed
            syncPreferences()
        } else {
            status = .notInstalled
        }
    }

    /// Whether local whisper is fully configured and ready to use.
    var isReady: Bool {
        if case .installed = status { return true }
        return false
    }

    /// Run full installation: Homebrew install + model download.
    func install() async {
        // Guard against double-tap
        switch status {
        case .installing, .downloading: return
        default: break
        }

        // Step 1: Check/install whisper-cli via Homebrew
        if findWhisperBinary() == nil {
            guard let brewPath = findBrew() else {
                status = .failed(message: L10n.lang == .ru
                    ? "Homebrew не найден. Установите (2-5 мин): /bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
                    : "Homebrew not found. Install (2-5 min): /bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"")
                return
            }

            status = .installing(step: L10n.lang == .ru ? "Установка whisper-cpp через Homebrew (2-5 мин)..." : "Installing whisper-cpp via Homebrew (2-5 min)...")

            let success = await runBrew(brewPath: brewPath)
            if !success {
                // status already set by runBrew
                return
            }
        }

        // Step 2: Download model if not present
        if !modelExists() {
            status = .downloading(progress: 0)
            let success = await downloadModel()
            if !success {
                return
            }
        }

        // Step 3: Verify and sync
        if let _ = findWhisperBinary(), modelExists() {
            syncPreferences()
            status = .installed
        } else {
            status = .failed(message: L10n.lang == .ru
                ? "Установка завершена, но файлы не найдены"
                : "Installation finished but files not found")
        }
    }

    /// Cancel in-progress download.
    func cancel() {
        downloadTask?.cancel()
        downloadTask = nil
        status = .notInstalled
    }

    // MARK: - Binary detection

    private func findBrew() -> String? {
        brewPaths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func findWhisperBinary() -> String? {
        // Check managed path first, then system Homebrew paths
        whisperPaths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    // MARK: - Model

    private func modelPath() -> URL {
        modelsDir.appendingPathComponent(defaultModelName)
    }

    private func modelExists() -> Bool {
        FileManager.default.fileExists(atPath: modelPath().path)
    }

    // MARK: - Homebrew install

    private func runBrew(brewPath: String) async -> Bool {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: brewPath)
            process.arguments = ["install", "whisper-cpp"]
            process.environment = ProcessInfo.processInfo.environment

            // Drain pipes asynchronously to prevent buffer-full deadlock.
            let stderrPipe = Pipe()
            let stderrBuffer = DataBuffer()
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty { stderrBuffer.append(data) }
            }
            process.standardError = stderrPipe

            let stdoutPipe = Pipe()
            stdoutPipe.fileHandleForReading.readabilityHandler = { _ in
                // discard stdout but drain it
            }
            process.standardOutput = stdoutPipe

            // Set termination handler BEFORE run() to avoid race
            // if the process exits very quickly.
            process.terminationHandler = { proc in
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                let success = proc.terminationStatus == 0
                if !success {
                    let errData = stderrBuffer.snapshot()
                    let errStr = String(data: errData, encoding: .utf8) ?? "unknown error"
                    let truncated = errStr.count > 300 ? String(errStr.prefix(300)) + "..." : errStr
                    Task { @MainActor in
                        self.status = .failed(message: "brew install whisper-cpp failed: \(truncated)")
                    }
                }
                continuation.resume(returning: success)
            }

            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                Task { @MainActor in
                    self.status = .failed(message: "brew install failed: \(error.localizedDescription)")
                }
                continuation.resume(returning: false)
            }
        }
    }

    // MARK: - Model download

    private func downloadModel() async -> Bool {
        do {
            try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        } catch {
            status = .failed(message: "Cannot create models directory: \(error.localizedDescription)")
            return false
        }

        let destination = modelPath()

        // Use URLSession delegate for progress
        return await withCheckedContinuation { continuation in
            let session = URLSession(
                configuration: .default,
                delegate: DownloadDelegate(
                    destination: destination,
                    onProgress: { [weak self] progress in
                        Task { @MainActor in
                            self?.status = .downloading(progress: progress)
                        }
                    },
                    onComplete: { [weak self] error in
                        Task { @MainActor in
                            if let error {
                                self?.status = .failed(message: error.localizedDescription)
                                continuation.resume(returning: false)
                            } else {
                                continuation.resume(returning: true)
                            }
                        }
                    }
                ),
                delegateQueue: nil
            )
            let task = session.downloadTask(with: modelURL)
            self.downloadTask = task
            task.resume()
        }
    }

    // MARK: - Preferences sync

    private func syncPreferences() {
        if let binary = findWhisperBinary() {
            UserDefaults.standard.set(binary, forKey: Preferences.Key.localWhisperBinaryPath)
        }
        let model = modelPath().path
        if FileManager.default.fileExists(atPath: model) {
            UserDefaults.standard.set(model, forKey: Preferences.Key.localWhisperModelPath)
        }
    }
}

// MARK: - Download delegate

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    private let destination: URL
    private let onProgress: (Double) -> Void
    private let onComplete: (Error?) -> Void

    init(destination: URL, onProgress: @escaping (Double) -> Void, onComplete: @escaping (Error?) -> Void) {
        self.destination = destination
        self.onProgress = onProgress
        self.onComplete = onComplete
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Validate HTTP response before moving file
        if let http = downloadTask.response as? HTTPURLResponse,
           !(200..<300).contains(http.statusCode) {
            onComplete(NSError(domain: "WhisperInstaller", code: http.statusCode,
                               userInfo: [NSLocalizedDescriptionKey: "Download failed: HTTP \(http.statusCode)"]))
            return
        }

        // Validate file size (ggml-base.bin should be ~142MB, reject < 1MB)
        let attrs = try? FileManager.default.attributesOfItem(atPath: location.path)
        let size = (attrs?[.size] as? Int64) ?? 0
        if size < 1_000_000 {
            onComplete(NSError(domain: "WhisperInstaller", code: -1,
                               userInfo: [NSLocalizedDescriptionKey: "Downloaded file too small (\(size) bytes), likely corrupt"]))
            return
        }

        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
            onComplete(nil)
        } catch {
            onComplete(error)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        onProgress(progress)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            // Don't report cancel as failure
            if (error as NSError).code == NSURLErrorCancelled { return }
            onComplete(error)
        }
    }
}
