import AppKit
import SwiftUI

@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    private weak var menuBarController: MenuBarController?
    private var window: NSWindow?
    private var previousApp: NSRunningApplication?
    private var model: MainWindowModel?

    init(menuBarController: MenuBarController) {
        self.menuBarController = menuBarController
        super.init()
    }

    func show() {
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp = front
        } else {
            previousApp = nil
        }

        if window == nil {
            buildWindow()
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func buildWindow() {
        guard let menuBarController else { return }

        let model = MainWindowModel(
            menuBarController: menuBarController,
            historyStore: menuBarController.historyStoreForInterface,
            permissions: menuBarController.permissionsCoordinatorForInterface,
            startOrStopRecording: { [weak self] wantsRawOutput in
                self?.performPrimaryRecordingAction(wantsRawOutput: wantsRawOutput)
            }
        )
        self.model = model

        let hostingView = NSHostingView(rootView: MainWindowView(model: model))
        hostingView.frame = NSRect(x: 0, y: 0, width: 960, height: 680)

        let newWindow = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "WhisperHot"
        newWindow.isReleasedWhenClosed = false
        newWindow.contentView = hostingView
        newWindow.center()
        newWindow.delegate = self
        self.window = newWindow
    }

    private func performPrimaryRecordingAction(wantsRawOutput: Bool) {
        guard let menuBarController else { return }

        switch menuBarController.interfaceSnapshot().mode {
        case .idle:
            let target = previousApp
            window?.orderOut(nil)
            if let target, target.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                target.activate(options: [])
            }

            // Let AppKit finish focus handoff before MenuBarController snapshots
            // the paste target. Without the small delay, the main window is still
            // frontmost and auto-paste correctly refuses to paste into itself.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak menuBarController] in
                MainActor.assumeIsolated {
                    menuBarController?.toggleRecordingFromInterface(wantsRawOutput: wantsRawOutput)
                }
            }

        case .recording:
            menuBarController.toggleRecordingFromInterface(wantsRawOutput: wantsRawOutput)

        case .transcribing:
            break
        }
    }
}

@MainActor
final class MainWindowModel: ObservableObject {
    @Published private(set) var snapshot: MenuBarController.InterfaceSnapshot
    @Published private(set) var microphoneState: PermissionsCoordinator.PermissionState
    @Published private(set) var accessibilityGranted: Bool
    @Published private(set) var inputMonitoringState: PermissionsCoordinator.PermissionState
    @Published private(set) var providerSetupStatus: ProviderSetupStatus

    let historyStore: HistoryStore
    private weak var menuBarController: MenuBarController?
    private let permissions: PermissionsCoordinator
    private let startOrStopRecordingHandler: (Bool) -> Void

    init(
        menuBarController: MenuBarController,
        historyStore: HistoryStore,
        permissions: PermissionsCoordinator,
        startOrStopRecording: @escaping (Bool) -> Void
    ) {
        self.menuBarController = menuBarController
        self.historyStore = historyStore
        self.permissions = permissions
        self.startOrStopRecordingHandler = startOrStopRecording
        self.snapshot = menuBarController.interfaceSnapshot()
        self.microphoneState = permissions.microphoneState()
        self.accessibilityGranted = permissions.accessibilityGranted()
        self.inputMonitoringState = permissions.inputMonitoringState()
        self.providerSetupStatus = Self.readProviderSetupStatus()
    }

    var allRequiredPermissionsReady: Bool {
        microphoneState == .granted && accessibilityGranted
    }

    var firstRecordingReady: Bool {
        allRequiredPermissionsReady && providerSetupStatus.isReady
    }

    func refresh() {
        if let menuBarController {
            let next = menuBarController.interfaceSnapshot()
            if next != snapshot {
                snapshot = next
            }
        }

        let nextMic = permissions.microphoneState()
        if nextMic != microphoneState {
            microphoneState = nextMic
        }

        let nextAccessibility = permissions.accessibilityGranted()
        if nextAccessibility != accessibilityGranted {
            accessibilityGranted = nextAccessibility
        }

        let nextInputMonitoring = permissions.inputMonitoringState()
        if nextInputMonitoring != inputMonitoringState {
            inputMonitoringState = nextInputMonitoring
        }

        let nextProviderSetup = Self.readProviderSetupStatus()
        if nextProviderSetup != providerSetupStatus {
            providerSetupStatus = nextProviderSetup
        }
    }

    func startOrStopRecording(wantsRawOutput: Bool = false) {
        startOrStopRecordingHandler(wantsRawOutput)
    }

