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
    @AppStorage(Preferences.Key.contextRoutingEnabled) private var contextRoutingEnabled: Bool = Preferences.Defaults.contextRoutingEnabled
    @AppStorage(Preferences.Key.postProcessingProvider) private var ppProvider: PostProcessingProvider = .openRouter
    @AppStorage(Preferences.Key.postProcessingModelOpenAI) private var ppModelOpenAI: String = Preferences.Defaults.postProcessingModelOpenAI
    @AppStorage(Preferences.Key.postProcessingModelGroq) private var ppModelGroq: String = Preferences.Defaults.postProcessingModelGroq
    @AppStorage(Preferences.Key.customEndpointURL) private var customEndpointURL: String = Preferences.Defaults.customEndpointURL
    @AppStorage(Preferences.Key.customEndpointModel) private var customEndpointModel: String = Preferences.Defaults.customEndpointModel
    @AppStorage(Preferences.Key.appLanguage) private var appLanguage: AppLanguage = .ru

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
    @State private var polzaAIKey: String = ""
    @State private var polzaAIStatus: StatusMessage = .init(text: "", kind: .secondary)
    @State private var customEndpointKey: String = ""
    @State private var customEndpointKeyStatus: StatusMessage = .init(text: "", kind: .secondary)
    @State private var contextRules: [ContextRule] = Preferences.contextRules
    @StateObject private var whisperInstaller = WhisperInstaller()
    @StateObject private var updateChecker = UpdateChecker()

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

    private enum SettingsSection: String, CaseIterable, Identifiable {
        case recording
        case providers
        case postProcessing
        case hotkey
        case historyPrivacy
        case updates

        var id: String { rawValue }

        var label: String {
            switch self {
            case .recording: return L10n.recording
            case .providers: return L10n.providers
            case .postProcessing: return L10n.postProcessing
            case .hotkey: return L10n.hotkey
            case .historyPrivacy: return L10n.historyPrivacy
            case .updates: return L10n.lang == .ru ? "Обновления" : "Updates"
            }
        }

        var icon: String {
            switch self {
            case .recording: return "mic.fill"
            case .providers: return "key.fill"
            case .postProcessing: return "wand.and.stars"
            case .hotkey: return "keyboard"
            case .historyPrivacy: return "clock"
            case .updates: return "arrow.triangle.2.circlepath"
            }
        }
    }

    @State private var selectedSection: SettingsSection = .recording

    // MARK: - Body

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selectedSection) { section in
                Label(section.label, systemImage: section.icon)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            ScrollView {
                detailContent
                    .padding()
            }
        }
        .frame(minWidth: 700, idealWidth: 740, maxWidth: 900,
               minHeight: 480, idealHeight: 600, maxHeight: 900)
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

    @ViewBuilder
    private var detailContent: some View {
        switch selectedSection {
        case .recording: recordingTab
        case .providers: providersTab
        case .postProcessing: postProcessingTab
        case .hotkey: hotkeyTab
        case .historyPrivacy: historyPrivacyTab
        case .updates: updatesTab
        }
    }

    // MARK: - Tab: Recording

    private var recordingTab: some View {
        Form {
            Section(L10n.interfaceLanguage) {
                Picker(L10n.interfaceLanguage, selection: $appLanguage) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
            }

            Section(L10n.language) {
                Picker(L10n.language, selection: $language) {
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
                Text(L10n.languageHint)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section(L10n.afterTranscription) {
                Toggle(L10n.autoPasteToggle, isOn: $autoPaste)
                Toggle(L10n.soundChimesToggle, isOn: $sounds)
                Text(L10n.autoPasteHint)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section(L10n.indicator) {
                Picker(L10n.style, selection: $indicatorStyle) {
                    ForEach(IndicatorStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.radioGroup)
            }

            Section(L10n.startup) {
                Toggle(L10n.launchAtLogin, isOn: $launchAtLoginEnabled)
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
            Section(L10n.service) {
                Picker(L10n.provider, selection: $provider) {
                    ForEach(TranscriptionProvider.allCases) { p in
                        Text(p.displayName).tag(p)
                    }
                }
                Text(L10n.providerDescription(for: provider))
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
            case .polzaAI:
                Section("Polza.ai API Key") {
                    apiKeyControls(
                        account: .polzaAI,
                        binding: $polzaAIKey,
                        status: $polzaAIStatus,
                        placeholder: "plz_..."
                    )
                }
                Section("Polza.ai Model") {
                    modelPicker
                }
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
            // Status + one-click install
            HStack {
                switch whisperInstaller.status {
                case .installed:
                    Label(L10n.lang == .ru ? "Установлено" : "Installed", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                case .notInstalled:
                    Label(L10n.lang == .ru ? "Не установлено" : "Not installed", systemImage: "xmark.circle")
                        .foregroundColor(.secondary)
                case .installing(let step):
                    ProgressView()
                        .controlSize(.small)
                    Text(step)
                        .font(.caption)
                        .foregroundColor(.secondary)
                case .downloading(let progress):
                    ProgressView(value: progress)
                        .frame(width: 120)
                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .font(.caption)
                }
                Spacer()
                switch whisperInstaller.status {
                case .notInstalled, .failed:
                    Button(L10n.lang == .ru ? "Установить" : "Install") {
                        Task { await whisperInstaller.install() }
                    }
                case .installing, .downloading:
                    Button(L10n.lang == .ru ? "Отмена" : "Cancel") {
                        whisperInstaller.cancel()
                    }
                case .installed:
                    EmptyView()
                }
            }

            // Manual path overrides (advanced)
            DisclosureGroup(L10n.lang == .ru ? "Ручная настройка путей" : "Manual path configuration") {
                LabeledContent(L10n.binary) {
                    HStack(spacing: 8) {
                        Text(pathDisplay(localBinaryPath))
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button(L10n.choose) { pickBinary() }
                        if !localBinaryPath.isEmpty {
                            Button(L10n.clear) { localBinaryPath = "" }
                        }
                    }
                }
                LabeledContent(L10n.ggmlModel) {
                    HStack(spacing: 8) {
                        Text(pathDisplay(localModelPath))
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button(L10n.choose) { pickModel() }
                        if !localModelPath.isEmpty {
                            Button(L10n.clear) { localModelPath = "" }
                        }
                    }
                }
            }

            Text(L10n.lang == .ru
                ? "Нажмите «Установить» для автоматической установки whisper-cpp через Homebrew и загрузки модели ggml-base (~142 МБ). Или настройте пути вручную."
                : "Click Install to automatically set up whisper-cpp via Homebrew and download the ggml-base model (~142 MB). Or configure paths manually.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Tab: Post-processing

    private var postProcessingTab: some View {
        Form {
            Section(L10n.llmCleanup) {
                Toggle(L10n.llmCleanupToggle, isOn: $postProcessingEnabled)
                Text(L10n.llmCleanupHint)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section(L10n.providers) {
                Picker(L10n.ppProvider, selection: $ppProvider) {
                    ForEach(PostProcessingProvider.allCases) { p in
                        Text(p.displayName).tag(p)
                    }
                }
                .disabled(!postProcessingEnabled)

                ppModelSection
                    .disabled(!postProcessingEnabled)
            }

            Section(L10n.preset) {
                Picker(L10n.preset, selection: $postProcessingPreset) {
                    ForEach(PostProcessingPreset.allCases) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                .disabled(!postProcessingEnabled)

                if postProcessingPreset == .custom {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.customSystemPrompt)
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

            Section(L10n.contextRouting) {
                Toggle(L10n.contextRoutingToggle, isOn: $contextRoutingEnabled)
                    .disabled(!postProcessingEnabled)
                Text(L10n.contextRoutingHint)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if contextRoutingEnabled && postProcessingEnabled {
                    ForEach($contextRules) { $rule in
                        HStack(spacing: 6) {
                            VStack(alignment: .leading, spacing: 1) {
                                TextField("Label", text: $rule.label)
                                    .font(.body)
                                    .textFieldStyle(.plain)
                                TextField("Bundle ID", text: $rule.bundleID)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .textFieldStyle(.plain)
                            }
                            .frame(width: 160, alignment: .leading)
                            Picker("", selection: $rule.presetRawValue) {
                                ForEach(PostProcessingPreset.allCases) { preset in
                                    Text(preset.displayName).tag(preset.rawValue)
                                }
                            }
                            .labelsHidden()
                            if rule.bundleID != "*" {
                                Button(role: .destructive) {
                                    contextRules.removeAll { $0.id == rule.id }
                                    Preferences.contextRules = contextRules
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                    .onChange(of: contextRules) { _ in
                        Preferences.contextRules = contextRules
                    }
                    HStack(spacing: 8) {
                        Button(L10n.addRule) {
                            let newRule = ContextRule(
                                bundleID: "com.example.app",
                                label: "New App",
                                preset: .cleanup
                            )
                            // Insert before the "*" fallback rule if it exists
                            if let fallbackIdx = contextRules.lastIndex(where: { $0.bundleID == "*" }) {
                                contextRules.insert(newRule, at: fallbackIdx)
                            } else {
                                contextRules.append(newRule)
                            }
                            Preferences.contextRules = contextRules
                        }
                        Button(L10n.resetToDefaults) {
                            contextRules = ContextRule.defaults
                            Preferences.contextRules = contextRules
                        }
                    }
                    Text(L10n.bundleIDTip)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var ppModelSection: some View {
        switch ppProvider {
        case .openRouter:
            TextField("OpenRouter model", text: $postProcessingModel, prompt: Text("openai/gpt-4o-mini"))
                .textFieldStyle(.roundedBorder)
            Text("Any chat model from the OpenRouter catalog. Uses your OpenRouter key from the Providers tab.")
                .font(.caption)
                .foregroundColor(.secondary)
        case .openAI:
            TextField("OpenAI model", text: $ppModelOpenAI, prompt: Text("gpt-4o-mini"))
                .textFieldStyle(.roundedBorder)
            Text("Uses your OpenAI key from the Providers tab.")
                .font(.caption)
                .foregroundColor(.secondary)
        case .groq:
            TextField("Groq model", text: $ppModelGroq, prompt: Text("llama-3.1-8b-instant"))
                .textFieldStyle(.roundedBorder)
            Text("Groq chat completions model. Uses your Groq key from the Providers tab.")
                .font(.caption)
                .foregroundColor(.secondary)
        case .polzaAI:
            TextField("Polza.ai model", text: $postProcessingModel, prompt: Text("openai/gpt-4o-mini"))
                .textFieldStyle(.roundedBorder)
            Text("Любая chat-модель из каталога Polza.ai. Использует ключ Polza.ai из таба Providers.")
                .font(.caption)
                .foregroundColor(.secondary)
        case .custom:
            TextField("Endpoint URL", text: $customEndpointURL, prompt: Text("https://api.polza.ai/v1/chat/completions"))
                .textFieldStyle(.roundedBorder)
            if !customEndpointURL.isEmpty, PostProcessingProvider.custom.endpoint == nil {
                Label("Invalid URL. Must start with https:// or http://", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.red)
            }
            TextField("Model name", text: $customEndpointModel, prompt: Text("gpt-4o-mini"))
                .textFieldStyle(.roundedBorder)
            if customEndpointModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Label("Model name is required", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
            apiKeyControls(
                account: .customEndpoint,
                binding: $customEndpointKey,
                status: $customEndpointKeyStatus,
                placeholder: "API key"
            )
            Text("Any OpenAI-compatible /chat/completions endpoint (e.g. Polza.ai, Together.ai).")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Tab: Hotkey

    private var hotkeyTab: some View {
        Form {
            Section(L10n.recordStop) {
                LabeledContent(L10n.shortcut) {
                    HStack(spacing: 8) {
                        HotkeyRecorderView(
                            keyCode: $hotkeyKeyCode,
                            modifiers: $hotkeyModifiers,
                            isDisabled: fnKeyEnabled
                        )
                        Button(L10n.reset) {
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

            Section(L10n.fnKeyExperimental) {
                Toggle(L10n.useFnKey, isOn: $fnKeyEnabled)
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
            Section(L10n.transcriptHistory) {
                Toggle(L10n.keepLocalHistory, isOn: $historyEnabled)

                Picker(L10n.retention, selection: $historyRetentionDays) {
                    Text(L10n.keepForever).tag(0)
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

                Text(L10n.historyEncryptionHint)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section(L10n.audioRetention) {
                Picker(L10n.keepRecordings, selection: $audioRetention) {
                    ForEach(AudioRetention.allCases) { r in
                        Text(r.displayName).tag(r)
                    }
                }
                Button(L10n.wipeAllAudio) {
                    AudioRetentionSweeper.wipeAll()
                }
            }

            Section(L10n.privacyNotes) {
                VStack(alignment: .leading, spacing: 6) {
                    Label {
                        Text(L10n.privacyCloud)
                    } icon: {
                        Image(systemName: "cloud.fill")
                            .foregroundColor(.secondary)
                    }
                    Label {
                        Text(L10n.privacyClipboard)
                    } icon: {
                        Image(systemName: "doc.on.clipboard")
                            .foregroundColor(.secondary)
                    }
                    Label {
                        Text(L10n.privacyFiles)
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

    // MARK: - Tab: Updates

    private var updatesTab: some View {
        Form {
            Section(L10n.lang == .ru ? "Версия" : "Version") {
                HStack {
                    Text(L10n.lang == .ru ? "Текущая версия:" : "Current version:")
                    Text(updateChecker.currentVersion)
                        .fontWeight(.medium)
                }

                switch updateChecker.status {
                case .idle:
                    EmptyView()
                case .checking:
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text(L10n.lang == .ru ? "Проверяю..." : "Checking...")
                            .foregroundColor(.secondary)
                    }
                case .upToDate(let version):
                    Label(
                        L10n.lang == .ru ? "Вы используете последнюю версию (\(version))" : "You're on the latest version (\(version))",
                        systemImage: "checkmark.circle.fill"
                    )
                    .foregroundColor(.green)
                case .updateAvailable(let current, let latest, _):
                    VStack(alignment: .leading, spacing: 6) {
                        Label(
                            L10n.lang == .ru ? "Доступна версия \(latest) (у вас \(current))" : "Version \(latest) available (you have \(current))",
                            systemImage: "arrow.down.circle.fill"
                        )
                        .foregroundColor(.orange)
                        Button(L10n.lang == .ru ? "Скачать обновление" : "Download update") {
                            updateChecker.openDownload()
                        }
                    }
                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .font(.caption)
                }

                Button(L10n.lang == .ru ? "Проверить обновления" : "Check for updates") {
                    Task { await updateChecker.check(force: true) }
                }
            }

            Section(L10n.lang == .ru ? "О приложении" : "About") {
                Text("WhisperHot \(updateChecker.currentVersion)")
                    .font(.headline)
                Text(L10n.lang == .ru
                    ? "macOS приложение для голосовой транскрипции. Apple Silicon (M1+), macOS 13.0+."
                    : "macOS speech-to-text app. Apple Silicon (M1+), macOS 13.0+.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Apache License 2.0")
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
        case .polzaAI:
            Picker("Model", selection: $modelOpenAI) {
                ForEach(Preferences.availableOpenAIModels) { m in
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
        SecureField(L10n.apiKey, text: binding, prompt: Text(placeholder))
            .textFieldStyle(.roundedBorder)
        HStack(spacing: 8) {
            Button(L10n.save) {
                let trimmed = binding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    status.wrappedValue = StatusMessage(text: L10n.keyIsEmpty, kind: .error)
                    return
                }
                do {
                    try Keychain.save(apiKey: trimmed, account: account)
                    status.wrappedValue = StatusMessage(text: L10n.savedToKeychain, kind: .success)
                } catch {
                    status.wrappedValue = StatusMessage(text: "Save failed: \(error.localizedDescription)", kind: .error)
                }
            }
            Button(L10n.delete) {
                do {
                    try Keychain.delete(account: account)
                    binding.wrappedValue = ""
                    status.wrappedValue = StatusMessage(text: L10n.deletedFromKeychain, kind: .success)
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

    // providerDescription replaced by L10n.providerDescription(for:)

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
        (polzaAIKey, polzaAIStatus) = loadKey(account: .polzaAI)
        (customEndpointKey, customEndpointKeyStatus) = loadKey(account: .customEndpoint)
        contextRules = Preferences.contextRules
    }

    private func loadKey(account: Keychain.Account) -> (String, StatusMessage) {
        do {
            let key = try Keychain.readAPIKey(account: account)
            return (key, StatusMessage(text: L10n.loadedFromKeychain, kind: .secondary))
        } catch Keychain.KeychainError.itemNotFound {
            return ("", StatusMessage(text: L10n.noKeySaved, kind: .secondary))
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
