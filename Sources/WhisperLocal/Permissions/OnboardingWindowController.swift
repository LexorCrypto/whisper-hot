import AppKit

@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    static let hasShownKey = "WhisperLocal.hasShownOnboarding"

    private let permissions: PermissionsCoordinator
    private var window: NSWindow?
    private var previousApp: NSRunningApplication?

    private var micStatusLabel: NSTextField?
    private var micActionButton: NSButton?
    private var axStatusLabel: NSTextField?
    private var axActionButton: NSButton?

    private var refreshTimer: Timer?

    init(permissions: PermissionsCoordinator) {
        self.permissions = permissions
        super.init()
    }

    func show() {
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp = front
        }

        if window == nil {
            buildWindow()
        }

        refreshStates()
        startRefreshTimer()

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Window construction

    private func buildWindow() {
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "Welcome to WhisperLocal"
        newWindow.isReleasedWhenClosed = false
        newWindow.center()
        newWindow.delegate = self

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 540, height: 400))
        newWindow.contentView = content

        let titleLabel = NSTextField(labelWithString: "WhisperLocal needs two permissions")
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        titleLabel.frame = NSRect(x: 24, y: 350, width: 492, height: 24)
        content.addSubview(titleLabel)

        let subtitleLabel = NSTextField(
            labelWithString: "Grant both to enable voice transcription and auto-paste into the active app."
        )
        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.frame = NSRect(x: 24, y: 322, width: 492, height: 20)
        content.addSubview(subtitleLabel)

        // Microphone row
        let micTitle = NSTextField(labelWithString: "Microphone")
        micTitle.font = .systemFont(ofSize: 14, weight: .semibold)
        micTitle.frame = NSRect(x: 24, y: 272, width: 200, height: 20)
        content.addSubview(micTitle)

        let micDescription = NSTextField(
            labelWithString: "Required to capture the audio you want to transcribe."
        )
        micDescription.font = .systemFont(ofSize: 12)
        micDescription.textColor = .secondaryLabelColor
        micDescription.frame = NSRect(x: 24, y: 250, width: 492, height: 18)
        content.addSubview(micDescription)

        let micStatus = NSTextField(labelWithString: "…")
        micStatus.font = .systemFont(ofSize: 12)
        micStatus.frame = NSRect(x: 24, y: 222, width: 320, height: 20)
        content.addSubview(micStatus)
        self.micStatusLabel = micStatus

        let micButton = NSButton(
            title: "Request Access",
            target: self,
            action: #selector(handleMicAction)
        )
        micButton.bezelStyle = .rounded
        micButton.frame = NSRect(x: 370, y: 218, width: 146, height: 28)
        content.addSubview(micButton)
        self.micActionButton = micButton

        // Accessibility row
        let axTitle = NSTextField(labelWithString: "Accessibility")
        axTitle.font = .systemFont(ofSize: 14, weight: .semibold)
        axTitle.frame = NSRect(x: 24, y: 170, width: 200, height: 20)
        content.addSubview(axTitle)

        let axDescription = NSTextField(
            labelWithString: "Required to paste the transcript into whichever app currently has focus."
        )
        axDescription.font = .systemFont(ofSize: 12)
        axDescription.textColor = .secondaryLabelColor
        axDescription.frame = NSRect(x: 24, y: 148, width: 492, height: 18)
        content.addSubview(axDescription)

        let axStatus = NSTextField(labelWithString: "…")
        axStatus.font = .systemFont(ofSize: 12)
        axStatus.frame = NSRect(x: 24, y: 120, width: 320, height: 20)
        content.addSubview(axStatus)
        self.axStatusLabel = axStatus

        let axButton = NSButton(
            title: "Open Settings",
            target: self,
            action: #selector(handleAccessibilityAction)
        )
        axButton.bezelStyle = .rounded
        axButton.frame = NSRect(x: 370, y: 116, width: 146, height: 28)
        content.addSubview(axButton)
        self.axActionButton = axButton

        // Footer
        let footer = NSTextField(
            labelWithString: "You can re-open this window from the WhisperLocal menu at any time."
        )
        footer.font = .systemFont(ofSize: 11)
        footer.textColor = .tertiaryLabelColor
        footer.frame = NSRect(x: 24, y: 42, width: 492, height: 18)
        content.addSubview(footer)

        let closeButton = NSButton(
            title: "Done",
            target: self,
            action: #selector(closeOnboarding)
        )
        closeButton.bezelStyle = .rounded
        closeButton.frame = NSRect(x: 436, y: 12, width: 80, height: 28)
        content.addSubview(closeButton)

        self.window = newWindow
    }

    // MARK: - State refresh

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshStates()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private func refreshStates() {
        let micState = permissions.microphoneState()
        switch micState {
        case .granted:
            micStatusLabel?.stringValue = "✓ Granted"
            micStatusLabel?.textColor = .systemGreen
            micActionButton?.title = "Granted"
            micActionButton?.isEnabled = false
        case .denied:
            micStatusLabel?.stringValue = "✗ Denied — change it in System Settings"
            micStatusLabel?.textColor = .systemRed
            micActionButton?.title = "Open Settings"
            micActionButton?.isEnabled = true
        case .notDetermined:
            micStatusLabel?.stringValue = "Not requested yet"
            micStatusLabel?.textColor = .secondaryLabelColor
            micActionButton?.title = "Request Access"
            micActionButton?.isEnabled = true
        }

        let axGranted = permissions.accessibilityGranted()
        if axGranted {
            axStatusLabel?.stringValue = "✓ Granted"
            axStatusLabel?.textColor = .systemGreen
            axActionButton?.title = "Granted"
            axActionButton?.isEnabled = false
        } else {
            axStatusLabel?.stringValue = "Not granted — enable WhisperLocal in System Settings"
            axStatusLabel?.textColor = .systemOrange
            axActionButton?.title = "Open Settings"
            axActionButton?.isEnabled = true
        }
    }

    // MARK: - Actions

    @objc private func handleMicAction() {
        switch permissions.microphoneState() {
        case .notDetermined:
            Task { @MainActor in
                _ = await self.permissions.requestMicrophone()
                self.refreshStates()
            }
        case .denied, .granted:
            // Handing off to System Settings. Drop previousApp so windowWillClose
            // does not yank focus out of Settings later.
            previousApp = nil
            permissions.openMicrophoneSettings()
        }
    }

    @objc private func handleAccessibilityAction() {
        // First call triggers the system prompt (once per session). We always
        // also open the System Settings pane so the user has a direct path.
        // Drop previousApp for the same reason as the mic handler.
        previousApp = nil
        permissions.promptAccessibility()
        permissions.openAccessibilitySettings()
    }

    @objc private func closeOnboarding() {
        window?.close()
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        refreshTimer?.invalidate()
        refreshTimer = nil
        UserDefaults.standard.set(true, forKey: Self.hasShownKey)

        // Only restore the previously-focused app if WhisperLocal is still the
        // frontmost application at close time. If the user has since moved
        // focus elsewhere (e.g. System Settings, the active paste target),
        // leave them where they are.
        let ourPID = ProcessInfo.processInfo.processIdentifier
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == ourPID {
            previousApp?.activate(options: [])
        }
        previousApp = nil
    }
}
