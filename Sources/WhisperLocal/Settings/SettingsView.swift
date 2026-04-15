import AppKit
import ServiceManagement
import SwiftUI

extension Notification.Name {
    /// Posted by SettingsWindowController every time the window is shown, so
    /// the SwiftUI view can re-read Keychain state that may have changed
    /// since the view was first constructed (the hosting view is built once
    /// and reused across open/close cycles).
    static let whisperLocalSettingsWillShow = Notification.Name("WhisperLocal.settingsWillShow")
}

struct SettingsView: View {
    @AppStorage(Preferences.Key.provider) private var provider: TranscriptionProvider = .openai
    @AppStorage(Preferences.Key.modelOpenAI) private var modelOpenAI: String = Preferences.Defaults.modelOpenAI
    @AppStorage(Preferences.Key.modelOpenRouter) private var modelOpenRouter: String = Preferences.Defaults.modelOpenRouter
    @AppStorage(Preferences.Key.modelGroq) private var modelGroq: String = Preferences.Defaults.modelGroq
    @AppStorage(Preferences.Key.localWhisperBinaryPath) private var localBinaryPath: String = ""
    @AppStorage(Preferences.Key.localWhisperModelPath) private var localModelPath: String = ""
    @AppStorage(Preferences.Key.language) private var language: TranscriptionLanguage = .auto
    @AppStorage(Preferences.Key.autoPaste) private var autoPaste: Bool = Preferences.Defaults.autoPaste
    @AppStorage(Preferences.Key.sounds) private var sounds: Bool = Preferences.Defaults.sounds
    @AppStorage(Preferences.Key.indicatorStyle) private var indicatorStyle: IndicatorStyle = .menubar
    @AppStorage(Preferences.Key.postProcessingEnabled) private var postProcessingEnabled: Bool = Preferences.Defaults.postProcessingEnabled
    @AppStorage(Preferences.Key.postProcessingPreset) private var postProcessingPreset: PostProcessingPreset = .cleanup
    @AppStorage(Preferences.Key.postProcessingCustomPrompt) private var postProcessingCustomPrompt: String = ""
    @AppStorage(Preferences.Key.postProcessingModel) private var postProcessingModel: String = Preferences.Defaults.postProcessingModel
    @AppStorage(Preferences.Key.historyEnabled) private var historyEnabled: Bool = Preferences.Defaults.historyEnabled
    @AppStorage(Preferences.Key.historyRetentionDays) private var historyRetentionDays: Int = Preferences.Defaults.historyRetentionDays
    @AppStorage(Preferences.Key.historyMaxEntries) private var historyMaxEntries: Int = Preferences.Defaults.historyMaxEntries
    @AppStorage(Preferences.Key.audioRetention) private var audioRetention: AudioRetention = .immediate
    @AppStorage(Preferences.Key.fnKeyEnabled) private var fnKeyEnabled: Bool = Preferences.Defaults.fnKeyEnabled
    @AppStorage(Preferences.Key.hotkeyKeyCode) private var hotkeyKeyCode: Int = Preferences.Defaults.hotkeyKeyCode
    @AppStorage(Preferences.Key.hotkeyModifiers) private var hotkeyModifiers: Int = Preferences.Defaults.hotkeyModifiers

    @State private var launchAtLoginEnabled: Bool = LaunchAtLoginController.isEnabled
    @State private var launchAtLoginStatus: String = LaunchAtLoginController.statusDescription
    /// When true, the next onChange for `launchAtLoginEnabled` is the
    /// programmatic revert we triggered ourselves, not a fresh user click.
    /// Skip the side effect so we don't re-enter register()/unregister().
    @State private var suppressLaunchAtLoginChange: Bool = false

    @State private var openAIKey: String = ""
    @State private var openAIStatus: StatusMessage = .init(text: "", kind: .secondary)
    @State private var openRouterKey: String = ""
    @State private var openRouterStatus: StatusMessage = .init(text: "", kind: .secondary)
    @State private var groqKey: String = ""
    @State private var groqStatus: StatusMessage = .init(text: "", kind: .secondary)

