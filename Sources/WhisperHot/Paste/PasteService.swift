import AppKit
import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics

/// Delivers transcribed text to the user's intended target app.
/// The pasteboard write is unconditional — if any guard trips, text still
/// ends up on the clipboard so the user can paste manually.
@MainActor
final class PasteService {
    enum Outcome: Sendable, CustomStringConvertible {
        case pasted
        case copiedOnlyNoTarget
        case copiedOnlyOwnAppFrontmost
        case copiedOnlyFocusMismatch(expected: String, actual: String)
        case copiedOnlySecureInput
        case copiedOnlyNoAccessibility
        case pasteboardWriteFailed
        case failed(String)

        var isPasted: Bool {
            if case .pasted = self { return true }
            return false
        }

        var description: String {
            switch self {
            case .pasted:
                return "pasted into target"
            case .copiedOnlyNoTarget:
                return "copied to clipboard (no target captured)"
            case .copiedOnlyOwnAppFrontmost:
                return "copied to clipboard (WhisperHot is frontmost)"
            case .copiedOnlyFocusMismatch(let expected, let actual):
                return "copied to clipboard (focus moved: \(expected) → \(actual))"
            case .copiedOnlySecureInput:
                return "copied to clipboard (secure input detected)"
            case .copiedOnlyNoAccessibility:
                return "copied to clipboard (Accessibility permission missing)"
            case .pasteboardWriteFailed:
                return "failed: NSPasteboard rejected setString"
            case .failed(let message):
                return "failed: \(message)"
            }
        }
    }

    /// Deliver `text` to `targetApp`. The pasteboard is always written. The
    /// Cmd+V synthesis is only performed if every guard passes. Main-thread only.
    func deliver(text: String, targetApp: NSRunningApplication?) -> Outcome {
        dispatchPrecondition(condition: .onQueue(.main))

        // 1. Always seed the pasteboard so the user has the text regardless
        //    of any guard failure below. If the pasteboard refuses the write,
        //    bail before synthesizing Cmd+V — otherwise we would paste stale
        //    or empty contents into the target.
        guard writePasteboard(text: text) else {
            return .pasteboardWriteFailed
        }

        // 2. Must have captured a target at record start.
        guard let target = targetApp else {
            return .copiedOnlyNoTarget
        }

        // 3. Captured target may have quit between record-start and paste time.
        if target.isTerminated {
            return .copiedOnlyFocusMismatch(
                expected: target.bundleIdentifier ?? "pid \(target.processIdentifier)",
                actual: "<terminated>"
            )
        }

        // 4. Accessibility permission is required for CGEventPost to deliver
        //    synthetic key events to other apps. Without it the events are
        //    silently dropped. Do not even try — tell the caller.
        guard AXIsProcessTrusted() else {
            return .copiedOnlyNoAccessibility
        }

        // 5. Verify the user's intended target is still frontmost. Between
        //    recording stop and paste time, the user may have switched apps,
        //    opened a spotlight window, or made our own Settings key.
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            return .copiedOnlyOwnAppFrontmost
        }
        if front?.processIdentifier != target.processIdentifier {
            return .copiedOnlyFocusMismatch(
                expected: target.bundleIdentifier ?? "pid \(target.processIdentifier)",
                actual: front?.bundleIdentifier ?? "pid \(front?.processIdentifier ?? -1)"
            )
        }

        // 6. NEVER auto-paste into a Secure Event Input field. That is the
        //    signal a password/sudo/Secure-Keyboard-Input-enabled app is
        //    eating the keystrokes. Auto-pasting a transcript there would
        //    leak it into a password field at best and into a terminal at worst.
        if IsSecureEventInputEnabled() {
            return .copiedOnlySecureInput
        }

        // 7. Synthesize Cmd+V via CGEventPost.
        guard synthesizeCmdV() else {
            return .failed("CGEventPost synthesis returned nil")
        }
        return .pasted
    }

    // MARK: - Private

    private func writePasteboard(text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }

    private func synthesizeCmdV() -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            return false
        }
        let vKey = CGKeyCode(kVK_ANSI_V)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false) else {
            return false
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }
}
