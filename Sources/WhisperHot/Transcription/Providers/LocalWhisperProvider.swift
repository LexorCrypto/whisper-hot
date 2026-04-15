import Foundation

/// Thread-safe byte accumulator used by the subprocess pipe drain handlers.
/// Wrapped in a class so the async drain closures can mutate a shared buffer
/// without tripping Swift 6 Sendable captures on a local `var Data`.
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

/// Runs whisper.cpp's CLI binary as a subprocess on the raw WAV we already
/// wrote to disk. Fully offline — no bytes leave the user's machine.
///
/// The user must install whisper.cpp (e.g. `brew install whisper-cpp` or
/// build from source) and download a GGML model, then point Preferences
/// at both the binary and the model file via Settings.
final class LocalWhisperProvider: TranscriptionService {
    private let binaryPath: String
    private let modelPath: String

    init(binaryPath: String, modelPath: String) {
        self.binaryPath = binaryPath
        self.modelPath = modelPath
    }

    func transcribe(audioURL: URL, options: TranscriptionOptions) async throws -> TranscriptionResult {
        guard !binaryPath.isEmpty, FileManager.default.isExecutableFile(atPath: binaryPath) else {
            throw TranscriptionError.localBinaryNotFound(path: binaryPath)
        }
        guard !modelPath.isEmpty, FileManager.default.isReadableFile(atPath: modelPath) else {
            throw TranscriptionError.localModelNotFound(path: modelPath)
        }

        // Sanity-check the audio file — keeps error messages consistent
        // with the cloud providers even though we don't upload anything.
        guard FileManager.default.isReadableFile(atPath: audioURL.path) else {
            throw TranscriptionError.audioFileUnreadable(
                underlying: NSError(
                    domain: "WhisperHot.LocalWhisperProvider",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Audio file not readable"]
                )
            )
        }

        let binaryPathCopy = binaryPath
        let modelPathCopy = modelPath

        var arguments: [String] = [
            "-m", modelPathCopy,
            "-f", audioURL.path,
            "-nt",          // no timestamps — just the transcript text
            "-np"           // no print progress / non-essential output
        ]
        if options.language != .auto {
            arguments.append(contentsOf: ["-l", options.language.rawValue])
        }
        if let prompt = options.prompt, !prompt.isEmpty {
            arguments.append(contentsOf: ["--prompt", prompt])
        }
        let finalArguments = arguments

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<TranscriptionResult, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: binaryPathCopy)
            process.arguments = finalArguments

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            let stdoutBuffer = DataBuffer()
            let stderrBuffer = DataBuffer()

            // Drain both pipes CONCURRENTLY with the child process so its
            // stdout/stderr can never saturate the kernel pipe buffer and
            // deadlock it mid-transcribe. readabilityHandler fires on a
            // private Dispatch queue every time data arrives (or an empty
            // chunk signals EOF, which is our cue to clear the handler and
            // leave the drain group).
            let drainGroup = DispatchGroup()
            drainGroup.enter()
            drainGroup.enter()

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                    drainGroup.leave()
                    return
                }
                stdoutBuffer.append(chunk)
            }
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                    drainGroup.leave()
                    return
                }
                stderrBuffer.append(chunk)
            }

            process.terminationHandler = { proc in
                // Block here until both pipes hit EOF. drainGroup.wait runs
                // on the termination-handler's private queue, which is
                // independent of the readabilityHandler queues, so this
                // cannot deadlock.
                drainGroup.wait()

                let outData = stdoutBuffer.snapshot()
                let errData = stderrBuffer.snapshot()

                guard proc.terminationStatus == 0 else {
                    let errText = String(data: errData, encoding: .utf8) ?? "<unreadable stderr>"
                    continuation.resume(
                        throwing: TranscriptionError.localProcessFailed(
                            exitCode: proc.terminationStatus,
                            stderr: errText
                        )
                    )
                    return
                }

                let stdoutText = String(data: outData, encoding: .utf8) ?? ""
                let text = stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else {
                    continuation.resume(throwing: TranscriptionError.emptyTranscript)
                    return
                }

                let modelName = URL(fileURLWithPath: modelPathCopy).lastPathComponent
                continuation.resume(
                    returning: TranscriptionResult(
                        text: text,
                        providerModel: "local/\(modelName)"
                    )
                )
            }

            do {
                try process.run()
            } catch {
                // Tear down the pipe drains we just set up so they can't fire
                // after we've resumed the continuation with the failure.
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(
                    throwing: TranscriptionError.localProcessFailed(
                        exitCode: -1,
                        stderr: error.localizedDescription
                    )
                )
            }
        }
    }
}
