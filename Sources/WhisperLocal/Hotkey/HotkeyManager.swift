import AppKit
import Carbon.HIToolbox

/// Registers a single global hotkey via Carbon `RegisterEventHotKey`.
/// - All public methods must be called from the main thread.
/// - The Carbon event handler is delivered synchronously on the main thread by
///   the application event target in Cocoa apps, so `onHotkey` fires on the
///   same main-thread turn as the key press — no async hops.
/// - Defaults to Option+Command+5 (⌥⌘5).
/// - Not wired for Fn key — that is Block 15 and requires CGEventTap.
final class HotkeyManager {
    struct Combo: Equatable {
        /// Virtual key code (e.g. kVK_ANSI_5 for "5").
        let keyCode: UInt32
        /// Carbon modifier flags (cmdKey, optionKey, controlKey, shiftKey).
        let modifiers: UInt32

        static let defaultCombo = Combo(
            keyCode: UInt32(kVK_ANSI_5),
            modifiers: UInt32(cmdKey | optionKey)
        )
    }

    /// Invoked synchronously on the main thread each time the hotkey fires.
    /// Runs on the same main-thread turn as the key press — no dispatch hop —
    /// so downstream code can read `NSWorkspace.shared.frontmostApplication`
    /// exactly as it was at the moment the user pressed the combo.
    var onHotkey: (() -> Void)?

    private var hotkeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private static let hotkeyID: UInt32 = 0x776C_686B // 'wlhk'
    private static let signature: OSType = 0x574C_486B // 'WLHk'

    deinit {
        // deinit is not guaranteed to run on any particular queue. Carbon APIs
        // are not thread-safe, so bounce the teardown onto main synchronously.
        if Thread.isMainThread {
            unregister()
        } else {
            DispatchQueue.main.sync { [weak self] in
                self?.unregister()
            }
        }
    }

    /// Register the given combo. Replaces any previous registration.
    /// Returns true on success. Main-thread only.
    @discardableResult
    func register(combo: Combo = .defaultCombo) -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        unregister()

        installEventHandlerIfNeeded()

        let id = EventHotKeyID(signature: Self.signature, id: Self.hotkeyID)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            combo.keyCode,
            combo.modifiers,
            id,
            GetApplicationEventTarget(),
            0,
            &ref
        )

        if status != noErr {
            NSLog("WhisperLocal: RegisterEventHotKey failed with OSStatus \(status)")
            removeEventHandler()
            return false
        }

        self.hotkeyRef = ref
        return true
    }

    /// Main-thread only.
    func unregister() {
        dispatchPrecondition(condition: .onQueue(.main))
        if let ref = hotkeyRef {
            UnregisterEventHotKey(ref)
            hotkeyRef = nil
        }
        removeEventHandler()
    }

    // MARK: - Private

    private func installEventHandlerIfNeeded() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard eventHandlerRef == nil else { return }

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        // userData is a raw pointer to self. passUnretained is safe because the
        // handler lifetime is bounded by HotkeyManager's own lifetime (removed in
        // deinit before self is deallocated).
        let userData = Unmanaged.passUnretained(self).toOpaque()

        let handler: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }

            // Carbon delivers application-target events on the main thread in
            // Cocoa apps. Assert it and fire onHotkey synchronously so the
            // handler runs on the same main-thread turn as the key press.
            // This is critical for Block 5, which captures the frontmost app
            // at the moment of the hotkey press.
            dispatchPrecondition(condition: .onQueue(.main))

            var id = EventHotKeyID()
            let getStatus = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &id
            )
            guard getStatus == noErr else { return getStatus }
            guard id.signature == HotkeyManager.signature, id.id == HotkeyManager.hotkeyID else {
                return OSStatus(eventNotHandledErr)
            }

            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            manager.onHotkey?()
            return noErr
        }

        var ref: EventHandlerRef?
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            &spec,
            userData,
            &ref
        )
        if status != noErr {
            NSLog("WhisperLocal: InstallEventHandler failed with OSStatus \(status)")
            return
        }
        self.eventHandlerRef = ref
    }

    private func removeEventHandler() {
        dispatchPrecondition(condition: .onQueue(.main))
        if let ref = eventHandlerRef {
            RemoveEventHandler(ref)
            eventHandlerRef = nil
        }
    }
}
