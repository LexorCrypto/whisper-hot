import AppKit
import Carbon.HIToolbox
import SwiftUI

extension Notification.Name {
    /// Posted when the user arms the in-Settings hotkey recorder. Observers
    /// (the MenuBarController) should temporarily release the currently-bound
    /// Carbon hotkey so pressing the existing combo during capture doesn't
    /// also toggle a real recording session.
    static let whisperLocalHotkeyRecorderDidArm = Notification.Name("WhisperLocal.hotkeyRecorderDidArm")
    /// Posted when the recorder stops capturing for any reason: commit,
    /// cancel, window close, or the Fn-key toggle flipping on. Observers
    /// should re-apply the current preferences-backed hotkey bindings.
    static let whisperLocalHotkeyRecorderDidDisarm = Notification.Name("WhisperLocal.hotkeyRecorderDidDisarm")
    /// Posted by `SettingsWindowController.windowWillClose` so the recorder
    /// can drop its local NSEvent monitor even though `.onDisappear` is
    /// unreliable — the SwiftUI hosting view is reused across open/close.
    static let whisperLocalSettingsWillClose = Notification.Name("WhisperLocal.settingsWillClose")
}

/// Formats a (keyCode, Carbon modifier mask) pair into a human-readable combo
/// like `⌥⌘5` or `⌃F12`. Uses `UCKeyTranslate` against the current keyboard
/// layout so the character reflects the user's actual keymap (e.g. a German
/// keyboard shows `Z` where a US keyboard shows `Y` for the same physical key).
enum HotkeyFormatter {
    static func format(keyCode: Int, modifiers: Int) -> String {
        var result = ""
        if modifiers & controlKey != 0 { result += "⌃" }
        if modifiers & optionKey != 0 { result += "⌥" }
        if modifiers & shiftKey != 0 { result += "⇧" }
        if modifiers & cmdKey != 0 { result += "⌘" }
        result += keyLabel(for: keyCode)
        return result
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> Int {
        var result = 0
        if flags.contains(.command) { result |= cmdKey }
        if flags.contains(.option) { result |= optionKey }
        if flags.contains(.control) { result |= controlKey }
        if flags.contains(.shift) { result |= shiftKey }
        return result
    }

    /// Returns a display string for the given virtual key code. Special keys
    /// (arrows, function keys, space, return, etc.) use glyphs; everything
    /// else is translated through the current keyboard layout.
    private static func keyLabel(for keyCode: Int) -> String {
        if let symbol = specialKeyGlyphs[keyCode] {
            return symbol
        }
        return translate(keyCode: keyCode) ?? "Key \(keyCode)"
    }

    private static let specialKeyGlyphs: [Int: String] = [
        kVK_Return: "↩",
        kVK_Tab: "⇥",
        kVK_Space: "Space",
        kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦",
        kVK_Escape: "⎋",
        kVK_LeftArrow: "←",
        kVK_RightArrow: "→",
        kVK_UpArrow: "↑",
        kVK_DownArrow: "↓",
        kVK_Home: "↖",
        kVK_End: "↘",
        kVK_PageUp: "⇞",
        kVK_PageDown: "⇟",
        kVK_ANSI_KeypadEnter: "⌤",
        kVK_ANSI_KeypadClear: "⌧",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
        kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
        kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16",
        kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20"
    ]

    private static func translate(keyCode: Int) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutPtr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let layoutData = Unmanaged<CFData>.fromOpaque(layoutPtr).takeUnretainedValue() as Data
        return layoutData.withUnsafeBytes { raw -> String? in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                return nil
            }
            var deadKeyState: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var actualLength = 0
            let status = UCKeyTranslate(
                layout,
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                UInt32(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                chars.count,
                &actualLength,
                &chars
            )
            guard status == noErr, actualLength > 0 else { return nil }
            return String(utf16CodeUnits: chars, count: actualLength).uppercased()
        }
    }
}

/// A pill-style button that captures the next keyboard combo and writes the
/// resulting (keyCode, Carbon modifier mask) pair into the bound values.
///
/// Contract:
/// - Click to arm. The button shows "Press combo…" while armed.
/// - The first key press with at least one modifier (⌘/⌥/⌃/⇧) is captured.
/// - Pressing `Escape` with no modifier cancels recording without changing
///   the stored combo.
/// - The SwiftUI parent is expected to persist the bindings to `@AppStorage`
///   so the Carbon hotkey re-registers via the existing UserDefaults
///   observer in `MenuBarController`.
struct HotkeyRecorderView: View {
    @Binding var keyCode: Int
    @Binding var modifiers: Int
    /// When true, an external state change (e.g. the Fn-key toggle flipping
    /// on) has disabled this control. The view cancels any in-flight capture
    /// instead of quietly rewriting the combo behind the user's back.
    var isDisabled: Bool = false

    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var rejectionFlash: Date?

