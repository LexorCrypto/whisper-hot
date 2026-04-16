import Combine
import Foundation

/// Drives the recording indicator UI with periodic snapshots of the recorder's
/// current RMS level and elapsed time. SwiftUI views observe the published
/// fields and redraw on every tick.
@MainActor
final class IndicatorViewModel: ObservableObject {
    enum Mode { case idle, recording, transcribing }

    @Published private(set) var rms: Float = 0
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var isActive: Bool = false
    @Published private(set) var mode: Mode = .idle

    private let rmsProvider: () -> Float
    private var timer: Timer?
    /// Exposed for TimelineView-based indicators that compute phase
    /// relative to recording start rather than absolute wall clock.
    private(set) var startDate: Date?

    /// Tick frequency for the UI refresh loop. 20 Hz is smooth enough for a
    /// pulsing dot and a waveform without burning battery. We also set
    /// `tolerance` below so AppKit can coalesce wakeups with other timers.
    private let tickInterval: TimeInterval = 1.0 / 20.0

    init(rmsProvider: @escaping () -> Float) {
        self.rmsProvider = rmsProvider
    }

    deinit {
        timer?.invalidate()
    }

    func start() {
        timer?.invalidate()
        startDate = Date()
        rms = 0
        elapsed = 0
        isActive = true
        mode = .recording

        let t = Timer(timeInterval: tickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        // Let AppKit coalesce wakeups with other timers; we do not need
        // strict 20 Hz jitter for a pulsing dot.
        t.tolerance = tickInterval / 2
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Switch to transcribing mode: keep the panel visible with a
    /// waiting animation but stop reading RMS from the microphone.
    func startTranscribing() {
        mode = .transcribing
        rms = 0
        // Keep timer running for elapsed time + animation
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        startDate = nil
        isActive = false
        mode = .idle
        rms = 0
        elapsed = 0
    }

    private func tick() {
        if mode == .recording {
            rms = rmsProvider()
        }
        // In transcribing mode rms stays 0 — the view draws a waiting animation instead
        if let startDate {
            elapsed = Date().timeIntervalSince(startDate)
        }
    }
}
