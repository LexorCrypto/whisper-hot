import AppKit
import SwiftUI

/// Owns the floating recording indicator panel.
/// - Reads the current `Preferences.indicatorStyle` each `show()` so the user
///   can switch modes in Settings and see the change on the next recording.
/// - Menubar-only mode shows no panel at all (the status item already signals
///   recording state via its SF Symbol flip).
/// - Panel is non-activating, appears on all Spaces, survives Stage Manager
///   and Spaces transitions, and never steals focus from the target app.
@MainActor
final class IndicatorController {
    private let viewModel: IndicatorViewModel
    private var panel: NSPanel?

    init(rmsProvider: @escaping () -> Float) {
        self.viewModel = IndicatorViewModel(rmsProvider: rmsProvider)
    }

    func show() {
        let style = Preferences.indicatorStyle
        guard style != .menubar else {
            hide()
            return
        }

        viewModel.start()

        let panel: NSPanel = self.panel ?? makePanel()
        self.panel = panel

        let hostingView = makeHostingView(for: style)
        let targetSize = hostingView.fittingSize
        let hostFrame = NSRect(origin: .zero, size: targetSize)
        hostingView.frame = hostFrame
        panel.setContentSize(targetSize)
        panel.contentView = hostingView

        positionOnScreen(panel: panel)
        panel.orderFrontRegardless()
    }

    /// Switch to transcribing mode: keep panel visible with waiting animation.
    func showTranscribing() {
        viewModel.startTranscribing()
        // Panel stays visible — no hide/show cycle
    }

    func hide() {
        panel?.orderOut(nil)
        viewModel.stop()
    }

    // MARK: - Panel construction

    private func makePanel() -> NSPanel {
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 40),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        p.level = .statusBar
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.backgroundColor = .clear
        p.isOpaque = false
        // Window shadow works with transparent/clear backgrounds because AppKit
        // derives it from the rendered alpha. SwiftUI .shadow() does not
        // contribute to view layout, so if we sized the panel to the bare
        // content it would clip. Let AppKit draw the shadow instead.
        p.hasShadow = true
        p.isMovableByWindowBackground = false
        // Appear on every Space, ride along through full screen and Stage Manager.
        p.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .fullScreenAuxiliary,
            .ignoresCycle
        ]
        return p
    }

    private func makeHostingView(for style: IndicatorStyle) -> NSHostingView<AnyView> {
        let root: AnyView
        switch style {
        case .pill:
            root = AnyView(MiniPillView(viewModel: viewModel))
        case .waveform:
            root = AnyView(ClassicWaveformView(viewModel: viewModel))
        case .floatingCapsule:
            root = AnyView(FloatingCapsuleView(viewModel: viewModel))
        case .menubar:
            root = AnyView(EmptyView())
        }
        let host = NSHostingView(rootView: root)
        host.translatesAutoresizingMaskIntoConstraints = true
        return host
    }

    private func positionOnScreen(panel: NSPanel) {
        // NSScreen.main tracks the screen of the active app's key window and
        // can be nil, so fall back to the first screen. That is good enough
        // for a global indicator: the panel shows up on the display the user
        // is currently working in, and "first" is a sensible fallback when
        // there is no active key window.
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let x = visible.midX - size.width / 2
        let y = visible.maxY - size.height - 12
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
