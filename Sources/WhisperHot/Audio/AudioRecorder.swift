import AVFoundation
import Foundation
import os

final class AudioRecorder: NSObject {
    private struct ActiveSession: @unchecked Sendable {
        /// Monotonic ID assigned at session-creation time. Stale tap
        /// callbacks from a previous session capture this session strongly,
        /// so they end up writing to their own audioFile/writerQueue —
        /// they never leak into a successor session's WAV. The ID is kept
        /// for diagnostics and so `stopRecording()` can log which session
        /// it's draining.
        let id: UInt64
        let converter: AVAudioConverter
        let audioFile: AVAudioFile
        let inputFormat: AVAudioFormat
        let outputURL: URL

        /// Per-session tap-callback synchronization. Created fresh for each
        /// `startRecording()` so an abandoned session whose callback
        /// wedged forever (the `resetAfterWake()` motivating case) cannot
        /// poison the next session's `stopRecording()`.
        let tapGroup: DispatchGroup

        /// Per-session serial disk-I/O queue. Same isolation rationale:
        /// a stuck `audioFile.write` block on a previous queue does not
        /// block the next session's drain.
        let writerQueue: DispatchQueue
    }

    /// Monotonic counter for session IDs. Main-thread only; incremented in
    /// `startRecording()` before publishing the new `ActiveSession` into
    /// `sessionLock`.
    private var sessionCounter: UInt64 = 0

    /// Main-thread only.
    private(set) var isRecording = false

    /// Thread-safe snapshot of the most recent RMS value sampled from the tap.
    var currentRMS: Float {
        rmsLock.withLock { $0 }
    }

    /// Fired on the main queue when recording stops unexpectedly (config change, error).
    var onAutoStop: (() -> Void)?

    /// Fired on the main queue when a tap/write error occurs during recording.
    /// The recording continues but the audio may be incomplete.
    var onRecordingError: ((String) -> Void)?

    private let engine = AVAudioEngine()

    // OSAllocatedUnfairLock is the canonical macOS fast lock with priority inheritance.
    // Safe for the real-time audio thread: no stalls from priority inversion the way
    // pthread_mutex / NSLock could cause.
    private let sessionLock = OSAllocatedUnfairLock<ActiveSession?>(initialState: nil)
    private let rmsLock = OSAllocatedUnfairLock<Float>(initialState: 0)

    // Per-session DispatchGroup / DispatchQueue live on `ActiveSession` —
    // see the comments on those fields for why they MUST be per-session
    // and not shared across recordings. Sharing them was the bug
    // `resetAfterWake()` would otherwise create: a wedged tap callback or
    // stuck writer block from session N would poison session N+1's
    // `stopRecording()` drain.

    private var configurationObserver: NSObjectProtocol?

