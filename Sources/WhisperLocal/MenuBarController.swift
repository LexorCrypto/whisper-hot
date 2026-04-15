import AppKit

@MainActor
final class MenuBarController: NSObject {
    private enum RecorderState {
        case idle
        case recording
        case transcribing
    }

    private let statusItem: NSStatusItem
    private let settingsWindowController = SettingsWindowController()
    private let audioRecorder = AudioRecorder()
    private let hotkeyManager = HotkeyManager()
    private let fnKeyMonitor = FnKeyMonitor()
    private let pasteService = PasteService()
    private let soundPlayer = SoundPlayer()
    private let permissionsCoordinator = PermissionsCoordinator()
    private let historyStore = HistoryStore()
    private lazy var onboardingWindowController = OnboardingWindowController(
        permissions: permissionsCoordinator
    )
    private lazy var historyWindowController = HistoryWindowController(store: historyStore)
    private lazy var indicatorController = IndicatorController(
        rmsProvider: { [audioRecorder] in audioRecorder.currentRMS }
    )
    /// The concrete TranscriptionService is chosen at transcription time
    /// based on `Preferences.provider`, so switching providers in Settings
    /// takes effect on the very next recording without any restart.
    private var recordMenuItem: NSMenuItem?
    private var state: RecorderState = .idle
    private var isStartingRecording = false
    /// The app that was frontmost when recording started. Used by PasteService
    /// to verify the paste target is still focused when the transcription
    /// completes. Nil means "no valid target" (e.g., WhisperLocal was frontmost).
    private var recordingTarget: NSRunningApplication?

    /// The WAV file the current recording is producing. Captured so
    /// finishTranscription can delete it per the audio retention policy.
    private var currentRecordingURL: URL?

    /// Sticky banner at the top of the status menu that surfaces the last
    /// post-processing error without stealing focus. Cleared on: any new
    /// recording start, a successful transcription, or a run with
    /// post-processing disabled. Does NOT time out on its own.
    private var postProcessingErrorMenuItem: NSMenuItem?
    private var postProcessingErrorSeparator: NSMenuItem?

    /// While Fn is enabled but `fnKeyMonitor.start()` keeps failing (usually
    /// because Input Monitoring permission has not been granted yet), this
    /// timer polls every few seconds. It invalidates itself as soon as Fn
    /// starts successfully or the user disables the toggle.
    private var fnRetryTimer: Timer?

    /// True while the Settings hotkey recorder is armed. The Carbon hotkey
    /// is temporarily released so pressing the currently-bound combo during
    /// capture doesn't double as a real record/stop command, and the
    /// UserDefaults observer skips intermediate re-registrations while the
    /// user is mid-combo.
    private var isHotkeyRecorderArmed = false

    /// NotificationCenter observer tokens held so we can removeObserver on
    /// deinit. MenuBarController lives for the app lifetime in practice,
    /// so this is defensive hygiene rather than leak prevention.
    private var notificationTokens: [NSObjectProtocol] = []

    private enum TranscriptionOutcome: Sendable {
        case success(TranscriptionResult)
        case failure(String)
    }

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureButton(recording: false)
        buildMenu()

        audioRecorder.onAutoStop = { [weak self] in
            MainActor.assumeIsolated {
                self?.handleAutoStop()
            }
        }
        hotkeyManager.onHotkey = { [weak self] in
            MainActor.assumeIsolated {
                self?.toggleRecording(nil)
            }
        }

        fnKeyMonitor.onFnKeyPressed = { [weak self] in
            self?.toggleRecording(nil)
        }