    /// Minimum modifier mask that makes a global Carbon hotkey safe to bind.
    /// Shift-only is banned because combos like `⇧A` would fire every time
    /// the user types a capital letter anywhere on the system. At least one
    /// of Cmd/Option/Control is required; Shift is allowed as a secondary.
    private static let requiredModifierMask = cmdKey | optionKey | controlKey

    var body: some View {
        Button(action: toggleRecording) {
            Text(displayText)
                .font(.system(.body, design: .monospaced))
                .frame(minWidth: 110)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(background)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(borderColor, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .onDisappear { stopMonitoring() }
        .onChange(of: isDisabled) { nowDisabled in
            if nowDisabled { stopMonitoring() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .whisperLocalSettingsWillClose)) { _ in
            stopMonitoring()
        }
    }

    private var displayText: String {
        if isRecording {
            if rejectionFlash != nil {
                return "Need ⌘/⌥/⌃…"
            }
            return "Press combo…"
        }
        return HotkeyFormatter.format(keyCode: keyCode, modifiers: modifiers)
    }

    private var background: Color {
        isRecording
            ? Color.accentColor.opacity(0.15)
            : Color.secondary.opacity(0.12)
    }

    private var borderColor: Color {
        if rejectionFlash != nil {
            return Color.orange
        }
        return isRecording ? Color.accentColor : Color.secondary.opacity(0.3)
    }

    private func toggleRecording() {
        if isRecording { stopMonitoring() } else { startMonitoring() }
    }

    private func startMonitoring() {
        guard !isRecording, !isDisabled else { return }
        isRecording = true
        rejectionFlash = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKeyDown(event)
            return nil // swallow so the Settings window doesn't beep
        }
        NotificationCenter.default.post(
            name: .whisperLocalHotkeyRecorderDidArm,
            object: nil
        )
    }

    private func stopMonitoring() {
        guard isRecording else { return }
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
        isRecording = false
        rejectionFlash = nil
        NotificationCenter.default.post(
            name: .whisperLocalHotkeyRecorderDidDisarm,
            object: nil
        )
    }

    private func handleKeyDown(_ event: NSEvent) {
        let code = Int(event.keyCode)
        let carbon = HotkeyFormatter.carbonModifiers(from: event.modifierFlags)

        if code == kVK_Escape && carbon == 0 {
            stopMonitoring()
            return
        }
        // Require at least one non-shift modifier (⌘/⌥/⌃). Shift-only combos
        // would hijack normal typing — e.g. ⇧A fires on every capital A.
        guard carbon & Self.requiredModifierMask != 0 else {
            rejectionFlash = Date()
            return
        }
        if Self.isReservedCombo(keyCode: code, modifiers: carbon) {
            rejectionFlash = Date()
            return
        }

        keyCode = code
        modifiers = carbon
        stopMonitoring()
    }

    /// A short denylist of macOS-reserved combos. Registering these via
    /// `RegisterEventHotKey` silently succeeds but leaves the user with no
    /// working way to invoke Spotlight / App Switcher / Quit — a frustrating
    /// footgun. Not exhaustive; just the ones most likely to be picked by
    /// accident.
    private static func isReservedCombo(keyCode: Int, modifiers: Int) -> Bool {
        switch (keyCode, modifiers) {
        case (kVK_Space, cmdKey),                              // Spotlight
             (kVK_Space, cmdKey | shiftKey),                   // Input source
             (kVK_Space, optionKey | cmdKey),                  // Finder search
             (kVK_Tab, cmdKey),                                // App switcher
             (kVK_Tab, cmdKey | shiftKey),                     // Reverse switch
             (kVK_ANSI_Grave, cmdKey),                         // Window cycle
             (kVK_ANSI_Q, cmdKey),                             // Quit
             (kVK_ANSI_W, cmdKey),                             // Close window
             (kVK_ANSI_H, cmdKey),                             // Hide
             (kVK_ANSI_M, cmdKey):                             // Minimize
            return true
        default:
            return false
        }
    }
}
