import AVFoundation
import CoreAudio
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

        /// Tap-callback synchronization. Created fresh for each
        /// `startRecording()` so an abandoned session whose callback
        /// wedged forever (the `resetAfterWake()` motivating case) cannot
        /// poison the next session's `stopRecording()`. A successor created
        /// by a mid-recording device switch deliberately INHERITS the group:
        /// it is the same take, and the old tap is already drained by then.
        let tapGroup: DispatchGroup

        /// Serial disk-I/O queue. Same isolation rationale: a stuck
        /// `audioFile.write` block on a previous queue does not block the
        /// next session's drain. Inherited across a device switch, because
        /// both sessions write to the same `audioFile` and their writes MUST
        /// stay ordered on one queue.
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

    /// Rebuilt whenever the system's default input device moves out from under
    /// it — see `rebindEngineToCurrentInputDeviceIfNeeded()`. A `var`, not a
    /// `let`, for exactly that reason.
    private var engine = AVAudioEngine()

    /// The default input device that was current when `engine` was built.
    /// Main-thread only. `AVAudioEngine` cannot be asked which microphone it
    /// is on — it runs on a private aggregate device — so this is how we
    /// detect that the microphone changed under a live engine.
    private var engineInputDeviceID = AudioRecorder.currentDefaultInputDeviceID()

    /// True while a device switch is in flight (notification seen, engine not
    /// yet re-bound). Coalesces the burst of configuration-change
    /// notifications a single Bluetooth connect produces.
    private var isSwitchingDevice = false

    /// Bumped by every recording-lifecycle transition and by each new switch
    /// sequence; a queued retry that no longer matches is dropped.
    private var deviceSwitchGeneration: UInt64 = 0

    /// A Bluetooth input is not usable the instant the notification arrives:
    /// the device appears, the profile negotiates, and only then does the HAL
    /// report a non-zero format. Retry on a short cadence instead of giving up
    /// on the first zero-rate reading.
    private static let deviceSwitchRetryDelay: TimeInterval = 0.15
    private static let deviceSwitchMaxAttempts = 10

    /// Upper bound on waiting for in-flight tap callbacks during a device
    /// switch. Exceeding it means a callback is wedged, and the WAV must not
    /// then be handed to a second tap.
    private static let tapDrainTimeout: DispatchTimeInterval = .milliseconds(500)

    // OSAllocatedUnfairLock is the canonical macOS fast lock with priority inheritance.
    // Safe for the real-time audio thread: no stalls from priority inversion the way
    // pthread_mutex / NSLock could cause.
    private let sessionLock = OSAllocatedUnfairLock<ActiveSession?>(initialState: nil)
    private let rmsLock = OSAllocatedUnfairLock<Float>(initialState: 0)

    // Per-session DispatchGroup / DispatchQueue live on `ActiveSession` —
    // see the comments on those fields for why they MUST NOT be shared
    // across unrelated recordings. Sharing them was the bug
    // `resetAfterWake()` would otherwise create: a wedged tap callback or
    // stuck writer block from session N would poison session N+1's
    // `stopRecording()` drain. The one deliberate exception is the successor
    // session minted by a mid-recording device switch, which is the same take
    // continuing on a different microphone.

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

        invalidatePendingDeviceSwitch()
        rebindEngineToCurrentInputDeviceIfNeeded()

        let url = try Self.makeOutputURL()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard Self.isUsableFormat(inputFormat) else {
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

        invalidatePendingDeviceSwitch()

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

    // MARK: - Sleep / wake and device-switch recovery

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
    /// Also the give-up path of a failed device switch: one of the ways that
    /// switch fails is a wedged tap callback, and `stopRecording()` would
    /// then block the menu bar on `tapGroup.wait()` forever. `handleAutoStop`
    /// discards the take either way, so the clean WAV flush buys nothing here.
    ///
    /// Safe to call when no session is active (idempotent no-op). Caller
    /// is responsible for treating any orphan WAV as discardable; the
    /// retention sweeper will clean it up.
    func resetAfterWake() {
        dispatchPrecondition(condition: .onQueue(.main))
        invalidatePendingDeviceSwitch()
        // Rebuild rather than merely stop: after a suspend the engine can come
        // back bound to a device that no longer exists, and a stale binding
        // makes every later `startRecording()` fail with `invalidInputFormat`.
        rebuildEngine()
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
        // Idempotent: a device switch that reuses the engine calls this again,
        // and overwriting the token without unregistering would leak an
        // observer that keeps handling later notifications.
        removeConfigurationObserver()
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            self?.handleConfigurationChange()
        }
    }

    /// `.AVAudioEngineConfigurationChange` fires whenever the HAL topology
    /// under the engine moves: AirPods connecting or disconnecting, a USB
    /// interface arriving, the user picking another input in System Settings,
    /// or the current device renegotiating its sample rate.
    ///
    /// This used to tear the take down and report an auto-stop, which made
    /// AirPods unusable in two compounding ways: putting them on killed the
    /// recording, and the engine stayed bound to the input device that had
    /// just disappeared, so every subsequent `startRecording()` failed too —
    /// the only way out was quitting and relaunching the app. Now we keep the
    /// take alive: re-point the engine at the current default input and carry
    /// on writing into the same WAV. Auto-stop is the last resort, once the
    /// retries are exhausted.
    private func handleConfigurationChange() {
        dispatchPrecondition(condition: .onQueue(.main))
        // Also covers a notification landing while the user presses stop:
        // no active recording, nothing to migrate (was tech-debt item F027).
        guard isRecording else { return }
        // A single Bluetooth connect emits several of these in a row.
        guard !isSwitchingDevice else { return }

        deviceSwitchGeneration &+= 1
        isSwitchingDevice = true
        NSLog("WhisperHot: audio configuration changed; rebinding input device")

        // Detach right away — the old device may already be gone, and we do
        // not want its half-formed buffers landing in the WAV.
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        attemptDeviceSwitch(attempt: 0, generation: deviceSwitchGeneration)
    }

    private func attemptDeviceSwitch(attempt: Int, generation: UInt64) {
        dispatchPrecondition(condition: .onQueue(.main))
        // A stop / start / reset happened while this retry sat in the queue:
        // that newer lifecycle event owns the engine now.
        guard generation == deviceSwitchGeneration else { return }
        guard isRecording else {
            isSwitchingDevice = false
            return
        }

        do {
            try rebindActiveSessionToCurrentDevice()
            isSwitchingDevice = false
            NSLog("WhisperHot: recording resumed on the current input device (attempt \(attempt + 1))")
        } catch {
            guard attempt + 1 < Self.deviceSwitchMaxAttempts else {
                isSwitchingDevice = false
                NSLog("WhisperHot: input device never settled (\(error.localizedDescription)); abandoning recording")
                resetAfterWake()
                onAutoStop?()
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.deviceSwitchRetryDelay) { [weak self] in
                self?.attemptDeviceSwitch(attempt: attempt + 1, generation: generation)
            }
        }
    }

    /// Moves the in-flight recording onto the current default input device
    /// without closing the WAV.
    ///
    /// The successor session keeps the same `audioFile`, `outputURL`,
    /// `writerQueue` and `tapGroup` — it is the same take, so its writes must
    /// stay ordered behind the previous ones on the one serial queue — and
    /// takes a new id, input format and converter for the new device.
    ///
    /// Everything fallible runs before the live session is touched, so a
    /// failed attempt leaves the recording exactly as it found it and the
    /// retry starts from a clean state.
    private func rebindActiveSessionToCurrentDevice() throws {
        guard let current = sessionLock.withLock({ $0 }) else {
            throw AudioError.notRecording
        }

        rebindEngineToCurrentInputDeviceIfNeeded()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard Self.isUsableFormat(inputFormat) else {
            throw AudioError.invalidInputFormat
        }
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw AudioError.converterUnavailable
        }

        // Take the old session off the air — in-flight taps bail on the id
        // check — then let any callback already inside `processTapBuffer`
        // finish. The engine is stopped and untapped by now, so this returns
        // immediately unless a callback is genuinely wedged; in that case we
        // must not hand its AVAudioFile to a second tap.
        sessionLock.withLock { $0 = nil }
        guard current.tapGroup.wait(timeout: .now() + Self.tapDrainTimeout) == .success else {
            sessionLock.withLock { $0 = current }
            throw AudioError.tapDrainTimedOut
        }

        sessionCounter &+= 1
        let successor = ActiveSession(
            id: sessionCounter,
            converter: converter,
            audioFile: current.audioFile,
            inputFormat: inputFormat,
            outputURL: current.outputURL,
            tapGroup: current.tapGroup,
            writerQueue: current.writerQueue
        )
        sessionLock.withLock { $0 = successor }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self, session = successor] buffer, _ in
            self?.processTapBuffer(buffer, session: session)
        }
        installConfigurationObserver()

        do {
            try engine.start()
        } catch {
            // `successor` stays in the slot: it owns the same WAV as `current`,
            // so the next retry picks the take up from exactly here.
            inputNode.removeTap(onBus: 0)
            removeConfigurationObserver()
            throw AudioError.engineStartFailed(underlying: error)
        }
    }

    /// Cancels any queued device-switch retry. Every recording-lifecycle
    /// transition calls this, so a retry scheduled for a finished take can
    /// never reach into its successor.
    private func invalidatePendingDeviceSwitch() {
        deviceSwitchGeneration &+= 1
        isSwitchingDevice = false
    }

    private func removeConfigurationObserver() {
        if let obs = configurationObserver {
            NotificationCenter.default.removeObserver(obs)
            configurationObserver = nil
        }
    }

    // MARK: - Input device binding

    /// Rebuilds `engine` when the system's default input device has moved
    /// since the engine was built, or when the engine stopped reporting a
    /// usable input format.
    ///
    /// Note what we do NOT do here: ask the engine which device it is on.
    /// `AVAudioEngine` does not sit on a physical device at all — on macOS it
    /// drives a private `CADefaultDeviceAggregate-*` that wraps the current
    /// default input and output, so `inputNode.auAudioUnit.deviceID` returns
    /// the aggregate's id, never the microphone's. Pinning the unit with
    /// `setDeviceID(_:)` is not an option either: on an engine that has
    /// already materialised its IO unit it fails with `-10851` and leaves the
    /// unit with a device id of 0. So we remember the default input device we
    /// built the engine for and compare against that.
    ///
    /// A fresh engine is the reliable recovery: after the HAL topology moves
    /// under a live engine — AirPods connecting mid-session — its input node
    /// can keep reporting the format of a device that is gone, and every
    /// later `startRecording()` fails on `invalidInputFormat` until the app
    /// is relaunched.
    private func rebindEngineToCurrentInputDeviceIfNeeded() {
        let systemDefault = Self.currentDefaultInputDeviceID()
        let staleFormat = !Self.isUsableFormat(engine.inputNode.outputFormat(forBus: 0))
        guard systemDefault != engineInputDeviceID || staleFormat else { return }
        NSLog("WhisperHot: rebuilding audio engine (input device \(engineInputDeviceID) -> \(systemDefault), staleFormat=\(staleFormat))")
        rebuildEngine()
    }

    /// Tears the current engine down and replaces it with a fresh instance,
    /// which resolves the default input device anew. Never waits on the tap or
    /// writer queues, so it is also safe on the wake-recovery path.
    private func rebuildEngine() {
        removeConfigurationObserver()
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        engine = AVAudioEngine()
        engineInputDeviceID = Self.currentDefaultInputDeviceID()
    }

    private static func isUsableFormat(_ format: AVAudioFormat) -> Bool {
        format.sampleRate > 0 && format.channelCount > 0
    }

    /// The HAL device id macOS currently routes audio input to, or
    /// `kAudioObjectUnknown` when there is no input device at all.
    private static func currentDefaultInputDeviceID() -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        guard status == noErr else {
            NSLog("WhisperHot: could not read the default input device (OSStatus \(status))")
            return AudioDeviceID(kAudioObjectUnknown)
        }
        return deviceID
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
