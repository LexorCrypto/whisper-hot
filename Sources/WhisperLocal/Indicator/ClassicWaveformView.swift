import SwiftUI

struct ClassicWaveformView: View {
    @ObservedObject var viewModel: IndicatorViewModel

    private let barCount = 28

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.red)
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

        // `viewModel.rms` is a 0…~0.3 ballpark for speech. Scale up and clamp.
        let level = CGFloat(min(max(viewModel.rms * 5.0, 0), 1))

        // Animated phase over time so the bars "travel" during steady tone.
        let phaseBase = viewModel.elapsed * 3.5

        for i in 0..<barCount {
            let phase = phaseBase + Double(i) * 0.35
            let wave = (sin(phase) * 0.5 + 0.5)   // 0…1
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

    private var formattedElapsed: String {
        let total = Int(viewModel.elapsed)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
