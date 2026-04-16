import SwiftUI

/// Premium recording indicator: capsule with blur material, animated
/// waveform bars driven by RMS, pulsing dot, and elapsed timer.
///
/// Two modes:
/// - **Recording:** bars driven by microphone RMS, red pulsing dot
/// - **Transcribing:** gentle pulsing wave animation, orange dot
///
///  ┌──────────────────────────────────────────────────┐
///  │  🔴  ░░▓▓▓░▓▓▓▓░░▓▓░░▓░░▓▓░▓▓▓░▓   00:05      │
///  │            (blur background material)            │
///  └──────────────────────────────────────────────────┘
struct FloatingCapsuleView: View {
    @ObservedObject var viewModel: IndicatorViewModel

    private let barCount = 36

    var body: some View {
        HStack(spacing: 10) {
            TimelineView(.animation) { timeline in
                let elapsed = timeline.date.timeIntervalSince(viewModel.startDate ?? Date())
                HStack(spacing: 10) {
                    // Dot: red when recording, orange pulsing when transcribing
                    Circle()
                        .fill(dotColor)
                        .frame(width: 10, height: 10)
                        .opacity(dotOpacity(phase: elapsed))

                    Canvas { context, size in
                        if viewModel.mode == .transcribing {
                            drawWaitingAnimation(context: context, size: size, phase: elapsed)
                        } else {
                            drawWaveform(context: context, size: size, phase: elapsed)
                        }
                    }
                    .frame(width: 240, height: 32)
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

    // MARK: - Dot

    private var dotColor: Color {
        viewModel.mode == .transcribing ? .orange : .red
    }

    private func dotOpacity(phase: TimeInterval) -> Double {
        if viewModel.mode == .transcribing {
            // Slower, calmer pulse for waiting state
            let cycle = phase.truncatingRemainder(dividingBy: 1.5)
            return 0.4 + 0.6 * (0.5 + 0.5 * cos(cycle / 1.5 * .pi * 2))
        }
        let cycle = phase.truncatingRemainder(dividingBy: 1.0)
        let base = 0.55 + 0.45 * cos(cycle * .pi * 2)
        let rmsBoost = Double(min(viewModel.rms * 4, 1))
        return min(base + rmsBoost * 0.25, 1.0)
    }

    // MARK: - Recording waveform

    private func drawWaveform(context: GraphicsContext, size: CGSize, phase: TimeInterval) {
        let barSpacing: CGFloat = 2.5
        let totalSpacing = barSpacing * CGFloat(barCount - 1)
        let barWidth = max((size.width - totalSpacing) / CGFloat(barCount), 1.5)
        let maxBarHeight = size.height
        let midY = size.height / 2

        // Amplified RMS for more volatile response (x8 instead of x5)
        let level = CGFloat(min(max(viewModel.rms * 8.0, 0), 1))

        let animPhase = phase * 4.0  // faster wave travel

        for i in 0..<barCount {
            let t = Double(i) / Double(barCount)
            // Multiple harmonics for more organic look
            let wave1 = sin(animPhase + t * .pi * 5) * 0.5 + 0.5
            let wave2 = sin(animPhase * 1.3 + t * .pi * 3) * 0.25 + 0.25
            let wave = min(wave1 + wave2, 1.0)

            let heightFrac = level * wave
            let h = max(heightFrac * maxBarHeight, 2)
            let x = CGFloat(i) * (barWidth + barSpacing)
            let y = midY - h / 2
            let rect = CGRect(x: x, y: y, width: barWidth, height: h)

            let opacity = 0.3 + 0.7 * Double(level) * wave
            context.fill(
                Path(roundedRect: rect, cornerRadius: barWidth / 2),
                with: .color(.accentColor.opacity(opacity))
            )
        }
    }

    // MARK: - Transcribing waiting animation

    private func drawWaitingAnimation(context: GraphicsContext, size: CGSize, phase: TimeInterval) {
        let barSpacing: CGFloat = 2.5
        let totalSpacing = barSpacing * CGFloat(barCount - 1)
        let barWidth = max((size.width - totalSpacing) / CGFloat(barCount), 1.5)
        let maxBarHeight = size.height * 0.4  // calmer, smaller bars
        let midY = size.height / 2

        // Gentle traveling wave with no RMS input
        let animPhase = phase * 2.0  // slower than recording

        for i in 0..<barCount {
            let t = Double(i) / Double(barCount)
            // Smooth sine wave that "breathes"
            let wave = sin(animPhase + t * .pi * 3) * 0.5 + 0.5
            let breathe = 0.3 + 0.7 * (sin(phase * 0.8) * 0.5 + 0.5)

            let h = max(wave * breathe * maxBarHeight, 2)
            let x = CGFloat(i) * (barWidth + barSpacing)
            let y = midY - h / 2
            let rect = CGRect(x: x, y: y, width: barWidth, height: h)

            let opacity = 0.2 + 0.5 * wave * breathe
            context.fill(
                Path(roundedRect: rect, cornerRadius: barWidth / 2),
                with: .color(.orange.opacity(opacity))
            )
        }
    }

    // MARK: - Helpers

    private var formattedElapsed: String {
        let total = Int(viewModel.elapsed)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
