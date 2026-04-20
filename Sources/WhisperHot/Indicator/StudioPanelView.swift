import SwiftUI

/// Wide, dark "studio" recording panel modeled after SuperWhisper's floating
/// indicator, minus the vendor logo. A dense cluster of vertical bars driven
/// by microphone RMS fills the center, fading at the edges. A small footer
/// row shows keyboard shortcut hints so the user always knows how to stop.
///
///  ┌──────────────────────────────────────────────────────────────────┐
///  │     · · ▁ ▂ ▄ ▆ █ █ ▆ ▅ █ ▇ ▅ ▄ ▃ ▂ ▁ · ·                        │
///  │                                                                  │
///  │                                  Stop ⌥⌘5   Cancel esc           │
///  └──────────────────────────────────────────────────────────────────┘
struct StudioPanelView: View {
    @ObservedObject var viewModel: IndicatorViewModel

    private let barCount = 72
    private let panelWidth: CGFloat = 560
    private let waveHeight: CGFloat = 64

    var body: some View {
        VStack(spacing: 8) {
            TimelineView(.animation) { timeline in
                let phase = timeline.date.timeIntervalSince(viewModel.startDate ?? timeline.date)
                Canvas { context, size in
                    if viewModel.mode == .transcribing {
                        drawWaiting(context: context, size: size, phase: phase)
                    } else {
                        drawRecording(context: context, size: size, phase: phase)
                    }
                }
                .frame(width: panelWidth - 32, height: waveHeight)
            }

            footer
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .frame(width: panelWidth)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.black.opacity(0.86))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
        )
    }

    // MARK: - Footer (keyboard hints)

    private var footer: some View {
        HStack(spacing: 14) {
            Spacer()
            HStack(spacing: 6) {
                Text(L10n.lang == .ru ? "Стоп" : "Stop")
                    .foregroundColor(.white.opacity(0.85))
                keyCap(stopHotkeyLabel)
            }
        }
        .font(.system(size: 12, weight: .medium))
    }

    private func keyCap(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundColor(.white.opacity(0.95))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.white.opacity(0.12))
            )
    }

    /// The hotkey string that actually toggles recording. Fn mode collapses
    /// to the globe glyph so the label stays truthful instead of promising a
    /// combo that will not fire.
    private var stopHotkeyLabel: String {
        if Preferences.fnKeyEnabled {
            return "fn"
        }
        return HotkeyFormatter.format(
            keyCode: Preferences.hotkeyKeyCode,
            modifiers: Preferences.hotkeyModifiers
        )
    }

    // MARK: - Recording waveform

    private func drawRecording(context: GraphicsContext, size: CGSize, phase: TimeInterval) {
        let barSpacing: CGFloat = 3
        let totalSpacing = barSpacing * CGFloat(barCount - 1)
        let barWidth = max((size.width - totalSpacing) / CGFloat(barCount), 1.5)
        let maxBarHeight = size.height
        let midY = size.height / 2

        let level = CGFloat(min(max(viewModel.rms * 9.0, 0), 1))
        let animPhase = phase * 5.0

        for i in 0..<barCount {
            let t = Double(i) / Double(barCount - 1)
            // Two harmonics stacked: fast travelling wave + slower modulation
            // gives the dense, busy look from the reference.
            let wave1 = sin(animPhase + t * .pi * 6) * 0.5 + 0.5
            let wave2 = sin(animPhase * 1.6 + t * .pi * 2.5) * 0.3 + 0.3
            let wave = min(wave1 + wave2, 1.0)

            // Bell-shaped edge falloff so the cluster is centered, edges dim.
            let centered = 1.0 - abs(t - 0.5) * 2.0
            let envelope = pow(max(centered, 0), 1.6)

            let heightFrac = max(level * wave * envelope, 0.04)
            let h = max(heightFrac * maxBarHeight, 2)
            let x = CGFloat(i) * (barWidth + barSpacing)
            let y = midY - h / 2
            let rect = CGRect(x: x, y: y, width: barWidth, height: h)

            let alpha = 0.25 + 0.75 * envelope * (Double(level) * 0.6 + 0.4) * wave
            context.fill(
                Path(roundedRect: rect, cornerRadius: barWidth / 2),
                with: .color(.white.opacity(min(alpha, 1.0)))
            )
        }
    }

    // MARK: - Transcribing waiting animation

    private func drawWaiting(context: GraphicsContext, size: CGSize, phase: TimeInterval) {
        let barSpacing: CGFloat = 3
        let totalSpacing = barSpacing * CGFloat(barCount - 1)
        let barWidth = max((size.width - totalSpacing) / CGFloat(barCount), 1.5)
        let maxBarHeight = size.height * 0.35
        let midY = size.height / 2

        let animPhase = phase * 2.2

        for i in 0..<barCount {
            let t = Double(i) / Double(barCount - 1)
            let wave = sin(animPhase + t * .pi * 3) * 0.5 + 0.5
            let breathe = 0.35 + 0.65 * (sin(phase * 0.9) * 0.5 + 0.5)
            let centered = 1.0 - abs(t - 0.5) * 2.0
            let envelope = pow(max(centered, 0), 1.4)

            let h = max(wave * breathe * envelope * maxBarHeight, 2)
            let x = CGFloat(i) * (barWidth + barSpacing)
            let y = midY - h / 2
            let rect = CGRect(x: x, y: y, width: barWidth, height: h)

            let alpha = 0.2 + 0.5 * wave * envelope * breathe
            context.fill(
                Path(roundedRect: rect, cornerRadius: barWidth / 2),
                with: .color(.orange.opacity(alpha))
            )
        }
    }
}
