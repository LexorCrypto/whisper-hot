import AVFoundation
import Foundation
import os

final class AudioRecorder: NSObject {
    private struct ActiveSession: @unchecked Sendable {
        let converter: AVAudioConverter
        let audioFile: AVAudioFile
        let inputFormat: AVAudioFormat
        let outputURL: URL
    }

    /// Main-thread only.
    private(set) var isRecording = false

    /// Thread-safe snapshot of the most recent RMS value sampled from the tap.
    var currentRMS: Float {
        rmsLock.withLock { $0 }
    }

    /// Fired on the main queue when recording stops unexpectedly (config change, error).
    var onAutoStop: (() -> Void)?

    private let engine = AVAudioEngine()

    // OSAllocatedUnfairLock is the canonical macOS fast lock with priority inheritance.
    // Safe for the real-time audio thread: no stalls from priority inversion the way
    // pthread_mutex / NSLock could cause.
    private let sessionLock = OSAllocatedUnfairLock<ActiveSession?>(initialState: nil)
    private let rmsLock = OSAllocatedUnfairLock<Float>(initialState: 0)

    // Tracks in-flight tap callbacks so stopRecording can wait for them explicitly,
    // without depending on any undocumented "removeTap is a barrier" assumption.
    private let tapGroup = DispatchGroup()

    // Serial queue for all disk I/O — keeps audioFile.write off the real-time audio thread.
    private let writerQueue = DispatchQueue(
        label: "com.aleksejsupilin.WhisperHot.audio.writer",
        qos: .userInitiated
    )

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

        let newSession = ActiveSession(
            converter: converter,
            audioFile: file,
            inputFormat: inputFormat,
            outputURL: url
        )

        sessionLock.withLock { $0 = newSession }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.processTapBuffer(buffer)
        }

        installConfigurationObserver()

        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            tapGroup.wait()
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
        // 2. tapGroup.wait  — explicitly wait for any tap callbacks that are
        //    already in flight (or whose input buffer was already in the pipeline
        //    before removeTap). This makes us independent of whether removeTap
        //    itself is a barrier.
        // 3. writerQueue.sync{}  — drain the serial writer queue; all
        //    writerQueue.async calls the taps made were enqueued before their
        //    tapGroup.leave(), so they are now guaranteed to run before this marker.
        // 4. Clear session  — now nothing is holding ActiveSession references
        //    besides the lock-protected slot, so nilling it deallocates the
        //    AVAudioFile and flushes the WAV header.
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        removeConfigurationObserver()

        tapGroup.wait()
        writerQueue.sync { }

        let finished: ActiveSession? = sessionLock.withLock { slot in
            let captured = slot
            slot = nil
            return captured
        }

        rmsLock.withLock { $0 = 0 }
        isRecording = false

        guard let finished else {
            throw AudioError.notRecording
        }
        return finished.outputURL
    }

    // MARK: - Tap processing (real-time audio thread)

    private func processTapBuffer(_ buffer: AVAudioPCMBuffer) {
        tapGroup.enter()
        defer { tapGroup.leave() }

        let active = sessionLock.withLock { $0 }
        guard let active else { return }

        let rms = Self.computeRMS(buffer: buffer)
        rmsLock.withLock { $0 = rms }

        let ratio = outputFormat.sampleRate / active.inputFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 1024)
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            return
        }

        var inputConsumed = false
        var error: NSError?
        let status = active.converter.convert(to: outBuffer, error: &error) { _, outStatus in
            if inputConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputConsumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        guard status != .error, error == nil else {
            NSLog("WhisperHot: converter error: \(error?.localizedDescription ?? "unknown")")
            return
        }

        // The converted buffer is handed off to the serial writer queue. Because
        // writerQueue.async is called before tapGroup.leave(), stopRecording's
        // tapGroup.wait() guarantees no new writes will be enqueued after it returns.
        let file = active.audioFile
        writerQueue.async {
            do {
                try file.write(from: outBuffer)
            } catch {
                NSLog("WhisperHot: audio write error: \(error.localizedDescription)")
            }
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