    func openSettingsWindow() {
        menuBarController?.openSettingsFromInterface()
    }

    func openHistoryWindow() {
        menuBarController?.openHistoryFromInterface()
    }

    func openPermissionsWindow() {
        menuBarController?.openOnboardingFromInterface()
    }

    func requestMicrophoneAccess() {
        Task { @MainActor in
            _ = await permissions.requestMicrophone()
            refresh()
        }
    }

    func openMicrophoneSettings() {
        permissions.openMicrophoneSettings()
    }

    func openAccessibilitySettings() {
        permissions.promptAccessibility()
        permissions.openAccessibilitySettings()
        refresh()
    }

    func openInputMonitoringSettings() {
        _ = permissions.requestInputMonitoring()
        permissions.openInputMonitoringSettings()
        refresh()
    }

    struct ProviderSetupStatus: Equatable {
        let title: String
        let detail: String
        let systemImage: String
        let isReady: Bool
    }

    private static func readProviderSetupStatus() -> ProviderSetupStatus {
        let provider = Preferences.provider

        if provider == .localWhisper {
            if Preferences.isLocalWhisperReady {
                return ProviderSetupStatus(
                    title: L10n.mainProviderReady(provider.shortName),
                    detail: L10n.mainLocalProviderReady(Preferences.currentModel),
                    systemImage: "externaldrive.badge.checkmark",
                    isReady: true
                )
            }

            return ProviderSetupStatus(
                title: L10n.mainProviderNeedsSetup(provider.shortName),
                detail: L10n.mainLocalProviderMissingDetail,
                systemImage: "externaldrive.badge.exclamationmark",
                isReady: false
            )
        }

        guard let account = provider.keychainAccount else {
            return ProviderSetupStatus(
                title: L10n.mainProviderReady(provider.shortName),
                detail: L10n.mainProviderNoKeyRequired,
                systemImage: "checkmark.seal.fill",
                isReady: true
            )
        }

        do {
            let key = try Keychain.readAPIKey(account: account).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else {
                return ProviderSetupStatus(
                    title: L10n.mainProviderNeedsAPIKey(provider.shortName),
                    detail: L10n.mainProviderMissingKeyDetail(provider.shortName),
                    systemImage: "key.slash",
                    isReady: false
                )
            }

            return ProviderSetupStatus(
                title: L10n.mainProviderReady(provider.shortName),
                detail: L10n.mainProviderKeySavedDetail(provider.shortName),
                systemImage: "key.fill",
                isReady: true
            )
        } catch Keychain.KeychainError.itemNotFound {
            return ProviderSetupStatus(
                title: L10n.mainProviderNeedsAPIKey(provider.shortName),
                detail: L10n.mainProviderMissingKeyDetail(provider.shortName),
                systemImage: "key.slash",
                isReady: false
            )
        } catch {
            return ProviderSetupStatus(
                title: L10n.mainProviderCheckFailed(provider.shortName),
                detail: error.localizedDescription,
                systemImage: "exclamationmark.triangle.fill",
                isReady: false
            )
        }
    }
}

private struct MainWindowView: View {
    @StateObject private var model: MainWindowModel
    @State private var selectedSection: MainSection = .dashboard

    init(model: MainWindowModel) {
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedSection) {
                Section(L10n.mainGroupOverview) {
                    sidebarRow(.dashboard)
                }

                Section(L10n.mainGroupSettings) {
                    sidebarRow(.recording)
                    sidebarRow(.providers)
                    sidebarRow(.postProcessing)
                    sidebarRow(.hotkey)
                    sidebarRow(.historyPrivacy)
                    sidebarRow(.updates)
                }

                Section(L10n.mainGroupData) {
                    sidebarRow(.transcriptHistory)
                    sidebarRow(.setup)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 230)
        } detail: {
            detailView
        }
        .frame(minWidth: 860, idealWidth: 960, minHeight: 600, idealHeight: 680)
        .onAppear { model.refresh() }
        .onReceive(Timer.publish(every: 0.75, on: .main, in: .common).autoconnect()) { _ in
            model.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            model.refresh()
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedSection {
        case .dashboard:
            DashboardView(
                model: model,
                navigateTo: { selectedSection = $0 }
            )
        case .recording:
            SettingsView(embeddedSection: .recording)
        case .providers:
            SettingsView(embeddedSection: .providers)
        case .postProcessing:
            SettingsView(embeddedSection: .postProcessing)
        case .hotkey:
            SettingsView(embeddedSection: .hotkey)
        case .historyPrivacy:
            SettingsView(embeddedSection: .historyPrivacy)
        case .updates:
            SettingsView(embeddedSection: .updates)
        case .transcriptHistory:
            TranscriptHistoryView(store: model.historyStore)
        case .setup:
            SetupView(
                model: model,
                openProviders: { selectedSection = .providers }
            )
        }
    }

