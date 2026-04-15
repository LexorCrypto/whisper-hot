import AppKit
import CoreGraphics

/// Watches the Fn (🌐) modifier via a `CGEventTap` on `.flagsChanged` events.
/// Fires `onFnKeyPressed` synchronously on the main thread each time the user
/// presses Fn (released → pressed transition). Releases are ignored.
///
/// Requires **Input Monitoring** permission. `start()` returns `false` when
/// the tap cannot be created — almost always because the user has not yet
/// granted Input Monitoring access. Callers should check the return and
/// surface a Settings-level hint.
///
/// This is the experimental opt-in from Block 15. Plan §5 keeps the default
/// hotkey as ⌥⌘5 via Carbon `RegisterEventHotKey`; Fn is fragile because
/// macOS owns part of its behavior (Dictation / Show Emoji / Input Source),
/// and there is no public API to override those system bindings.
final class FnKeyMonitor {
    /// Invoked synchronously on the main thread each time Fn is pressed.
    var onFnKeyPressed: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    /// Tracks last known Fn-pressed state so we only fire on the release→press
    /// transition (mirrors Carbon `RegisterEventHotKey`'s press semantics).
    private var previouslyPressed = false

    deinit {
        // deinit is not guaranteed to run on a specific queue. The tap lives
        // on main's runloop; teardown bounces through main.
        if Thread.isMainThread {
            stopInternal()
        } else {
            DispatchQueue.main.sync { [weak self] in
                self?.stopInternal()
            }
        }
    }

    /// Install the event tap on the main runloop. Main-thread only.
    /// Returns `true` on success. Returns `false` when `CGEvent.tapCreate`
    /// refused (most commonly: Input Monitoring permission denied).
    @discardableResult
    func start() -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        stopInternal()

        let userData = Unmanaged.passUnretained(self).toOpaque()
        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else {
                return Unmanaged.passUnretained(event)
            }
            let monitor = Unmanaged<FnKeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
            monitor.handle(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: userData
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.eventTap = tap
        self.runLoopSource = source
        self.previouslyPressed = false
        return true
    }

    /// Uninstall the tap. Safe to call multiple times. Main-thread only.
    func stop() {
        dispatchPrecondition(condition: .onQueue(.main))
        stopInternal()
    }

    private func stopInternal() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
        }
        eventTap = nil
        runLoopSource = nil
        previouslyPressed = false
    }

    /// Called by the CGEventTap C callback on the main runloop.
    private func handle(type: CGEventType, event: CGEvent) {
        // The system can disable our tap if it times out or gets preempted
        // by user input. Re-enable and carry on.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return
        }
        guard type == .flagsChanged else { return }

        let isPressed = event.flags.contains(.maskSecondaryFn)
        if isPressed && !previouslyPressed {
            onFnKeyPressed?()
        }
        previouslyPressed = isPressed
    }
}
