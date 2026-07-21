import SwiftUI

/// Mid-size dark "glass" recording panel: a pulsing status dot, a compact
/// accent→violet gradient waveform driven by microphone RMS, an mm:ss
/// elapsed timer, and the paste destination ("→ App") — all inside a
/// frosted, dark rounded-rect capsule.
///
///  ┌──────────────────────────────────────────────┐
///  │  ●  ▁▂▄▆█▇▅▃▂▁▂▃▅▇█▆  00:05  → Hermes         │
///  └──────────────────────────────────────────────┘
struct MediumIndicatorView: View {
    @ObservedObject var viewModel: IndicatorViewModel

    private let barCount = 20
    private let panelHeight: CGFloat = 46
    private let waveWidth: CGFloat = 104
    private let waveHeight: CGFloat = 26

    private let accent = Color(red: 0.039, green: 0.518, blue: 1.0)
    private let violet = Color(red: 0.749, green: 0.353, blue: 0.949)

    private let glassShape = RoundedRectangle(cornerRadius: 16, style: .continuous)

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(dotColor)
                .frame(width: 10, height: 10)
                .opacity(dotOpacity)

            Canvas { context, size in
                if viewModel.mode == .transcribing {
                    drawTranscribing(context: context, size: size)
                } else {
                    drawRecording(context: context, size: size)
                }
            }
            .frame(width: waveWidth, height: waveHeight)

            Text(formattedElapsed)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.85))

            if let destination = viewModel.destination {
                HStack(spacing: 4) {
                    Text("→")
                        .foregroundColor(.white.opacity(0.45))
                    Text(destination)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundColor(.white.opacity(0.7))
                }
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .frame(maxWidth: 120, alignment: .leading)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(height: panelHeight)
        .background(glassShape.fill(Color.black.opacity(0.55)))
        .background(.ultraThinMaterial, in: glassShape)
        .overlay(glassShape.strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
    }

    // MARK: - Dot

    private var dotColor: Color {
        viewModel.mode == .transcribing ? .orange : .red
    }

    private var dotOpacity: Double {
        if viewModel.mode == .transcribing {
            // Slower, calmer pulse for the waiting state.
            let cycle = viewModel.elapsed.truncatingRemainder(dividingBy: 1.5)
            return 0.4 + 0.6 * (0.5 + 0.5 * cos(cycle / 1.5 * .pi * 2))
        }
        let cycle = viewModel.elapsed.truncatingRemainder(dividingBy: 1.0)
        let base = 0.55 + 0.45 * cos(cycle * .pi * 2)
        let rmsBoost = Double(min(viewModel.rms * 4, 1))
        return min(base + rmsBoost * 0.25, 1.0)
    }

    // MARK: - Recording waveform

    private func drawRecording(context: GraphicsContext, size: CGSize) {
        let barSpacing: CGFloat = 2.5
        let totalSpacing = barSpacing * CGFloat(barCount - 1)
        let barWidth = max((size.width - totalSpacing) / CGFloat(barCount), 1.5)
        let maxBarHeight = size.height
        let midY = size.height / 2

        let level = CGFloat(min(max(viewModel.rms * 5, 0), 1))
        let speed = 6.0
        let offset = 0.4

        for i in 0..<barCount {
            let phase = viewModel.elapsed * speed + Double(i) * offset
            let wave = sin(phase) * 0.5 + 0.5
            let h = max(level * CGFloat(wave), 0.08) * maxBarHeight
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

    // MARK: - Transcribing waiting animation

    private func drawTranscribing(context: GraphicsContext, size: CGSize) {
        let barSpacing: CGFloat = 2.5
        let totalSpacing = barSpacing * CGFloat(barCount - 1)
        let barWidth = max((size.width - totalSpacing) / CGFloat(barCount), 1.5)
        let maxBarHeight = size.height
        let midY = size.height / 2

        let speed = 2.4
        let phase = viewModel.elapsed * speed
        let breathe = 0.3 + 0.7 * (sin(viewModel.elapsed * 0.8) * 0.5 + 0.5)

        for i in 0..<barCount {
            let t = Double(i) / Double(barCount)
            let wave = sin(phase + t * .pi * 3) * 0.5 + 0.5
            let h = max(CGFloat(wave * breathe), 0.08) * maxBarHeight
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

    // MARK: - Helpers

    private var formattedElapsed: String {
        let total = Int(viewModel.elapsed)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
