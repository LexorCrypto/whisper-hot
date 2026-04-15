import AppKit
import ServiceManagement
import SwiftUI

extension Notification.Name {
    /// Posted by SettingsWindowController every time the window is shown, so
    /// the SwiftUI view can re-read Keychain state that may have changed
    /// since the view was first constructed (the hosting view is built once
    /// and reused across open/close cycles).
    static let whisperHotSettingsWillShow = Notification.Name("WhisperHot.settingsWillShow")
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

    // MARK: - Body

    var body: some View {
        TabView {
            recordingTab
                .tabItem { Label("Recording", systemImage: "mic.fill") }
            providersTab
                .tabItem { Label("Providers", systemImage: "key.fill") }
            postProcessingTab
                .tabItem { Label("Post-processing", systemImage: "wand.and.stars") }
            hotkeyTab
                .tabItem { Label("Hotkey", systemImage: "keyboard") }
            historyPrivacyTab
                .tabItem { Label("History & Privacy", systemImage: "clock") }
        }
        .frame(minWidth: 620, idealWidth: 640, maxWidth: 760,
               minHeight: 440, idealHeight: 560, maxHeight: 900)
        .padding(.top, 8)
        .onAppear {
            normalizeStorageValues()
            reloadKeys()
            refreshLaunchAtLoginState()
        }
        .onReceive(NotificationCenter.default.publisher(for: .whisperHotSettingsWillShow)) { _ in
            normalizeStorageValues()
            reloadKeys()
            refreshLaunchAtLoginState()
        }
    }

    // MARK: - Tab: Recording

    private var recordingTab: some View {
        Form {
            Section("Language") {
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
                Text("Passed to every provider as a language hint. Auto-detect uses the provider's own detection.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("After transcription") {
                Toggle("Auto-paste into the active app", isOn: $autoPaste)
                Toggle("Play sound chimes", isOn: $sounds)
                Text("Auto-paste requires Accessibility permission. If nothing pastes, open System Settings → Privacy & Security → Accessibility and re-enable WhisperHot.")
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

            Section("Startup") {
                Toggle("Launch at login", isOn: $launchAtLoginEnabled)
                    .onChange(of: launchAtLoginEnabled) { newValue in
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
        }
        .formStyle(.grouped)
    }

    // MARK: - Tab: Providers

    private var providersTab: some View {
        Form {
            Section("Service") {
                Picker("Provider", selection: $provider) {
                    ForEach(TranscriptionProvider.allCases) { p in
                        Text(p.displayName).tag(p)
                    }
                }
                Text(providerDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Only render the config block for the currently-selected
            // provider. Users of Groq never see an OpenAI key field and
            // vice versa — that was the biggest source of "where is what"
            // confusion in the old flat layout.
            switch provider {
            case .openai:
                apiKeyAndModelSection(
                    title: "OpenAI",
                    account: .openAI,
                    binding: $openAIKey,
                    status: $openAIStatus,
                    placeholder: "sk-..."
                )
            case .openRouter:
                apiKeyAndModelSection(
                    title: "OpenRouter",
                    account: .openRouter,
                    binding: $openRouterKey,
                    status: $openRouterStatus,
                    placeholder: "sk-or-..."
                )
            case .groq:
                apiKeyAndModelSection(
                    title: "Groq",
                    account: .groq,
                    binding: $groqKey,
                    status: $groqStatus,
                    placeholder: "gsk_..."
                )
            case .localWhisper:
                localWhisperSection
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func apiKeyAndModelSection(
        title: String,
        account: Keychain.Account,
        binding: Binding<String>,
        status: Binding<StatusMessage>,
        placeholder: String
    ) -> some View {
        Section("\(title) API Key") {
            apiKeyControls(
                account: account,
                binding: binding,
                status: status,
                placeholder: placeholder
            )
        }
        Section("\(title) Model") {
            modelPicker
        }
    }

    private var localWhisperSection: some View {
        Section("Local whisper.cpp") {
            LabeledContent("Binary") {
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
            LabeledContent("GGML model") {
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
            Text("Install via Homebrew (`brew install whisper-cpp`) or build from source, then download a GGML model from huggingface.co/ggerganov/whisper.cpp.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Tab: Post-processing

    private var postProcessingTab: some View {
        Form {
            Section("LLM cleanup") {
                Toggle("Run LLM cleanup after transcription", isOn: $postProcessingEnabled)
                Text("Sends the raw transcript through an OpenRouter chat model to clean fillers, rewrite for tone, translate, or whatever the preset defines. Costs one extra API call per recording. Uses the OpenRouter key from the Providers tab.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Preset") {
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
            }

            Section("Model") {
                TextField("OpenRouter slug", text: $postProcessingModel, prompt: Text("openai/gpt-4o-mini"))
                    .textFieldStyle(.roundedBorder)
                    .disabled(!postProcessingEnabled)
                Text("Any chat-capable model from the OpenRouter catalog.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Tab: Hotkey

    private var hotkeyTab: some View {
        Form {
            Section("Record / Stop") {
                LabeledContent("Shortcut") {
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
            }

            Section("Fn key (experimental)") {
                Toggle("Use Fn (🌐) key instead", isOn: $fnKeyEnabled)
                    .onChange(of: fnKeyEnabled) { isOn in
                        if isOn {
                            let granted = PermissionsCoordinator().requestInputMonitoring()
                            if !granted {
                                PermissionsCoordinator().openInputMonitoringSettings()
                            }
                        }
                    }

                if fnKeyEnabled {
                    VStack(alignment: .leading, spacing: 6) {
                        Label {
                            Text("macOS reserves Fn for Dictation / Show Emoji / Change Input Source. Open System Settings → Keyboard → \"Press 🌐 key to → Do Nothing\" to avoid duplicate actions.")
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                        }
                        Label {
                            Text("Requires Input Monitoring permission. WhisperHot will need to be relaunched once after you grant it.")
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
        }
        .formStyle(.grouped)
    }

    // MARK: - Tab: History & Privacy

    private var historyPrivacyTab: some View {
        Form {
            Section("Transcript history") {
                Toggle("Keep a local history", isOn: $historyEnabled)

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

                Text("History is encrypted at rest with AES-GCM. The key lives in the macOS Keychain and never syncs to iCloud. File: ~/Library/Application Support/WhisperHot/history.bin.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Audio retention") {
                Picker("Keep recordings", selection: $audioRetention) {
                    ForEach(AudioRetention.allCases) { r in
                        Text(r.displayName).tag(r)
                    }
                }
                Button("Wipe all recorded audio now") {
                    AudioRetentionSweeper.wipeAll()
                }
            }

            Section("Privacy notes") {
                VStack(alignment: .leading, spacing: 6) {
                    Label {
                        Text("Cloud providers (OpenAI, OpenRouter, Groq) receive your audio. Pick Local whisper.cpp in Providers for fully offline transcription.")
                    } icon: {
                        Image(systemName: "cloud.fill")
                            .foregroundColor(.secondary)
                    }
                    Label {
                        Text("Clipboard managers (Paste, Raycast, Alfred) will capture the transcript when it reaches the pasteboard. Disable auto-paste in Recording if that concerns you.")
                    } icon: {
                        Image(systemName: "doc.on.clipboard")
                            .foregroundColor(.secondary)
                    }
                    Label {
                        Text("Raw WAVs live in ~/Library/Caches/WhisperHot/recordings/. API keys and the history encryption key are in the macOS Keychain with iCloud sync disabled.")
                    } icon: {
                        Image(systemName: "folder")
                            .foregroundColor(.secondary)
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
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
