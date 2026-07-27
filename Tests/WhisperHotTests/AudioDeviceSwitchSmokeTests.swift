import AVFoundation
import CoreAudio
import XCTest
@testable import WhisperHotLib

/// Pins down the platform facts that the input-device rebinding in
/// `AudioRecorder` is built on, so a future macOS change surfaces here rather
/// than as "dictation stops working when I put my AirPods in".
///
/// Read-only: it inspects the current audio topology and never changes it.
/// The full "switch devices mid-recording" scenario mutates a global macOS
/// setting and therefore stays manual.
final class AudioDeviceSwitchSmokeTests: XCTestCase {

    /// A freshly built engine must be usable on whatever microphone is current.
    /// This is the recovery `rebindEngineToCurrentInputDeviceIfNeeded()`
    /// performs: throw the engine away, build a new one, read the format.
    func testFreshEngineReportsUsableInputFormat() throws {
        let systemDefault = try Self.requireDefaultInputDeviceID()
        print("SMOKE input devices: \(Self.inputDevices()); default=\(systemDefault)")
        try XCTSkipIf(
            systemDefault == AudioDeviceID(kAudioObjectUnknown),
            "no input device on this machine"
        )

        // The engine MUST outlive the node access: `AVAudioEngine`'s nodes do
        // not retain their engine, so reading through a temporary is a
        // use-after-free (segfaults the whole xctest process).
        let engine = AVAudioEngine()
        let format = engine.inputNode.outputFormat(forBus: 0)
        withExtendedLifetime(engine) {}
        print("SMOKE fresh engine input format=\(format)")

        XCTAssertGreaterThan(format.sampleRate, 0, "a fresh engine must report a usable sample rate")
        XCTAssertGreaterThan(format.channelCount, 0, "a fresh engine must report at least one channel")
        XCTAssertNotNil(
            AVAudioConverter(from: format, to: Self.transcriptionFormat),
            "the current input format must be convertible to the 16 kHz mono PCM we transcribe"
        )
    }

    /// `AVAudioEngine` drives a private `CADefaultDeviceAggregate-*`, not the
    /// physical microphone, so its audio unit's `deviceID` never names the
    /// current input — which is why `AudioRecorder` tracks the default input
    /// device itself instead of asking the engine. If this ever stops holding,
    /// the cheaper `auAudioUnit.deviceID` comparison becomes available.
    func testEngineAudioUnitDoesNotExposeThePhysicalInputDevice() throws {
        let systemDefault = try Self.requireDefaultInputDeviceID()
        try XCTSkipIf(
            systemDefault == AudioDeviceID(kAudioObjectUnknown),
            "no input device on this machine"
        )

        let engine = AVAudioEngine()
        let unitDeviceID = engine.inputNode.auAudioUnit.deviceID
        withExtendedLifetime(engine) {}
        print("SMOKE engine unit device=\(unitDeviceID) systemDefaultInput=\(systemDefault)")

        XCTAssertNotEqual(
            unitDeviceID,
            systemDefault,
            "engine reports the physical input device now — revisit rebindEngineToCurrentInputDeviceIfNeeded()"
        )
    }

    private static let transcriptionFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 16_000,
        channels: 1,
        interleaved: true
    )!

    // MARK: - CoreAudio helpers

    private static func globalAddress(
        _ selector: AudioObjectPropertySelector
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    /// A CoreAudio query that failed outright. Distinct from "this machine has
    /// no microphone", which macOS reports as `noErr` naming
    /// `kAudioObjectUnknown`.
    private struct CoreAudioQueryFailure: Error, CustomStringConvertible {
        let property: String
        let status: OSStatus
        var description: String {
            "CoreAudio rejected \(property) with OSStatus \(status)"
        }
    }

    /// The system default input device, or `kAudioObjectUnknown` when this
    /// machine genuinely has none — the single outcome the callers may skip on.
    ///
    /// A failing `AudioObjectGetPropertyData` is **not** that outcome and
    /// throws instead. `kAudioObjectSystemObject` is always a valid object
    /// (`AudioHardwareBase.h:136-137`), so every nonzero `OSStatus` here means
    /// the platform assumption these tests exist to pin down has broken.
    /// Folding them all into the sentinel — as this helper briefly did — made a
    /// CoreAudio regression indistinguishable from a headless machine and would
    /// have turned both tests into a green skip.
    private static func requireDefaultInputDeviceID() throws -> AudioDeviceID {
        var address = globalAddress(kAudioHardwarePropertyDefaultInputDevice)
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        )
        guard status == noErr else {
            throw CoreAudioQueryFailure(
                property: "kAudioHardwarePropertyDefaultInputDevice",
                status: status
            )
        }
        return deviceID
    }

    /// Ids of every device exposing at least one input channel.
    private static func inputDevices() -> [AudioDeviceID] {
        var address = globalAddress(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        ) == noErr, size > 0 else { return [] }

        var ids = [AudioDeviceID](
            repeating: 0,
            count: Int(size) / MemoryLayout<AudioDeviceID>.size
        )
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids
        ) == noErr else { return [] }

        return ids.filter { inputChannelCount($0) > 0 }
    }

    private static func inputChannelCount(_ id: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else {
            return 0
        }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 16)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw) == noErr else {
            return 0
        }
        let list = raw.assumingMemoryBound(to: AudioBufferList.self)
        return UnsafeMutableAudioBufferListPointer(list).reduce(0) { $0 + Int($1.mNumberChannels) }
    }
}
