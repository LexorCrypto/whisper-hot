import SwiftUI

struct ClassicWaveformView: View {
    @ObservedObject var viewModel: IndicatorViewModel

    private let barCount = 28

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(viewModel.mode == .transcribing ? Color.orange : Color.red)
                .frame(width: 10, height: 10)

            Canvas { context, size in
                drawBars(context: context, size: size)
            }
            .frame(width: 220, height: 34)

            Text(formattedElapsed)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .frame(width: 44, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        // NSPanel.hasShadow draws the drop shadow — see IndicatorController.
    }

    private func drawBars(context: GraphicsContext, size: CGSize) {
        let barSpacing: CGFloat = 4
        let totalSpacing = barSpacing * CGFloat(barCount - 1)
        let barWidth = max((size.width - totalSpacing) / CGFloat(barCount), 1)
        let maxBarHeight = size.height
        let midY = size.height / 2

        let isTranscribing = viewModel.mode == .transcribing
        let phaseBase = viewModel.elapsed * (isTranscribing ? 2.0 : 3.5)

        if isTranscribing {
            // Gentle breathing wave, no RMS
            for i in 0..<barCount {
                let t = Double(i) / Double(barCount)
                let wave = sin(phaseBase + t * .pi * 3) * 0.5 + 0.5
                let breathe = 0.3 + 0.7 * (sin(viewModel.elapsed * 0.8) * 0.5 + 0.5)
                let h = max(wave * breathe * maxBarHeight * 0.4, 2)
                let x = CGFloat(i) * (barWidth + barSpacing)
                let y = midY - h / 2
                let rect = CGRect(x: x, y: y, width: barWidth, height: h)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: barWidth / 2),
                    with: .color(.orange.opacity(0.2 + 0.5 * wave * breathe))
                )
            }
        } else {
            let level = CGFloat(min(max(viewModel.rms * 5.0, 0), 1))
            for i in 0..<barCount {
                let phase = phaseBase + Double(i) * 0.35
                let wave = (sin(phase) * 0.5 + 0.5)
                let heightFrac = max(level * wave, 0.08)
                let h = heightFrac * maxBarHeight
                let x = CGFloat(i) * (barWidth + barSpacing)
                let y = midY - h / 2
                let rect = CGRect(x: x, y: y, width: barWidth, height: h)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: barWidth / 2),
                    with: .color(.accentColor)
                )
            }
        }
    }

    private var formattedElapsed: String {
        let total = Int(viewModel.elapsed)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
