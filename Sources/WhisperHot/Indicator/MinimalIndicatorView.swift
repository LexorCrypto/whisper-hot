import SwiftUI

/// Most minimal recording indicator style: a compact dark-glass capsule with
/// a pulsing status dot and a tiny 5-bar gradient waveform that echoes the
/// 5-bar app logo. No text, no timer — just motion.
///
///  ┌──────────────────┐
///  │  🔴  ▁▃▅▃▁        │
///  │   (dark glass)    │
///  └──────────────────┘
struct MinimalIndicatorView: View {
    @ObservedObject var viewModel: IndicatorViewModel

    private let barCount = 5

    private let accent = Color(red: 0.039, green: 0.518, blue: 1.0)
    private let violet = Color(red: 0.749, green: 0.353, blue: 0.949)

    private let shape = Capsule(style: .continuous)

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
                .opacity(dotOpacity)

            Canvas { context, size in
                drawBars(context: context, size: size)
            }
            .frame(width: 60, height: 18)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(width: 112, height: 34)
        .background(
            shape.fill(Color.black.opacity(0.55))
        )
        .background(.ultraThinMaterial, in: shape)
        .overlay(
            shape.strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    // MARK: - Dot

    private var dotColor: Color {
        viewModel.mode == .transcribing ? .orange : .red
    }

    private var dotOpacity: Double {
        let period: TimeInterval = viewModel.mode == .transcribing ? 1.5 : 1.0
        let phase = viewModel.elapsed.truncatingRemainder(dividingBy: period)
        return 0.45 + 0.55 * (0.5 + 0.5 * cos(phase / period * .pi * 2))
    }

    // MARK: - Bars

    private func drawBars(context: GraphicsContext, size: CGSize) {
        let barSpacing: CGFloat = 3
        let totalSpacing = barSpacing * CGFloat(barCount - 1)
        let barWidth = max((size.width - totalSpacing) / CGFloat(barCount), 1)
        let maxBarHeight = size.height
        let midY = size.height / 2
        let isTranscribing = viewModel.mode == .transcribing
        let phaseBase = viewModel.elapsed * (isTranscribing ? 1.8 : 3.5)

        for i in 0..<barCount {
            let t = Double(i) / Double(barCount - 1)
            let phase = phaseBase + Double(i) * 0.55
            let heightFrac: CGFloat
            if isTranscribing {
                let wave = sin(phase + t * .pi * 3) * 0.5 + 0.5
                let breathe = 0.3 + 0.7 * (sin(viewModel.elapsed * 0.8) * 0.5 + 0.5)
                heightFrac = max(CGFloat(wave * breathe), 0.08)
            } else {
                let level = CGFloat(min(max(viewModel.rms * 5, 0), 1))
                let wave = sin(phase) * 0.5 + 0.5
                heightFrac = max(level * CGFloat(wave), 0.08)
            }
            let h = heightFrac * maxBarHeight
            let x = CGFloat(i) * (barWidth + barSpacing)
            let y = midY - h / 2
            let rect = CGRect(x: x, y: y, width: barWidth, height: h)
            context.fill(
                Path(roundedRect: rect, cornerRadius: barWidth / 2),
                with: .linearGradient(
                    Gradient(colors: [accent, violet]),
                    startPoint: CGPoint(x: rect.midX, y: 0),
                    endPoint: CGPoint(x: rect.midX, y: size.height)
                )
            )
        }
    }
}