    private struct StatusMessage {
        enum Kind { case primary, secondary, success, error }
        let text: String
        let kind: Kind

        var color: Color {
            switch kind {
            case .primary: return .primary
            case .secondary: return .secondary
            case .success: return .green
            case .error: return .red
            }
        }
    }

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLoginEnabled)
                    .onChange(of: launchAtLoginEnabled) { newValue in
                        // Skip re-entry from our own programmatic revert.
                        if suppressLaunchAtLoginChange {
                            suppressLaunchAtLoginChange = false
                            return
                        }

                        var failureMessage: String?
                        do {
                            try LaunchAtLoginController.setEnabled(newValue)
                        } catch {
                            failureMessage = LaunchAtLoginController.describe(error: error)
                        }

                        // SMAppService is the source of truth. After any
                        // attempted change (success OR failure) re-read
                        // isEnabled: on success, a `.requiresApproval`
                        // outcome still means isEnabled == false and the
                        // toggle should reflect that, not the user's click.
                        let actual = LaunchAtLoginController.isEnabled
                        if actual != launchAtLoginEnabled {
                            suppressLaunchAtLoginChange = true
                            launchAtLoginEnabled = actual
                        }
                        launchAtLoginStatus = failureMessage ?? LaunchAtLoginController.statusDescription
                    }
                Text(launchAtLoginStatus)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Provider") {
                Picker("Service", selection: $provider) {
                    ForEach(TranscriptionProvider.allCases) { p in
                        Text(p.displayName).tag(p)
                    }
                }
                Text(providerDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("OpenAI API Key") {
                apiKeyControls(
                    account: .openAI,
                    binding: $openAIKey,
                    status: $openAIStatus,
                    placeholder: "sk-..."
                )
            }

            Section("OpenRouter API Key") {
                apiKeyControls(
                    account: .openRouter,
                    binding: $openRouterKey,
                    status: $openRouterStatus,
                    placeholder: "sk-or-..."
                )
            }

            Section("Groq API Key") {
                apiKeyControls(
                    account: .groq,
                    binding: $groqKey,
                    status: $groqStatus,
                    placeholder: "gsk_..."
                )
            }

            Section("Local Whisper (offline)") {
                LabeledContent("whisper.cpp binary") {
                    HStack(spacing: 8) {
                        Text(pathDisplay(localBinaryPath))
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button("Choose…") { pickBinary() }
                        if !localBinaryPath.isEmpty {
                            Button("Clear") { localBinaryPath = "" }
                        }
                    }
                }
                LabeledContent("GGML model file") {
                    HStack(spacing: 8) {
                        Text(pathDisplay(localModelPath))
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button("Choose…") { pickModel() }
                        if !localModelPath.isEmpty {
                            Button("Clear") { localModelPath = "" }
                        }
                    }
                }
                Text("Runs whisper.cpp as a subprocess. Install via Homebrew (`brew install whisper-cpp`) or build from source, then download a GGML model from huggingface.co/ggerganov/whisper.cpp.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Transcription") {
                modelPicker
                Picker("Language", selection: $language) {
                    Text("Auto detect").tag(TranscriptionLanguage.auto)
                    Text("English").tag(TranscriptionLanguage.en)
                    Text("Русский").tag(TranscriptionLanguage.ru)
                    Text("Latviski").tag(TranscriptionLanguage.lv)
                    Text("Deutsch").tag(TranscriptionLanguage.de)
                    Text("Français").tag(TranscriptionLanguage.fr)
                    Text("Español").tag(TranscriptionLanguage.es)
                    Text("Italiano").tag(TranscriptionLanguage.it)
                    Text("Português").tag(TranscriptionLanguage.pt)
                    Text("Polski").tag(TranscriptionLanguage.pl)
                    Text("Türkçe").tag(TranscriptionLanguage.tr)
                    Text("Українська").tag(TranscriptionLanguage.uk)
                    Text("日本語").tag(TranscriptionLanguage.ja)
                    Text("한국어").tag(TranscriptionLanguage.ko)
                    Text("中文").tag(TranscriptionLanguage.zh)
                }
            }

            Section("After transcription") {
                Toggle("Auto-paste into the active app", isOn: $autoPaste)
                Toggle("Play sound chimes", isOn: $sounds)
            }

            Section("Post-processing (optional)") {
                Toggle("Run LLM cleanup after transcription", isOn: $postProcessingEnabled)

                Picker("Preset", selection: $postProcessingPreset) {
                    ForEach(PostProcessingPreset.allCases) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                .disabled(!postProcessingEnabled)

                if postProcessingPreset == .custom {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Custom system prompt")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextEditor(text: $postProcessingCustomPrompt)
                            .font(.system(size: 12))
                            .frame(minHeight: 80)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                            .disabled(!postProcessingEnabled)
                    }
                }

                TextField("Model (OpenRouter slug)", text: $postProcessingModel, prompt: Text("openai/gpt-4o-mini"))
                    .textFieldStyle(.roundedBorder)
                    .disabled(!postProcessingEnabled)

                Text("Uses the OpenRouter API key above. Accepts any chat-capable model slug from the OpenRouter catalog. Adds one extra API call per transcription — turn it off if latency matters.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Indicator") {
                Picker("Style", selection: $indicatorStyle) {
                    ForEach(IndicatorStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.radioGroup)
            }

            Section("Privacy & data") {
                Picker("Audio retention", selection: $audioRetention) {
                    ForEach(AudioRetention.allCases) { r in
                        Text(r.displayName).tag(r)
                    }
                }

                Button("Wipe all recorded audio now") {
                    AudioRetentionSweeper.wipeAll()
                }

                VStack(alignment: .leading, spacing: 6) {
                    Label {
                        Text("Cloud providers (OpenAI, OpenRouter, Groq) receive your audio. Pick \"Local whisper.cpp\" in the Provider section for fully offline transcription.")
                    } icon: {
                        Image(systemName: "cloud.fill")
                            .foregroundColor(.secondary)
                    }
                    Label {
                        Text("Clipboard managers (Paste, Raycast, Alfred) will capture the transcript when it reaches the pasteboard. Disable auto-paste if that concerns you.")
                    } icon: {
                        Image(systemName: "doc.on.clipboard")
                            .foregroundColor(.secondary)
                    }
                    Label {
                        Text("Raw WAVs live in ~/Library/Caches/WhisperLocal/recordings/. API keys and the history encryption key live in the macOS Keychain, written with iCloud sync disabled.")
                    } icon: {
                        Image(systemName: "folder")
                            .foregroundColor(.secondary)
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Section("History") {
                Toggle("Keep a local history of transcripts", isOn: $historyEnabled)

                Picker("Retention", selection: $historyRetentionDays) {
                    Text("Keep forever").tag(0)
                    Text("1 day").tag(1)
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                }
                .disabled(!historyEnabled)

                Stepper(
                    "Max entries: \(historyMaxEntries)",
                    value: $historyMaxEntries,
                    in: 10...1000,
                    step: 10
                )
                .disabled(!historyEnabled)

                Text("History is encrypted at rest with AES-GCM. The key lives in your macOS Keychain and never syncs to iCloud. Records are stored in ~/Library/Application Support/WhisperLocal/history.bin.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Hotkey") {
                LabeledContent("Record / Stop") {
                    HStack(spacing: 8) {
                        HotkeyRecorderView(
                            keyCode: $hotkeyKeyCode,
                            modifiers: $hotkeyModifiers,
                            isDisabled: fnKeyEnabled
                        )
                        Button("Reset") {
                            hotkeyKeyCode = Preferences.Defaults.hotkeyKeyCode
                            hotkeyModifiers = Preferences.Defaults.hotkeyModifiers
                        }
                    }
                }
                .disabled(fnKeyEnabled)

                Text(fnKeyEnabled
                     ? "The Fn (🌐) transport is active — the combo above is disabled. Turn off the Fn toggle below to use a regular key combo."
                     : "Click the field and press a new combo. Requires at least one modifier (⌘/⌥/⌃/⇧). Press ⎋ to cancel.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Toggle("Use Fn (🌐) key instead (experimental)", isOn: $fnKeyEnabled)
                    .onChange(of: fnKeyEnabled) { isOn in
                        if isOn {
                            // Surface the Input Monitoring prompt as soon as
                            // the user opts in. If macOS hasn't granted it
                            // yet this also opens the System Settings pane.
                            let granted = PermissionsCoordinator().requestInputMonitoring()
                            if !granted {
                                PermissionsCoordinator().openInputMonitoringSettings()
                            }
                        }
                    }

                if fnKeyEnabled {
                    VStack(alignment: .leading, spacing: 6) {
                        Label {
                            Text("macOS reserves Fn for Dictation / Show Emoji / Change Input Source. There is no public API to rebind it. Open System Settings → Keyboard → \"Press 🌐 key to → Do Nothing\" to avoid duplicate actions.")
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                        }
                        Label {
                            Text("Requires Input Monitoring permission. WhisperLocal will need to be relaunched once after you grant it.")
                        } icon: {
                            Image(systemName: "lock.shield")
                                .foregroundColor(.secondary)
                        }
                        Button("Open Input Monitoring settings") {
                            PermissionsCoordinator().openInputMonitoringSettings()
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }

            Section {
                Text("Preferences live in ~/Library/Preferences/. API keys are stored separately in the macOS Keychain. Local Whisper runs entirely on this Mac — no bytes leave the machine.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 620, height: 1220)
        .onAppear {
            normalizeStorageValues()
            reloadKeys()
            refreshLaunchAtLoginState()
        }
        .onReceive(NotificationCenter.default.publisher(for: .whisperLocalSettingsWillShow)) { _ in
            normalizeStorageValues()
            reloadKeys()
            refreshLaunchAtLoginState()
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var modelPicker: some View {
        switch provider {
        case .openai:
            Picker("Model", selection: $modelOpenAI) {
                ForEach(Preferences.availableOpenAIModels) { m in
                    Text(m.displayName).tag(m.id)
                }
            }
        case .openRouter:
            Picker("Model", selection: $modelOpenRouter) {
                ForEach(Preferences.availableOpenRouterModels) { m in
                    Text(m.displayName).tag(m.id)
                }
            }
        case .groq:
            Picker("Model", selection: $modelGroq) {
                ForEach(Preferences.availableGroqModels) { m in
                    Text(m.displayName).tag(m.id)
                }
            }
        case .localWhisper:
            LabeledContent("Model") {
                Text(localModelPath.isEmpty ? "not set" : URL(fileURLWithPath: localModelPath).lastPathComponent)
                    .font(.caption)
                    .foregroundColor(localModelPath.isEmpty ? .red : .secondary)
            }
        }
    }

    @ViewBuilder
    private func apiKeyControls(
        account: Keychain.Account,
        binding: Binding<String>,
        status: Binding<StatusMessage>,
        placeholder: String
    ) -> some View {
        SecureField("API Key", text: binding, prompt: Text(placeholder))
            .textFieldStyle(.roundedBorder)
        HStack(spacing: 8) {
            Button("Save") {
                let trimmed = binding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    status.wrappedValue = StatusMessage(text: "Key is empty.", kind: .error)
                    return
                }
                do {
                    try Keychain.save(apiKey: trimmed, account: account)
                    status.wrappedValue = StatusMessage(text: "Saved to Keychain.", kind: .success)
                } catch {
                    status.wrappedValue = StatusMessage(text: "Save failed: \(error.localizedDescription)", kind: .error)
                }
            }
            Button("Delete") {
                do {
                    try Keychain.delete(account: account)
                    binding.wrappedValue = ""
                    status.wrappedValue = StatusMessage(text: "Deleted from Keychain.", kind: .success)
                } catch {
                    status.wrappedValue = StatusMessage(text: "Delete failed: \(error.localizedDescription)", kind: .error)
                }
            }
            Spacer()
            Text(status.wrappedValue.text)
                .font(.caption)
                .foregroundColor(status.wrappedValue.color)
        }
    }

    // MARK: - Helpers

    private var providerDescription: String {
        switch provider {
        case .openai:
            return "Dedicated STT endpoint. Most accurate, most expensive."
        case .openRouter:
            return "Routes audio to chat models like GPT-4o Audio Preview via /chat/completions. One key, many models."
        case .groq:
            return "OpenAI-compatible STT mirror. Whisper large-v3-turbo is roughly 10× faster and much cheaper than OpenAI direct."
        case .localWhisper:
            return "Runs whisper.cpp on your Mac via subprocess. Fully offline, no API key, no network."
        }
    }

    private func pathDisplay(_ path: String) -> String {
        path.isEmpty ? "not set" : path
    }

    private func refreshLaunchAtLoginState() {
        // Programmatic writes to launchAtLoginEnabled MUST go through the
        // suppression flag, otherwise .onChange fires and calls setEnabled()
        // again — turning a passive resync into an active round-trip to
        // SMAppService. This catches both the onAppear path and the
        // settings-will-show notification.
        let actual = LaunchAtLoginController.isEnabled
        if actual != launchAtLoginEnabled {
            suppressLaunchAtLoginChange = true
            launchAtLoginEnabled = actual
        }
        launchAtLoginStatus = LaunchAtLoginController.statusDescription
    }

    private func normalizeStorageValues() {
        if !Preferences.availableOpenAIModelIDs.contains(modelOpenAI) {
            modelOpenAI = Preferences.Defaults.modelOpenAI
        }
        if !Preferences.availableOpenRouterModelIDs.contains(modelOpenRouter) {
            modelOpenRouter = Preferences.Defaults.modelOpenRouter
        }
        if !Preferences.availableGroqModelIDs.contains(modelGroq) {
            modelGroq = Preferences.Defaults.modelGroq
        }
    }

    // MARK: - Keychain reload

    private func reloadKeys() {
        (openAIKey, openAIStatus) = loadKey(account: .openAI)
        (openRouterKey, openRouterStatus) = loadKey(account: .openRouter)
        (groqKey, groqStatus) = loadKey(account: .groq)
    }

    private func loadKey(account: Keychain.Account) -> (String, StatusMessage) {
        do {
            let key = try Keychain.readAPIKey(account: account)
            return (key, StatusMessage(text: "Loaded from Keychain.", kind: .secondary))
        } catch Keychain.KeychainError.itemNotFound {
            return ("", StatusMessage(text: "No key saved yet.", kind: .secondary))
        } catch {
            return ("", StatusMessage(text: "Load failed: \(error.localizedDescription)", kind: .error))
        }
    }

    // MARK: - File pickers

    private func pickBinary() {
        if let picked = runOpenPanel(
            title: "Select whisper.cpp executable",
            initial: localBinaryPath,
            filesOnly: true
        ) {
            localBinaryPath = picked
        }
    }

    private func pickModel() {
        if let picked = runOpenPanel(
            title: "Select GGML model file",
            initial: localModelPath,
            filesOnly: true
        ) {
            localModelPath = picked
        }
    }

    private func runOpenPanel(title: String, initial: String, filesOnly: Bool) -> String? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseFiles = filesOnly
        panel.canChooseDirectories = !filesOnly
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        if !initial.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: initial).deletingLastPathComponent()
        }
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
}