    private func sidebarRow(_ section: MainSection) -> some View {
        Label(section.title, systemImage: section.icon)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(section.title)
            .tag(section)
    }
}

private enum MainSection: String, Identifiable {
    case dashboard
    case recording
    case providers
    case postProcessing
    case hotkey
    case historyPrivacy
    case updates
    case transcriptHistory
    case setup

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return L10n.mainDashboard
        case .recording: return L10n.recording
        case .providers: return L10n.providers
        case .postProcessing: return L10n.postProcessing
        case .hotkey: return L10n.hotkey
        case .historyPrivacy: return L10n.mainPrivacySettings
        case .updates: return L10n.sectionUpdates
        case .transcriptHistory: return L10n.history
        case .setup: return L10n.mainSetup
        }
    }

    var icon: String {
        switch self {
        case .dashboard: return "rectangle.grid.2x2.fill"
        case .recording: return SettingsSection.recording.icon
        case .providers: return SettingsSection.providers.icon
        case .postProcessing: return SettingsSection.postProcessing.icon
        case .hotkey: return SettingsSection.hotkey.icon
        case .historyPrivacy: return SettingsSection.historyPrivacy.icon
        case .updates: return SettingsSection.updates.icon
        case .transcriptHistory: return "clock.arrow.circlepath"
        case .setup: return "checklist.checked"
        }
    }
}

private struct DashboardView: View {
    @ObservedObject var model: MainWindowModel
    let navigateTo: (MainSection) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center, spacing: 16) {
                    StatusBadge(snapshot: model.snapshot)
                    Spacer()
                    Button(
                        model.snapshot.primaryActionTitle,
                        systemImage: model.snapshot.primaryActionIcon
                    ) {
                        model.startOrStopRecording()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityLabel(model.snapshot.primaryActionTitle)
                    .disabled(model.snapshot.mode == .transcribing)
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: L10n.mainCurrentRoute, systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                    InfoRow(title: L10n.provider, value: model.snapshot.providerName)
                    InfoRow(title: L10n.model, value: model.snapshot.providerModel)
                    InfoRow(title: L10n.shortcut, value: model.snapshot.hotkeyLabel)
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: L10n.mainWritingPipeline, systemImage: "text.badge.checkmark")
                    FeatureRow(
                        title: model.snapshot.postProcessingEnabled ? L10n.mainPostProcessingOn : L10n.mainPostProcessingOff,
                        detail: "\(model.snapshot.postProcessingProviderName) · \(model.snapshot.postProcessingPresetName)",
                        isOn: model.snapshot.postProcessingEnabled
                    )
                    FeatureRow(
                        title: model.snapshot.contextRoutingEnabled ? L10n.mainContextRoutingOn : L10n.mainContextRoutingOff,
                        detail: L10n.postProcessing,
                        isOn: model.snapshot.contextRoutingEnabled
                    )
                    FeatureRow(
                        title: model.snapshot.historyEnabled ? L10n.mainHistoryOn : L10n.mainHistoryOff,
                        detail: L10n.historyPrivacy,
                        isOn: model.snapshot.historyEnabled
                    )
                    FeatureRow(
                        title: model.snapshot.autoPasteEnabled ? L10n.mainAutoPasteOn : L10n.mainAutoPasteOff,
                        detail: L10n.afterTranscription,
                        isOn: model.snapshot.autoPasteEnabled
                    )
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: L10n.mainLocalFallback, systemImage: "externaldrive.badge.checkmark")
                    FeatureRow(
                        title: model.snapshot.localWhisperReady ? L10n.mainLocalReady : L10n.mainLocalNotReady,
                        detail: model.snapshot.autoOfflineOnTimeout ? L10n.mainAutoOfflineOn : L10n.mainAutoOfflineOff,
                        isOn: model.snapshot.localWhisperReady
                    )
                }

                Divider()

                HStack(spacing: 10) {
                    Button(
                        L10n.mainConfigureProviders,
                        systemImage: "key"
                    ) {
                        navigateTo(.providers)
                    }
                    .accessibilityLabel(L10n.mainConfigureProviders)
                    Button(
                        L10n.mainViewHistory,
                        systemImage: "clock"
                    ) {
                        navigateTo(.transcriptHistory)
                    }
                    .accessibilityLabel(L10n.mainViewHistory)
                    Button(
                        L10n.mainOpenSetup,
                        systemImage: "checklist"
                    ) {
                        navigateTo(.setup)
                    }
                    .accessibilityLabel(L10n.mainOpenSetup)
                }
                .buttonStyle(.bordered)
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
        }
    }
}