    private let outputFormat: AVAudioFormat = {
        AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: true
        )!
    }()

    deinit {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        removeConfigurationObserver()
    }

    // MARK: - Lifecycle (main thread only)

    func startRecording() throws -> URL {
        dispatchPrecondition(condition: .onQueue(.main))

        guard !isRecording else {
            throw AudioError.alreadyRecording
        }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw AudioError.microphoneAccessDenied
        }

        let url = try Self.makeOutputURL()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            try? FileManager.default.removeItem(at: url)
            throw AudioError.invalidInputFormat
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            try? FileManager.default.removeItem(at: url)
            throw AudioError.converterUnavailable
        }

        let file: AVAudioFile
        do {
            file = try AVAudioFile(
                forWriting: url,
                settings: [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: 16_000.0,
                    AVNumberOfChannelsKey: 1,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsBigEndianKey: false,
                    AVLinearPCMIsNonInterleaved: false
                ],
                commonFormat: .pcmFormatInt16,
                interleaved: true
            )
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }

        sessionCounter &+= 1
        let myID = sessionCounter
        let newSession = ActiveSession(
            id: myID,
            converter: converter,
            audioFile: file,
            inputFormat: inputFormat,
            outputURL: url,
            tapGroup: DispatchGroup(),
            writerQueue: DispatchQueue(
                label: "com.aleksejsupilin.WhisperHot.audio.writer.\(myID)",
                qos: .userInitiated
            )
        )

        sessionLock.withLock { $0 = newSession }

        // The tap closure captures the session strongly so that even if a
        // later `resetAfterWake()` (or successor `startRecording()`) clears
        // the lock-protected slot, an in-flight callback still has its own
        // session and writes to its own audioFile via its own writerQueue.
        // No leakage into the next session's WAV.
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self, session = newSession] buffer, _ in
            self?.processTapBuffer(buffer, session: session)
        }

        installConfigurationObserver()

        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            newSession.tapGroup.wait()
            removeConfigurationObserver()
            sessionLock.withLock { $0 = nil }
            try? FileManager.default.removeItem(at: url)
            throw AudioError.engineStartFailed(underlying: error)
        }

        isRecording = true
        return url
    }

    @discardableResult
    func stopRecording() throws -> URL {
        dispatchPrecondition(condition: .onQueue(.main))

        guard isRecording else {
            throw AudioError.notRecording
        }

        // Teardown ordering:
        // 1. removeTap  — ask AVAudioEngine to stop scheduling new tap callbacks.
        // 2. Capture the live session and clear the slot — the writer queue
        //    and tap group we drain below belong to THIS session.
        // 3. session.tapGroup.wait  — explicitly wait for any tap callbacks
        //    that are already in flight (or whose input buffer was already
        //    in the pipeline before removeTap). Since the group is
        //    per-session, a wedged callback on a previously abandoned
        //    session cannot poison this drain.
        // 4. session.writerQueue.sync{}  — drain the serial writer queue;
        //    all `writerQueue.async` calls the taps made were enqueued
        //    before their `tapGroup.leave()`, so they are now guaranteed
        //    to run before this marker.
        // 5. Drop the captured session — now nothing references the
        //    AVAudioFile besides the local `finished`, so returning
        //    deallocates it and flushes the WAV header.
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        removeConfigurationObserver()

        let finished: ActiveSession? = sessionLock.withLock { slot in
            let captured = slot
            slot = nil
            return captured
        }

        guard let finished else {
            isRecording = false
            throw AudioError.notRecording
        }

        finished.tapGroup.wait()
        finished.writerQueue.sync { }

        rmsLock.withLock { $0 = 0 }
        isRecording = false
        return finished.outputURL
    }

    // MARK: - Tap processing (real-time audio thread)

    private func processTapBuffer(_ buffer: AVAudioPCMBuffer, session: ActiveSession) {
        session.tapGroup.enter()
        defer { session.tapGroup.leave() }

        // A callback that was queued by AVAudioEngine BEFORE removeTap can
        // still fire after `stopRecording()` (or `resetAfterWake()`) has
        // already cleared the slot. If we let those late callbacks write
        // through, they would append to a WAV that the caller has already
        // handed off to transcription — corrupting the file mid-read or
        // landing data after the drain marker that `stopRecording()`
        // explicitly waited on. Bail before doing any work, including
        // RMS updates and writer-queue enqueues.
        let isLive = sessionLock.withLock { $0?.id == session.id }
        guard isLive else { return }

        let rms = Self.computeRMS(buffer: buffer)
        rmsLock.withLock { $0 = rms }

        let ratio = outputFormat.sampleRate / session.inputFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 1024)
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            return
        }

        var inputConsumed = false
        var error: NSError?
        let status = session.converter.convert(to: outBuffer, error: &error) { _, outStatus in
            if inputConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputConsumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        guard status != .error, error == nil else {
            NSLog("WhisperHot: converter error")
            let msg = error?.localizedDescription ?? "unknown converter error"
            DispatchQueue.main.async { [weak self] in self?.onRecordingError?(msg) }
            return
        }

        // The converted buffer is handed off to the session's serial writer
        // queue. Because writerQueue.async is called before tapGroup.leave(),
        // stopRecording's session.tapGroup.wait() guarantees no new writes
        // will be enqueued after it returns.
        let file = session.audioFile
        session.writerQueue.async {
            do {
                try file.write(from: outBuffer)
            } catch {
                NSLog("WhisperHot: audio write error")
                let msg = error.localizedDescription
                DispatchQueue.main.async { [weak self] in self?.onRecordingError?(msg) }
            }
        }
    }

    // MARK: - Sleep / wake recovery

    /// Best-effort, non-blocking reset of any in-flight session. Designed
    /// for the sleep/wake recovery path: after the kernel suspends the
    /// process, AVAudioEngine can come back in a zombie state where a
    /// queued tap callback is wedged or `engine.stop()` is in a partial
    /// teardown. The normal `stopRecording()` waits on `tapGroup` and
    /// `writerQueue` from the main thread to flush the WAV cleanly — but
    /// if either queue is wedged, that wait deadlocks the menu bar app.
    /// This method NEVER waits on those queues. A still-in-flight tap
    /// closure already captured the `ActiveSession` strongly, so it can
    /// keep writing to the WAV until ARC reclaims it; we just need the
    /// engine and the lock-protected slot back to a sane state so the
    /// next `startRecording()` attempt doesn't hit `alreadyRecording`.
    ///
    /// Safe to call when no session is active (idempotent no-op). Caller
    /// is responsible for treating any orphan WAV as discardable; the
    /// retention sweeper will clean it up.
    func resetAfterWake() {
        dispatchPrecondition(condition: .onQueue(.main))
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        removeConfigurationObserver()
        let captured: ActiveSession? = sessionLock.withLock { slot in
            let prior = slot
            slot = nil
            return prior
        }
        rmsLock.withLock { $0 = 0 }
        isRecording = false
        if let url = captured?.outputURL {
            NSLog("WhisperHot: audio recorder reset, orphaned WAV %@", url.path)
        }
    }

    // MARK: - Configuration observer

    private func installConfigurationObserver() {
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            NSLog("WhisperHot: audio configuration changed; stopping recording")
            _ = try? self.stopRecording()
            self.onAutoStop?()
        }
    }

    private func removeConfigurationObserver() {
        if let obs = configurationObserver {
            NotificationCenter.default.removeObserver(obs)
            configurationObserver = nil
        }
    }

    // MARK: - Helpers

    private static func makeOutputURL() throws -> URL {
        let fm = FileManager.default
        let caches = try fm.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = caches.appendingPathComponent("WhisperHot/recordings", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = UUID().uuidString + ".wav"
        return dir.appendingPathComponent(name)
    }

    private static func computeRMS(buffer: AVAudioPCMBuffer) -> Float {
        guard buffer.format.commonFormat == .pcmFormatFloat32,
              let channelData = buffer.floatChannelData else {
            return 0
        }
        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0, channelCount > 0 else { return 0 }

        var sum: Float = 0
        for ch in 0..<channelCount {
            let ptr = channelData[ch]
            for i in 0..<frameLength {
                let sample = ptr[i]
                sum += sample * sample
            }
        }
        let meanSquare = sum / Float(frameLength * channelCount)
        return sqrtf(meanSquare)
    }
}
