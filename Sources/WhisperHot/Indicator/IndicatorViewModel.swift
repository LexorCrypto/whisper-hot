import Combine
import Foundation

/// Drives the recording indicator UI with periodic snapshots of the recorder's
/// current RMS level and elapsed time. SwiftUI views observe the published
/// fields and redraw on every tick.
@MainActor
final class IndicatorViewModel: ObservableObject {
    @Published private(set) var rms: Float = 0
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var isActive: Bool = false

    private let rmsProvider: () -> Float
    private var timer: Timer?
    private var startDate: Date?

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

    func stop() {
        timer?.invalidate()
        timer = nil
        startDate = nil
        isActive = false
        rms = 0
        elapsed = 0
    }

    private func tick() {
        rms = rmsProvider()
        if let startDate {
            elapsed = Date().timeIntervalSince(startDate)
        }
    }
}
