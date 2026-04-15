import AppKit
import ApplicationServices
import AVFoundation
import IOKit.hid

@MainActor
final class PermissionsCoordinator {
    enum PermissionState: Equatable {
        case granted
        case denied
        case notDetermined
    }

    // MARK: - Microphone

    func microphoneState() -> PermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    /// Request microphone access. Returns the granted state. Triggers the
    /// system prompt on first call; later calls just return the cached answer.
    func requestMicrophone() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }

    // MARK: - Accessibility

    func accessibilityGranted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Surfaces the system Accessibility trust prompt. Only triggers the
    /// prompt the first time per app session; subsequent calls are no-ops
    /// until the user takes action in System Settings.
    func promptAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    // MARK: - Input Monitoring (Block 15 Fn-key opt-in)

    func inputMonitoringState() -> PermissionState {
        let status = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        if status == kIOHIDAccessTypeGranted { return .granted }
        if status == kIOHIDAccessTypeDenied { return .denied }
        return .notDetermined
    }

    /// Trigger the Input Monitoring prompt. On first call macOS surfaces
    /// the system dialog + sends the user to the Privacy pane. Returns
    /// `true` synchronously only if access is already granted.
    @discardableResult
    func requestInputMonitoring() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    // MARK: - Deep links

    func openMicrophoneSettings() {
        openSystemSettings(anchor: "Privacy_Microphone")
    }

    func openAccessibilitySettings() {
        openSystemSettings(anchor: "Privacy_Accessibility")
    }

    func openInputMonitoringSettings() {
        openSystemSettings(anchor: "Privacy_ListenEvent")
    }

    private func openSystemSettings(anchor: String) {
        // On Ventura+, Privacy & Security panes live under the new Settings
        // extension ID. Try that first, fall back to the legacy System
        // Preferences target if NSWorkspace rejects the new URL.
        let newURL = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(anchor)")
        let legacyURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")

        if let newURL, NSWorkspace.shared.open(newURL) {
            return
        }
        if let legacyURL {
            NSWorkspace.shared.open(legacyURL)
        }
    }
}
