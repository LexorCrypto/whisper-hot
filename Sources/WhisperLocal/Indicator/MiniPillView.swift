import SwiftUI

struct MiniPillView: View {
    @ObservedObject var viewModel: IndicatorViewModel

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.red)
                .frame(width: 9, height: 9)
                .opacity(pulseOpacity)
            Text(formattedElapsed)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        // NSPanel.hasShadow draws the drop shadow — see IndicatorController.
    }

    private var pulseOpacity: Double {
        // Smooth 1 Hz pulse. Slightly boosted when the RMS spikes so the
        // dot "breathes" with the user's voice.
        let phase = viewModel.elapsed.truncatingRemainder(dividingBy: 1.0)
        let base = 0.55 + 0.45 * cos(phase * .pi * 2)
        let rmsBoost = Double(min(viewModel.rms * 4, 1))
        return min(base + rmsBoost * 0.25, 1.0)
    }

    private var formattedElapsed: String {
        let total = Int(viewModel.elapsed)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