private struct SetupView: View {
    @ObservedObject var model: MainWindowModel
    let openProviders: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: model.firstRecordingReady ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(model.firstRecordingReady ? .green : .orange)
                    .font(.title2)
                Text(model.firstRecordingReady ? L10n.mainFirstRunReady : L10n.mainFirstRunNeedsAttention)
                    .font(.title3.weight(.semibold))
            }

            Divider()

            PermissionRow(
                title: L10n.mainMicPermission,
                systemImage: "mic.fill",
                status: permissionLabel(model.microphoneState),
                isGranted: model.microphoneState == .granted,
                actionTitle: model.microphoneState == .notDetermined ? L10n.mainRequestAccess : L10n.mainOpenSystemSettings,
                action: {
                    if model.microphoneState == .notDetermined {
                        model.requestMicrophoneAccess()
                    } else {
                        model.openMicrophoneSettings()
                    }
                }
            )

            SetupStatusRow(
                title: model.providerSetupStatus.title,
                systemImage: model.providerSetupStatus.systemImage,
                status: model.providerSetupStatus.detail,
                isReady: model.providerSetupStatus.isReady,
                actionTitle: L10n.mainOpenProviders,
                action: openProviders
            )

            PermissionRow(
                title: L10n.mainAccessibilityPermission,
                systemImage: "cursorarrow.motionlines",
                status: model.accessibilityGranted ? L10n.mainGranted : L10n.mainNotGranted,
                isGranted: model.accessibilityGranted,
                actionTitle: L10n.mainOpenSystemSettings,
                action: { model.openAccessibilitySettings() }
            )

            PermissionRow(
                title: L10n.mainInputMonitoringPermission,
                systemImage: "keyboard",
                status: permissionLabel(model.inputMonitoringState),
                isGranted: model.inputMonitoringState == .granted,
                actionTitle: L10n.mainOpenSystemSettings,
                action: { model.openInputMonitoringSettings() }
            )

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: 720, maxHeight: .infinity, alignment: .topLeading)
    }

    private func permissionLabel(_ state: PermissionsCoordinator.PermissionState) -> String {
        switch state {
        case .granted: return L10n.mainGranted
        case .denied: return L10n.mainDenied
        case .notDetermined: return L10n.mainNotRequested
        }
    }
}

private struct SetupStatusRow: View {
    let title: String
    let systemImage: String
    let status: String
    let isReady: Bool
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundColor(isReady ? .green : .orange)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(status)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isReady {
                ReadinessPill()
            } else {
                Button(actionTitle, action: action)
                    .accessibilityLabel(actionTitle)
            }
        }
        .padding(.vertical, 8)
    }
}

private struct StatusBadge: View {
    let snapshot: MenuBarController.InterfaceSnapshot

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: snapshot.primaryActionIcon)
                .font(.title2)
                .foregroundColor(iconColor)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(snapshot.statusTitle)
                    .font(.title2.weight(.semibold))
                Text("\(snapshot.providerName) · \(snapshot.providerModel)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private var iconColor: Color {
        switch snapshot.mode {
        case .idle: return .accentColor
        case .recording: return .red
        case .transcribing: return .orange
        }
    }
}

private struct SectionHeader: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
    }
}

private struct InfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundColor(.secondary)
                .frame(width: 150, alignment: .leading)
            Text(value)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
        .font(.callout)
    }
}

private struct FeatureRow: View {
    let title: String
    let detail: String
    let isOn: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isOn ? .green : .secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout)
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let systemImage: String
    let status: String
    let isGranted: Bool
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundColor(isGranted ? .green : .orange)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(status)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isGranted {
                ReadinessPill()
            } else {
                Button(actionTitle, action: action)
                    .accessibilityLabel(actionTitle)
            }
        }
        .padding(.vertical, 8)
    }
}

private struct ReadinessPill: View {
    var body: some View {
        Label(L10n.mainReadyPill, systemImage: "checkmark.circle.fill")
            .font(.caption.weight(.semibold))
            .foregroundColor(.green)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.green.opacity(0.12), in: Capsule())
            .accessibilityLabel(L10n.mainReadyPill)
    }
}
