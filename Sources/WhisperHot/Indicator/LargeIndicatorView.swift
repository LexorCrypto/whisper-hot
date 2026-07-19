import SwiftUI

/// Large recording indicator style: a compact-but-substantial dark-glass
/// panel with a dense, center-symmetric gradient waveform (44 bars mirrored
/// left/right and growing up/down from the midline) plus a timer and a
/// muted hotkey hint. Deliberately narrower than the old wide studio panel.
///
///  ┌──────────────────────────────────────┐
///  │   ▁▂▃▅▇█▇▅▃▂▁ · ▁▂▃▅▇█▇▅▃▂▁            │
///  │   00:12                    ⌥⌘5 стоп   │
///  └──────────────────────────────────────┘
struct LargeIndicatorView: View {
    @ObservedObject var viewModel: IndicatorViewModel

    private let barCount = 44
    private let panelWidth: CGFloat = 340
    private let waveHeight: CGFloat = 48

    private let accent = Color(red: 0.039, green: 0.518, blue: 1.0)
    private let violet = Color(red: 0.749, green: 0.353, blue: 0.949)

    private let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)

    var body: some View {
        VStack(spacing: 8) {
            Canvas { context, size in
                drawBars(context: context, size: size)
            }
            .frame(width: panelWidth - 32, height: waveHeight)

            HStack(spacing: 8) {
                Text(formattedElapsed)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))

                Spacer()

                Text(hotkeyHintLabel)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .frame(width: panelWidth)
        .background(
            shape.fill(Color.black.opacity(0.55))
        )
        .background(.ultraThinMaterial, in: shape)
        .overlay(
            shape.strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    // MARK: - Waveform

    /// Bars are indexed by distance from the horizontal center, so index
    /// `i` and its mirror `barCount - 1 - i` always share the same phase —
    /// a true left/right symmetric ripple radiating outward. Each bar's
    /// rect is centered on `midY`, so it also grows symmetrically up and
    /// down rather than sitting on a baseline.
    private func drawBars(context: GraphicsContext, size: CGSize) {
        let barSpacing: CGFloat = 2
        let totalSpacing = barSpacing * CGFloat(barCount - 1)
        let barWidth = max((size.width - totalSpacing) / CGFloat(barCount), 1)
        let maxBarHeight = size.height
        let midY = size.height / 2
        let center = Double(barCount - 1) / 2
        let elapsed = viewModel.elapsed
        let isTranscribing = viewModel.mode == .transcribing

        for i in 0..<barCount {
            let dist = abs(Double(i) - center)
            let t = dist / center

            let heightFrac: CGFloat
            if isTranscribing {
                // Soft breathing wave, no RMS input.
                let phase = elapsed * 2.4 + dist * 0.4
                let wave = sin(phase + t * .pi * 3) * 0.5 + 0.5
                let breathe = 0.3 + 0.7 * (sin(elapsed * 0.8) * 0.5 + 0.5)
                heightFrac = max(CGFloat(wave * breathe), 0.08)
            } else {
                let level = CGFloat(min(max(viewModel.rms * 5, 0), 1))
                let phase = elapsed * 6.0 + dist * 0.45
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

    // MARK: - Footer

    private var formattedElapsed: String {
        let total = Int(viewModel.elapsed)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    /// Reflects the user's actual configured hotkey (or "fn" in Fn-key
    /// mode) rather than hardcoding a combo the user may have changed.
    private var hotkeyHintLabel: String {
        let combo: String
        if Preferences.fnKeyEnabled {
            combo = "fn"
        } else {
            combo = HotkeyFormatter.format(
                keyCode: Preferences.hotkeyKeyCode,
                modifiers: Preferences.hotkeyModifiers
            )
        }
        return "\(combo) \(L10n.stop.lowercased())"
    }
}
