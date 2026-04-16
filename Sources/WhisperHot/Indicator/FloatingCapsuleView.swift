import SwiftUI

/// Premium recording indicator: capsule with blur material, animated
/// waveform bars driven by RMS, pulsing red dot, and elapsed timer.
///
/// Uses `TimelineView(.animation)` for display-synced rendering
/// instead of a manual Timer, giving smoother 60fps animation
/// on ProMotion displays.
///
///  ┌─────────────────────────────────────────┐
///  │  🔴  ░░▓▓▓░▓▓▓▓░░▓▓░░▓░░   00:05      │
///  │       (blur background material)        │
///  └─────────────────────────────────────────┘
struct FloatingCapsuleView: View {
    @ObservedObject var viewModel: IndicatorViewModel

    private let barCount = 24

    var body: some View {
        HStack(spacing: 10) {
            // Pulsing dot + waveform driven by TimelineView for smooth 60fps.
            // Only these two elements need display-synced refresh, not the
            // static material/border/timer.
            TimelineView(.animation) { timeline in
                let elapsed = timeline.date.timeIntervalSince(viewModel.startDate ?? Date())
                HStack(spacing: 10) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 10, height: 10)
                        .opacity(pulseOpacity(phase: elapsed))

                    Canvas { context, size in
                        drawWaveform(context: context, size: size, phase: elapsed)
                    }
                    .frame(width: 180, height: 28)
                }
            }

            Text(formattedElapsed)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.primary)
                .frame(width: 44, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }

    // MARK: - Waveform

    private func drawWaveform(context: GraphicsContext, size: CGSize, phase: TimeInterval) {
        let barSpacing: CGFloat = 3
        let totalSpacing = barSpacing * CGFloat(barCount - 1)
        let barWidth = max((size.width - totalSpacing) / CGFloat(barCount), 1.5)
        let maxBarHeight = size.height
        let midY = size.height / 2

        let level = CGFloat(min(max(viewModel.rms * 5.0, 0), 1))

        // At silence (level near 0), bars collapse to flat lines instead of
        // shimmering, so the indicator looks truly idle.
        let animPhase = phase * 3.0

        for i in 0..<barCount {
            let t = Double(i) / Double(barCount)
            let wave = sin(animPhase + t * .pi * 4) * 0.5 + 0.5
            let heightFrac = level * wave
            // Minimum 2px height so bars are visible as dots even at silence
            let h = max(heightFrac * maxBarHeight, 2)
            let x = CGFloat(i) * (barWidth + barSpacing)
            let y = midY - h / 2
            let rect = CGRect(x: x, y: y, width: barWidth, height: h)

            // Opacity scales with level so bars fade at silence
            let opacity = 0.3 + 0.7 * Double(level) * wave
            context.fill(
                Path(roundedRect: rect, cornerRadius: barWidth / 2),
                with: .color(.accentColor.opacity(opacity))
            )
        }
    }

    // MARK: - Pulse

    private func pulseOpacity(phase: TimeInterval) -> Double {
        let cycle = phase.truncatingRemainder(dividingBy: 1.0)
        let base = 0.55 + 0.45 * cos(cycle * .pi * 2)
        let rmsBoost = Double(min(viewModel.rms * 4, 1))
        return min(base + rmsBoost * 0.25, 1.0)
    }

    // MARK: - Helpers

    private var formattedElapsed: String {
        let total = Int(viewModel.elapsed)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