        // React to Settings toggling the experimental Fn-key option or
        // changing the hotkey combo at runtime.
        let defaultsToken = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // While the recorder is mid-capture, intermediate @AppStorage
                // writes would otherwise try to re-register a half-new combo.
                // The disarm handler does the final sync.
                if self.isHotkeyRecorderArmed { return }
                self.syncHotkeyBindings()
            }
        }
        notificationTokens.append(defaultsToken)

        // Recorder arm/disarm uses synchronous delivery (queue: nil) so the
        // Carbon hotkey is released before the user's very next keystroke
        // can reach the live handler. Both observers run on the main thread
        // because the poster is always on the main thread.
        let armToken = NotificationCenter.default.addObserver(
            forName: .whisperLocalHotkeyRecorderDidArm,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleRecorderArm()
            }
        }
        notificationTokens.append(armToken)

        let disarmToken = NotificationCenter.default.addObserver(
            forName: .whisperLocalHotkeyRecorderDidDisarm,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleRecorderDisarm()
            }
        }
        notificationTokens.append(disarmToken)

        syncHotkeyBindings()

        // Enforce history retention on launch so aged records from prior
        // sessions are dropped even if the user last ran the app with
        // `historyRetentionDays = 0` and then changed it to a finite value.
        do {
            try historyStore.pruneNow()
        } catch {
            NSLog("WhisperLocal: history prune at launch failed → \(error.localizedDescription)")
        }

        maybeShowOnboarding()
    }

    deinit {
        // Defensive cleanup — MenuBarController normally lives for the app
        // lifetime, but explicit teardown keeps tests and future refactors
        // sane.
        for token in notificationTokens {
            NotificationCenter.default.removeObserver(token)
        }
        fnRetryTimer?.invalidate()
    }

    /// Single source of truth for the current hotkey transport. Fn and the
    /// Carbon ⌥⌘5 combo are mutually exclusive — the Settings toggle says
    /// "Use Fn instead", so we actually swap transports at runtime.
    ///
    /// Critical invariant: the user must ALWAYS have a working keyboard
    /// trigger. So when Fn is requested we try to start the monitor FIRST,
    /// and only unregister Carbon on success. On failure the Carbon
    /// fallback stays registered and a retry timer polls until Fn becomes
    /// available (e.g. after the user grants Input Monitoring in Settings).
    private func syncHotkeyBindings() {
        fnRetryTimer?.invalidate()
        fnRetryTimer = nil

        let combo = Preferences.hotkeyCombo
        let comboLabel = HotkeyFormatter.format(
            keyCode: Preferences.hotkeyKeyCode,
            modifiers: Preferences.hotkeyModifiers
        )

        if Preferences.fnKeyEnabled {
            if fnKeyMonitor.start() {
                hotkeyManager.unregister()
            } else {
                // Fn couldn't start. Make sure Carbon is registered as
                // fallback and schedule a retry.
                if !hotkeyManager.register(combo: combo) {
                    NSLog("WhisperLocal: failed to register Carbon fallback hotkey \(comboLabel)")
                }
                NSLog("WhisperLocal: Fn monitor unavailable (likely Input Monitoring permission pending). Carbon \(comboLabel) remains active; retrying every 3s.")
                scheduleFnRetryTimer()
            }
        } else {
            fnKeyMonitor.stop()
            if !hotkeyManager.register(combo: combo) {
                NSLog("WhisperLocal: failed to register hotkey \(comboLabel)")
            }
        }
    }

    /// Called synchronously when the Settings recorder begins capturing.
    /// Releases the active Carbon hotkey so pressing the currently-bound
    /// combo during capture doesn't also toggle a real recording. Fn
    /// transport is left alone — the recorder UI is disabled whenever Fn
    /// is the active transport, so there is nothing to pause there.
    private func handleRecorderArm() {
        isHotkeyRecorderArmed = true
        fnRetryTimer?.invalidate()
        fnRetryTimer = nil
        hotkeyManager.unregister()
    }

    /// Called synchronously when the recorder finishes (commit, cancel,
    /// window close, or external disable). Re-applies preferences, which
    /// picks up whatever new combo the user just captured.
    private func handleRecorderDisarm() {
        isHotkeyRecorderArmed = false
        syncHotkeyBindings()
    }

    private func scheduleFnRetryTimer() {
        dispatchPrecondition(condition: .onQueue(.main))
        let t = Timer(timeInterval: 3.0, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else {
                    timer.invalidate()
                    return
                }
                // User turned Fn off while we were polling — stop.
                guard Preferences.fnKeyEnabled else {
                    timer.invalidate()
                    self.fnRetryTimer = nil
                    return
                }
                // Try to start. On success, retire Carbon and stop polling.
                if self.fnKeyMonitor.start() {
                    self.hotkeyManager.unregister()
                    NSLog("WhisperLocal: Fn monitor recovered; Carbon fallback retired.")
                    timer.invalidate()
                    self.fnRetryTimer = nil
                }
            }
        }
        t.tolerance = 1.0
        RunLoop.main.add(t, forMode: .common)
        fnRetryTimer = t
    }

    private func maybeShowOnboarding() {
        let hasShown = UserDefaults.standard.bool(forKey: OnboardingWindowController.hasShownKey)
        if !hasShown {
            onboardingWindowController.show()
        }
    }

    // MARK: - UI construction

    private func configureButton(recording: Bool) {
        guard let button = statusItem.button else { return }
        let symbolName = recording ? "mic.fill" : "mic"
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "WhisperLocal") {
            image.isTemplate = true
            button.image = image
        } else {
            button.title = recording ? "● REC" : "WL"
        }
    }

    private func buildMenu() {
        let menu = NSMenu()

        // Hidden by default; revealed on post-processing failure.
        let errorItem = NSMenuItem(
            title: "⚠ Post-processing failed",
            action: #selector(postProcessingErrorTapped(_:)),
            keyEquivalent: ""
        )
        errorItem.target = self
        errorItem.isHidden = true
        menu.addItem(errorItem)
        self.postProcessingErrorMenuItem = errorItem

        let errorSeparator = NSMenuItem.separator()
        errorSeparator.isHidden = true
        menu.addItem(errorSeparator)
        self.postProcessingErrorSeparator = errorSeparator

        let recordItem = NSMenuItem(
            title: "Start Recording",
            action: #selector(toggleRecording(_:)),
            keyEquivalent: ""
        )
        recordItem.target = self
        menu.addItem(recordItem)
        self.recordMenuItem = recordItem

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings(_:)),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        let historyItem = NSMenuItem(
            title: "History…",
            action: #selector(openHistory(_:)),
            keyEquivalent: ""
        )
        historyItem.target = self
        menu.addItem(historyItem)

        let onboardingItem = NSMenuItem(
            title: "Onboarding & Permissions…",
            action: #selector(openOnboarding(_:)),
            keyEquivalent: ""
        )
        onboardingItem.target = self
        menu.addItem(onboardingItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit WhisperLocal",
            action: #selector(quit(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Actions

    @objc private func toggleRecording(_ sender: Any?) {
        switch state {
        case .recording:
            stopRecordingFromMenu()
        case .transcribing:
            NSLog("WhisperLocal: hotkey ignored — transcription in flight")
        case .idle:
            guard !isStartingRecording else { return }
            isStartingRecording = true
            Task { @MainActor in
                defer { self.isStartingRecording = false }
                // Single source of truth for mic permission — the same
                // PermissionsCoordinator the onboarding window uses, so
                // Block 4's duplicate logic in AudioRecorder is gone.
                let granted = await self.permissionsCoordinator.requestMicrophone()
                if granted {
                    self.startRecordingFromMenu()
                } else {
                    NSLog("WhisperLocal: microphone access denied")
                    self.showMicrophoneDeniedAlert()
                }
            }
        }
    }

    private func startRecordingFromMenu() {
        // Any new recording attempt clears a stale post-processing banner
        // from a previous run. The new transcription is the authoritative
        // state going forward.
        setPostProcessingError(nil)
        captureRecordingTarget()
        do {
            let url = try audioRecorder.startRecording()
            currentRecordingURL = url
            // Tell the retention sweeper not to delete the in-flight WAV
            // if the user hits "Wipe all" mid-session.
            AudioRetentionSweeper.activeRecordingURL = url
            NSLog("WhisperLocal: recording → \(url.path)")
            state = .recording
            recordMenuItem?.title = "Stop Recording"
            configureButton(recording: true)
            indicatorController.show()
            // Play AFTER the engine is armed so the chime is an honest
            // "recording started" signal. On open-mic/speaker setups the
            // chime may land in the first ~200ms of the WAV; Whisper treats
            // it as leading non-speech and the transcript is unaffected.
            playChimeIfEnabled(.start)
        } catch {
            NSLog("WhisperLocal: start error → \(error.localizedDescription)")
            recordingTarget = nil
            currentRecordingURL = nil
            AudioRetentionSweeper.activeRecordingURL = nil
        }
    }

    private func playChimeIfEnabled(_ chime: SoundPlayer.Chime) {
        if Preferences.sounds {
            soundPlayer.play(chime)
        }
    }

    private func makeTranscriptionService(for provider: TranscriptionProvider) -> TranscriptionService {
        switch provider {
        case .openai:
            return OpenAICompatibleSTTProvider(
                endpoint: URL(string: "https://api.openai.com/v1/audio/transcriptions")!,
                model: Preferences.modelOpenAI,
                apiKeyProvider: { try Keychain.readAPIKey(account: .openAI) }
            )
        case .openRouter:
            return OpenRouterAudioProvider(
                model: Preferences.modelOpenRouter,
                apiKeyProvider: { try Keychain.readAPIKey(account: .openRouter) }
            )
        case .groq:
            return OpenAICompatibleSTTProvider(
                endpoint: URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!,
                model: Preferences.modelGroq,
                apiKeyProvider: { try Keychain.readAPIKey(account: .groq) }
            )
        case .localWhisper:
            return LocalWhisperProvider(
                binaryPath: Preferences.localWhisperBinaryPath,
                modelPath: Preferences.localWhisperModelPath
            )
        }
    }

    private func captureRecordingTarget() {
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            recordingTarget = front
            if let bid = front?.bundleIdentifier {
                NSLog("WhisperLocal: paste target snapshot → \(bid)")
            }
        } else {
            recordingTarget = nil
            NSLog("WhisperLocal: paste target snapshot → none (WhisperLocal is frontmost)")
        }
    }

    private func stopRecordingFromMenu() {
        do {
            let url = try audioRecorder.stopRecording()
            NSLog("WhisperLocal: saved → \(url.path)")
            configureButton(recording: false)
            indicatorController.hide()
            playChimeIfEnabled(.stop)
            kickOffTranscription(audioURL: url)
        } catch {
            NSLog("WhisperLocal: stop error → \(error.localizedDescription)")
            state = .idle
            recordMenuItem?.title = "Start Recording"
            configureButton(recording: false)
            indicatorController.hide()
            recordingTarget = nil
            currentRecordingURL = nil
            AudioRetentionSweeper.activeRecordingURL = nil
        }
    }

    private func handleAutoStop() {
        // Recorder stopped itself (e.g. audio configuration change). There is no
        // meaningful partial recording to transcribe — just return the menu to idle.
        state = .idle
        recordMenuItem?.title = "Start Recording"
        configureButton(recording: false)
        indicatorController.hide()
        recordingTarget = nil
        currentRecordingURL = nil
        AudioRetentionSweeper.activeRecordingURL = nil
    }

    private func kickOffTranscription(audioURL: URL) {
        state = .transcribing
        recordMenuItem?.title = "Transcribing…"

        let service = makeTranscriptionService(for: Preferences.provider)
        var options = TranscriptionOptions()
        options.model = Preferences.currentModel
        options.language = Preferences.language

        // Snapshot post-processing configuration on the main actor before
        // handing it off to the detached task. If post-processing is
        // disabled the snapshot is nil and the task skips the extra hop.
        let postProcessor: LLMPostProcessor? = Preferences.postProcessingEnabled
            ? LLMPostProcessor(
                apiKeyProvider: { try Keychain.readAPIKey(account: .openRouter) }
              )
            : nil
        let postProcessingOptions: PostProcessingOptions? = Preferences.postProcessingEnabled
            ? Preferences.currentPostProcessingOptions
            : nil

        // Run the transcription off the main actor so disk I/O (Data(contentsOf:))
        // and multipart body construction don't block the UI thread. The
        // optional post-processing step runs on the same detached task
        // before the result is handed back to the main actor.
        Task.detached(priority: .userInitiated) { [weak self] in
            let outcome: TranscriptionOutcome
            do {
                let raw = try await service.transcribe(audioURL: audioURL, options: options)

                var finalResult = raw

                if let postProcessor, let ppOptions = postProcessingOptions {
                    do {
                        let processed = try await postProcessor.process(
                            text: raw.text,
                            options: ppOptions
                        )
                        finalResult = TranscriptionResult(
                            text: processed,
                            providerModel: raw.providerModel,
                            postProcessing: .succeeded(
                                model: ppOptions.model,
                                preset: ppOptions.preset.rawValue
                            )
                        )
                    } catch {
                        // Soft-fail: log, keep the raw transcript, and mark the
                        // failure in the outcome so finishTranscription can
                        // surface it visibly to the user.
                        NSLog("WhisperLocal: post-processing failed → \(error.localizedDescription)")
                        finalResult = TranscriptionResult(
                            text: raw.text,
                            providerModel: raw.providerModel,
                            postProcessing: .failed(reason: error.localizedDescription)
                        )
                    }
                }

                outcome = .success(finalResult)
            } catch {
                outcome = .failure(error.localizedDescription)
            }
            await self?.finishTranscription(outcome: outcome)
        }
    }

    private func finishTranscription(outcome: TranscriptionOutcome) {
        state = .idle
        recordMenuItem?.title = "Start Recording"
        let target = recordingTarget
        recordingTarget = nil
        let lastAudioURL = currentRecordingURL
        currentRecordingURL = nil
        switch outcome {
        case .success(let result):
            NSLog("WhisperLocal: transcript (\(result.providerModel)) → \(result.text)")
            if case .succeeded(let model, let preset) = result.postProcessing {
                NSLog("WhisperLocal: post-processed via \(model) (\(preset))")
            }
            if Preferences.autoPaste {
                let pasteOutcome = pasteService.deliver(text: result.text, targetApp: target)
                NSLog("WhisperLocal: paste outcome → \(pasteOutcome.description)")
            } else {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                _ = pasteboard.setString(result.text, forType: .string)
                NSLog("WhisperLocal: copied to clipboard (auto-paste disabled in settings)")
            }
            playChimeIfEnabled(.done)

            // Non-modal signal: post-processing failure shows up as a
            // sticky banner at the top of the status menu. Never steals
            // focus from the app the user just pasted into.
            switch result.postProcessing {
            case .failed(let reason):
                setPostProcessingError(reason)
            case .succeeded, .none:
                setPostProcessingError(nil)
            }

            // Persist to encrypted history if the user opted in.
            var historyAppendSucceeded = true
            if Preferences.historyEnabled {
                let record = TranscriptRecord(
                    text: result.text,
                    providerModel: result.providerModel,
                    postProcessing: result.postProcessing
                )
                do {
                    try historyStore.append(record)
                } catch {
                    historyAppendSucceeded = false
                    NSLog("WhisperLocal: history append failed → \(error.localizedDescription)")
                }
            }

            // Retention — on success, `.immediate` removes the WAV right away
            // UNLESS the user asked for history and that append failed. In
            // that case the raw WAV is the only remaining recovery artifact,
            // so we keep it for the startup sweep to clean up later.
            let historyOK = !Preferences.historyEnabled || historyAppendSucceeded
            if Preferences.audioRetention == .immediate, historyOK, let url = lastAudioURL {
                AudioRetentionSweeper.delete(url)
            }
        case .failure(let message):
            NSLog("WhisperLocal: transcription error → \(message)")
            // Failure path intentionally does NOT delete the audio file:
            // leaving it gives the startup sweep (or the user) a retry
            // window. The sweep still enforces the configured max age.
        }

        // The recording is no longer in flight.
        AudioRetentionSweeper.activeRecordingURL = nil
    }

    private func setPostProcessingError(_ error: String?) {
        if let error {
            let truncated = error.count > 80 ? String(error.prefix(80)) + "…" : error
            postProcessingErrorMenuItem?.title = "⚠ Post-processing: \(truncated)"
            postProcessingErrorMenuItem?.toolTip = error
            postProcessingErrorMenuItem?.isHidden = false
            postProcessingErrorSeparator?.isHidden = false
        } else {
            postProcessingErrorMenuItem?.isHidden = true
            postProcessingErrorSeparator?.isHidden = true
            postProcessingErrorMenuItem?.toolTip = nil
        }
    }

    @objc private func postProcessingErrorTapped(_ sender: Any?) {
        settingsWindowController.show()
    }

    @objc private func openSettings(_ sender: Any?) {
        settingsWindowController.show()
    }

    @objc private func openOnboarding(_ sender: Any?) {
        onboardingWindowController.show()
    }

    @objc private func openHistory(_ sender: Any?) {
        historyWindowController.show()
    }

    @objc private func quit(_ sender: Any?) {
        NSApp.terminate(nil)
    }

    // MARK: - Error UI

    private func showMicrophoneDeniedAlert() {
        let alert = NSAlert()
        alert.messageText = "Microphone access denied"
        alert.informativeText = """
        WhisperLocal needs microphone access to record audio.
        Open System Settings → Privacy & Security → Microphone and enable WhisperLocal.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            permissionsCoordinator.openMicrophoneSettings()
        }
    }

}
