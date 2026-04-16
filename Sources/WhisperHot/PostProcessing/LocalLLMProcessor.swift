import Foundation

/// Runs text post-processing locally via llama.cpp CLI subprocess.
/// Fully offline — no network calls. Requires the user to install
/// llama.cpp and download a GGUF model.
///
/// Usage: same interface as LLMPostProcessor.process() but runs
/// llama-cli as a subprocess instead of making HTTP calls.
final class LocalLLMProcessor: @unchecked Sendable {
    private let binaryPath: String
    private let modelPath: String

    init(binaryPath: String, modelPath: String) {
        self.binaryPath = binaryPath
        self.modelPath = modelPath
    }

    /// Process text through local LLM. Constructs a prompt from the
    /// preset's system prompt + user text, runs llama-cli, returns
    /// the cleaned text.
    func process(text: String, options: PostProcessingOptions) async throws -> String {
        guard FileManager.default.isExecutableFile(atPath: binaryPath) else {
            throw PostProcessingError.missingAPIKey // reuse error type
        }
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw PostProcessingError.missingAPIKey
        }

        let systemPrompt = options.preset.systemPrompt(custom: options.customPrompt)
        let fullPrompt = """
        <|system|>
        \(systemPrompt)
        <|user|>
        \(text)
        <|assistant|>
        """

        return try await runLlama(prompt: fullPrompt)
    }

    private func runLlama(prompt: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: (binaryPath as NSString).expandingTildeInPath)
            process.arguments = [
                "-m", (modelPath as NSString).expandingTildeInPath,
                "--prompt-cache-all",
                "-n", "512",
                "--temp", "0.1",
                "--no-display-prompt",
                "-f", "/dev/stdin"   // read prompt from stdin (avoids argv size limits)
            ]

            let stdinPipe = Pipe()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardInput = stdinPipe
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            // EOF-tracking via DispatchGroup (same pattern as LocalWhisperProvider)
            let drainGroup = DispatchGroup()
            let stdoutBuffer = DataBuffer()
            let stderrBuffer = DataBuffer()

            drainGroup.enter()
            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    drainGroup.leave()
                } else {
                    stdoutBuffer.append(data)
                }
            }

            drainGroup.enter()
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    drainGroup.leave()
                } else {
                    stderrBuffer.append(data)
                }
            }

            process.terminationHandler = { proc in
                // Wait for all pipe data to be read before accessing buffers
                drainGroup.wait()

                if proc.terminationStatus != 0 {
                    let errData = stderrBuffer.snapshot()
                    let errStr = String(data: errData, encoding: .utf8) ?? "unknown error"
                    let truncated = errStr.count > 300 ? String(errStr.prefix(300)) + "..." : errStr
                    continuation.resume(throwing: PostProcessingError.networkFailure(
                        underlying: NSError(domain: "LocalLLM", code: Int(proc.terminationStatus),
                                           userInfo: [NSLocalizedDescriptionKey: "llama-cli failed: \(truncated)"])
                    ))
                    return
                }

                let output = String(data: stdoutBuffer.snapshot(), encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if output.isEmpty {
                    continuation.resume(throwing: PostProcessingError.emptyResponse)
                } else {
                    continuation.resume(returning: output)
                }
            }

            do {
                try process.run()
                // Write prompt to stdin and close
                if let data = prompt.data(using: .utf8) {
                    stdinPipe.fileHandleForWriting.write(data)
                }
                stdinPipe.fileHandleForWriting.closeFile()
            } catch {
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                process.terminationHandler = nil
                continuation.resume(throwing: PostProcessingError.networkFailure(underlying: error))
            }
        }
    }
}

/// Thread-safe byte accumulator (same pattern as WhisperInstaller).
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
