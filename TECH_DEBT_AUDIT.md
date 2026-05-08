# Tech Debt Audit — WhisperHot

Generated: 2026-05-08
Version audited: 0.6.7 (commit `34b1d99`)
Scope: Sources/, Tests/, build scripts, top-level docs

## Executive summary

1. **Test coverage is thin.** 2 test files / 373 LOC against 43 source files / 8.7k LOC. Top-3 churn files (SettingsView, MenuBarController, Preferences — 38 commits in 6mo combined) have **zero** unit tests.
2. **L10n abstraction is half-applied.** `L10n.swift` exists, but **40 call sites bypass it** with inline `L10n.lang == .ru ? "..." : "..."` ternaries — adding a new UI string is a coin flip whether it lives in L10n or inline.
3. **`SettingsView.swift` is a 1026-line god view** with 30+ `@AppStorage` props at the top, six tab computed properties, inline Keychain logic, and inline UserDefaults bindings (bypassing its own `@AppStorage` pattern for localLLM paths).
4. **`DataBuffer` is triplicated byte-for-byte** across `LocalWhisperProvider`, `WhisperInstaller`, `LocalLLMProcessor` — comments in two of them admit it ("same pattern as ...") but nobody promoted it.
5. **Dead entry-point file**: `Sources/WhisperHot/WhisperHotApp.swift` is `@main`-decorated but excluded from compilation by `Package.swift`. Real entry is `Sources/WhisperHotApp/main.swift`. 14 lines of confusion-bait.
6. **Polza.ai shares OpenAI's model preference key and model list** — a user picking a Polza.ai model from the picker gets OpenAI model names, which Polza's catalog may not honour (`Preferences.currentModel` line 189; SettingsView model picker line 888).
7. **Provider URLs are duplicated across 3 files** with no single source of truth — Preferences.swift, TranscriptionCoordinator.swift, OpenRouterAudioProvider.swift each declare endpoint URLs.
8. **`isLocalWhisperReady` is a documented copy** between `MenuBarController:539-545` and `TranscriptionCoordinator:198-207`. The comment literally says "Mirrors TranscriptionCoordinator.makeLocalFallbackIfReady()".
9. **`PostProcessingError.missingAPIKey` is reused as the "binary not found" error** in `LocalLLMProcessor:23` — the comment says "reuse error type", and the user sees "API key is not set" when llama-cli is missing.
10. **MenuBarController menu re-localization is fragile**: `refreshDynamicMenuState` re-walks the menu, matching items by `#selector` to retitle them. Adding a new menu item requires editing both `buildMenu` and this if-else cascade.

The codebase is overall **healthy and disciplined** for a single-developer project: zero compile warnings, zero `TODO`/`FIXME` markers, careful threading in `AudioRecorder`, principled Keychain usage, AES-GCM for history at rest, paste guards for Secure Event Input + AX trust + focus TOCTOU. The debt that exists is concentrated in three files (SettingsView, MenuBarController, Preferences) and one cross-cutting concern (L10n).

## Architectural mental model

WhisperHot is a single-developer macOS menu bar speech-to-text app. AppKit provides the outer shell (NSStatusItem, NSPanel for the recording indicator, NSWindow for Settings/History/Onboarding); SwiftUI lives inside those windows via `NSHostingView`. The choice of AppKit-outside / SwiftUI-inside is deliberate and well-justified in `ARCHITECTURE.md` — `MenuBarExtra` and SwiftUI scenes lack the focus-preservation control that the auto-paste feature requires.

The hot path is: hotkey (Carbon `RegisterEventHotKey` or experimental Fn via `CGEventTap`) → `MenuBarController.toggleRecording` → `AudioRecorder` (AVAudioEngine + serial writer queue, real-time-thread-safe with `OSAllocatedUnfairLock`) writes 16 kHz mono PCM WAV → on stop, `TranscriptionCoordinator.fromPreferences` snapshots prefs and constructs the pipeline → `FallbackTranscriptionService` wraps a primary STT provider with optional offline-on-timeout race against a local whisper.cpp subprocess (ADR-014) → `LLMPostProcessor` or `LocalLLMProcessor` cleans up → `PasteService` writes pasteboard and synthesizes Cmd+V (with Secure Event Input, AX trust, focus, and target-still-running guards).

State boundaries are clean: `Preferences` is the typed accessor over `UserDefaults` for non-SwiftUI consumers, `Keychain` wraps `kSecClassGenericPassword` for API keys plus a 32-byte AES-GCM key for `HistoryStore`, and `TranscriptionCoordinator` is `Sendable` so it can be handed to `Task.detached`. The threading model (main-thread for state machine + UI, real-time tap thread for audio capture, serial writer queue for disk I/O) is documented in `ARCHITECTURE.md` and respected throughout.

The debt clusters where it always clusters: in the SwiftUI form view that owns most of the UI (1026 LOC, 14 commits in 6mo), in the menu bar state machine that owns most of the orchestration (871 LOC, 13 commits), and in the preferences module that everyone depends on (564 LOC, 11 commits). None of these are unmaintainable today; all three are at the size where the next round of features will start to hurt.

## Findings

| ID | Category | File:Line | Severity | Effort | Description | Recommendation |
|----|----------|-----------|----------|--------|-------------|----------------|
| F001 | Test debt | Tests/WhisperHotTests/ | Critical | L | Only 2 test files / 373 LOC against 8.7k LOC of production code. ContextRouter and FallbackTranscriptionService are tested; HistoryStore (encryption, key rotation), Keychain wrapper, Preferences accessors, AudioRecorder lifecycle, PasteService guards, providers (with mocked URLSession), LocalWhisperProvider subprocess handling, WordReplacement application — all untested. | Add provider tests (mocked URLSession), Preferences round-trip tests, HistoryStore encrypt/decrypt round-trip, WordReplacement.applyAll. Aim for 60%+ coverage on the Transcription, History, and PostProcessing modules. |
| F002 | Architectural decay | Sources/WhisperHot/WhisperHotApp.swift:1-14 | Medium | S | `@main enum WhisperHotApp` declared but `Package.swift:11` excludes the file from `WhisperHotLib`. Real entry point is `Sources/WhisperHotApp/main.swift:1-9`. The two files duplicate each other and the dead one will mislead any reader who lands there first. | Delete `Sources/WhisperHot/WhisperHotApp.swift` and remove the `exclude:` directive in `Package.swift:11`. |
| F003 | Architectural decay | Sources/WhisperHot/Transcription/Providers/LocalWhisperProvider.swift:6-21 / Sources/WhisperHot/LocalSetup/WhisperInstaller.swift:4-19 / Sources/WhisperHot/PostProcessing/LocalLLMProcessor.swift:130-145 | High | S | `private final class DataBuffer: @unchecked Sendable` is byte-for-byte identical in all three files (NSLock-guarded `Data` accumulator). Two of them carry comments admitting the duplication ("same pattern as WhisperInstaller", "same pattern as LocalWhisperProvider"). | Promote to internal `Sources/WhisperHot/Concurrency/DataBuffer.swift`. Remove all three private copies. |
| F004 | Architectural decay | Sources/WhisperHot/MenuBarController.swift:537-545 / Sources/WhisperHot/Transcription/TranscriptionCoordinator.swift:198-207 | High | S | `isLocalWhisperReady()` and `makeLocalFallbackIfReady()` duplicate the same four-line check (binary path non-empty + executable, model path non-empty + exists). Comment at MenuBarController:537 documents the duplication: *"Mirrors TranscriptionCoordinator.makeLocalFallbackIfReady()"*. | Move the readiness check to `Preferences.isLocalWhisperReady` (or a new `LocalWhisper` namespace). Both call sites use it. |
| F005 | Architectural decay | Sources/WhisperHot/Settings/SettingsView.swift:13-1026 | High | L | 1026-line single-file SwiftUI view: 30+ `@AppStorage` props at top, 6 tab computed properties, inline Keychain `save`/`delete` logic in `apiKeyControls`, inline `UserDefaults.standard` bindings for localLLM paths (bypassing its own `@AppStorage` pattern), normalization logic (`normalizeStorageValues`). Hottest churn file (14 commits in 6mo). | Split into `SettingsRecordingTab.swift`, `SettingsProvidersTab.swift`, `SettingsPostProcessingTab.swift`, `SettingsHotkeyTab.swift`, `SettingsHistoryPrivacyTab.swift`, `SettingsUpdatesTab.swift`. Extract a `KeychainBindingViewModel` for the per-provider key+status pairs. Move `apiKeyControls` and `apiKeyAndModelSection` into a `Components/` subfolder. |
| F006 | Architectural decay | Sources/WhisperHot/MenuBarController.swift:1-871 | Medium | L | 871-line state-machine hub with mixed concerns: status item button, menu construction, NSMenuDelegate, hotkey lifecycle (Carbon + Fn retry timer), recording lifecycle, transcription orchestration, error UI, paste delegation, About/Onboarding/History/Settings window dispatching. Decisions.md:290 already lists this as deferred work. | Extract `MenuBuilder` (buildMenu + refreshDynamicMenuState), `RecordingStateMachine` (toggleRecording + start/stop/finish), and a `HotkeyTransport` that hides the Fn-vs-Carbon switch. Already in the backlog per decisions.md. |
| F007 | Architectural decay | Sources/WhisperHot/MenuBarController.swift:442-471 | Medium | M | `refreshDynamicMenuState` re-localizes menu titles by walking `menu.items` and matching each item via `item.action == #selector(...)`. Adding a new menu entry requires editing both `buildMenu` and this if-else cascade — and a typo'd selector match silently leaves the title stale. | Cache menu items in named `private var` references (already done for `recordMenuItem`, `headerMenuItem`, `providerSubmenu`, `autoOfflineOnTimeoutMenuItem`). Do the same for `historyItem`, `settingsItem`, `onboardingItem`, `aboutItem`, `quitItem`, `providerParent` and retitle directly. |
| F008 | Architectural decay | Sources/WhisperHot/Audio/AudioRecorder.swift:29 | Low | S | `private let hadErrorLock = OSAllocatedUnfairLock<Bool>(initialState: false)` is set by tap (line 217) and writer (line 232) callbacks but never read by anyone. Dead state. | Either expose `hadError` to `MenuBarController.finishTranscription` to surface a "recording had write errors" warning, or delete the field. |
| F009 | Consistency rot | Sources/WhisperHot/Settings/SettingsView.swift (multiple) + MenuBarController.swift (multiple) + WhisperInstaller.swift (multiple) | High | M | **40 call sites use inline `L10n.lang == .ru ? "..." : "..."` ternaries** instead of adding a key to `L10n.swift`. Examples: SettingsView:99, 211, 213, 220-222, 251, 260-262, 385, 396, 399, 421, 425, 435, 468-470, 621, 628, 635-637, 644, 803, 805, 817, 822, 829, 833, 843, 851-853; MenuBarController:94-96, 531-533, 730-732, 770-772; WhisperInstaller:97-99, 103, 126-128. | Sweep: each unique string pair becomes a new key in `L10n.swift`. Lint rule (or Codex check on PR) to fail on `L10n.lang == .ru` outside `L10n.swift` itself. |
| F010 | Consistency rot | Sources/WhisperHot/Settings/Preferences.swift:449-457 (IndicatorStyle.displayName) + Sources/WhisperHot/Localization/L10n.swift:141-149 (L10n.indicatorStyleName) | Medium | S | Two parallel implementations of the same concept: `IndicatorStyle.displayName` returns hardcoded English, `L10n.indicatorStyleName(_:)` returns the localized version. SettingsView:205 uses `style.displayName` — the L10n version is **dead**. | Delete `IndicatorStyle.displayName`. Update SettingsView:205 to call `L10n.indicatorStyleName(style)`. Same drift exists in `AudioRetention.displayName` (Preferences:415-435) — also English-only. |
| F011 | Consistency rot | Sources/WhisperHot/Transcription/TranscriptionCoordinator.swift:169,180,186 + Sources/WhisperHot/Settings/Preferences.swift:498-501 + Sources/WhisperHot/Transcription/Providers/OpenRouterAudioProvider.swift:13 | Medium | S | Provider endpoint URLs declared in 3 files: TranscriptionCoordinator hardcodes 3 STT URLs, Preferences hardcodes 4 chat URLs, OpenRouterAudioProvider hardcodes its own. Adding a new provider or changing a base path requires synchronized edits across all sites. | Add `static var sttEndpoint: URL { ... }` and `static var chatEndpoint: URL { ... }` accessors to `TranscriptionProvider` and `PostProcessingProvider`. Single source of truth. |
| F012 | Consistency rot | Sources/WhisperHot/Settings/SettingsView.swift:622-633 | Medium | S | `localLLMBinaryPath` and `localLLMModelPath` use raw `UserDefaults.standard.string/.set` bindings inline. Every other path field uses `@AppStorage(Preferences.Key...)`. Inconsistent storage access. | Add `@AppStorage(Preferences.Key.localLLMBinaryPath) private var localLLMBinaryPath: String = ""` to the props block at top of SettingsView. Same for model path. |
| F013 | Consistency rot | Sources/WhisperHot/Settings/Preferences.swift:46-77 | Medium | S | `Preferences.Defaults` struct documents itself as the source of truth for first-run values, but is missing entries for `appLanguage`, `vocabularyHints`, `localLLMBinaryPath`, `localLLMModelPath`, `wordReplacements`, `contextRules`. Each absent default is handled at the call site (L10n.swift:22 defaults to .ru, SettingsView:41 also defaults to .ru, etc.). | Add the missing entries and register them in `registerDefaults()`. Centralizes the contract. |
| F014 | Consistency rot | Sources/WhisperHot/Settings/SettingsView.swift:594 + 867 | Low | S | Two `switch provider` blocks with 5-6 cases each: `ppModelSection` and `modelPicker`. Adding a new provider requires synchronized edits. | Acceptable for the count, but if a 6th provider lands, extract a `ProviderModelControls` view that takes the provider as input. Defer until then. |
| F015 | Type & contract | Sources/WhisperHot/PostProcessing/LocalLLMProcessor.swift:22-27 | High | S | `throw PostProcessingError.missingAPIKey` is used for "binary not executable" and "model file missing". The comment line 23 admits it: *"// reuse error type"*. User sees "API key is not set for the post-processing provider" when llama-cli is missing or the GGUF path is wrong. | Add `case missingLocalBinary(path: String)` and `case missingLocalModel(path: String)` to `PostProcessingError`. Surface real diagnostics. |
| F016 | Type & contract | Sources/WhisperHot/Settings/Preferences.swift:184-194 + Sources/WhisperHot/Settings/SettingsView.swift:888-892 + Sources/WhisperHot/Transcription/TranscriptionCoordinator.swift:184-189 | Medium | M | Polza.ai shares the OpenAI model preference key (`modelOpenAI`) and the OpenAI model list (`availableOpenAIModels`). The user pickers Polza.ai → sees OpenAI's `gpt-4o-mini-transcribe`, etc. → that name may not exist in Polza's catalog. The displayName claims it's "OpenAI-совместимый" but model identifiers are not guaranteed to overlap. | Either give Polza.ai its own preference key + model list, or change the model field for Polza.ai to a free-text TextField (since the caller is expected to know their Polza catalog). Currently a footgun. |
| F017 | Type & contract | Sources/WhisperHot/Audio/AudioRecorder.swift:277-296 | Low | S | `computeRMS` returns `0` for any input format that isn't `.pcmFormatFloat32`. macOS hardware overwhelmingly delivers float32 today, but on a future audio device with int16 input, the RMS indicator silently shows zero. | Add a `NSLog` warning on the first non-float32 buffer (one-shot via boolean flag) so a future regression is observable. |
| F018 | Test debt | Sources/WhisperHot/History/HistoryStore.swift | High | M | Encryption/decryption logic with multiple state branches (Keychain present + history present, Keychain absent + history absent, Keychain absent + history present orphan, key-length mismatch). Zero tests. The orphan-detection logic is exactly the kind of thing that quietly breaks when refactored. | Add `HistoryStoreTests.swift` covering: round-trip encrypt → decrypt, fresh-install path (no key + no file), orphan detection (no key + file present), key length mismatch, prune-by-retention, prune-by-max-entries. |
| F019 | Test debt | Sources/WhisperHot/Keychain/Keychain.swift | High | M | All API key handling routes through this; zero tests. The save-or-update flow (line 53-75) and the data-vs-string distinction (line 117-148 vs line 35-76) both have edge cases worth pinning. | Add `KeychainTests.swift` against a unique service name to round-trip save / update / read / delete / readData / saveData. |
| F020 | Test debt | Sources/WhisperHot/Transcription/Providers/OpenAICompatibleSTTProvider.swift / OpenRouterAudioProvider.swift / LocalWhisperProvider.swift | High | M | Multipart body assembly, HTTP error handling, audio file size validation, missing-key detection — all untested. The recent v0.6.6/v0.6.7 fixes around timeout race and cancellation propagation got tests; the providers themselves did not. | Add provider tests using a stubbed `URLSession` (URLProtocol-based mock). At minimum: missing-key path, oversized-file path, 4xx body capture, empty-transcript handling. |
| F021 | Test debt | Sources/WhisperHot/Paste/PasteService.swift | Medium | M | Six guard branches (no target, terminated, AX denied, focus mismatch, secure input, own-app frontmost) with distinct outcomes. None of them have unit tests. Hard to write since `IsSecureEventInputEnabled` and `AXIsProcessTrusted` are not directly mockable, but at least the focus-mismatch and terminated branches are pure logic. | Refactor `deliver` to take its environment (frontmost app, AX trust, secure input, pasteboard) as injected closures, then test the decision tree. |
| F022 | Test debt | Sources/WhisperHot/Transcription/WordReplacement.swift | Low | S | `WordReplacement.applyAll` is referenced by TranscriptionCoordinator at every transcription. Untested. | Trivial to add: empty-list, single-replacement, case-insensitive match, overlap behavior. |
| F023 | Dependency & config | Package.swift | Low | n/a | Zero external dependencies. `swift build` produces zero warnings. No `npm audit` / `pip-audit` equivalent applies; SwiftPM has no audit tool today. | Nothing material. Continue zero-deps for portability. |
| F024 | Dependency & config | Sources/WhisperHot/LocalSetup/WhisperInstaller.swift:44 + Sources/WhisperHot/Settings/Preferences.swift:498-501 + Sources/WhisperHot/Transcription/TranscriptionCoordinator.swift:169,180,186 + Sources/WhisperHot/Transcription/Providers/OpenRouterAudioProvider.swift:13 | Low | S | 9 force-unwrapped `URL(string: "https://...")!` literals across the codebase. The literals are valid; `precondition`-style `!` is idiomatic Swift here. Mostly fine, but combined with F011 (URLs duplicated across 3 files) becomes a maintenance hotspot. | Solved by F011 (single source of truth eliminates 7 of the 9). The huggingface URL in WhisperInstaller and the OpenRouter URL on its provider can stay as-is. |
| F025 | Performance | Sources/WhisperHot/Transcription/Providers/OpenAICompatibleSTTProvider.swift:54-91 + Sources/WhisperHot/Transcription/Providers/OpenRouterAudioProvider.swift (similar pattern) | Low | M | `Data(contentsOf:options:.mappedIfSafe)` then full multipart body assembly into a single in-memory `Data`. For a 25 MB WAV this means the file lives twice in memory (mapped + body). Personal voice notes are <2 MB, so impact in practice is nil; but if a user ever uploads a 25 MB clip the resident memory spike is 50+ MB. | Use `URLSession.upload(for:fromFile:)` with a multipart-prefixed temp file, OR construct the multipart with `InputStream`. Defer until someone hits the size cap. |
| F026 | Performance | Sources/WhisperHot/Transcription/Providers/LocalWhisperProvider.swift:75-168 | Medium | M | Subprocess has no internal timeout. If whisper.cpp hangs (corrupt model, OOM, zombie thread), the parent task waits forever. ADR-014 documents the cancellation gap (continuation does not observe `Task.cancel()`); ADR-014 chose to gate fallback to "after race resolves" but did not fix the underlying issue. | Add a watchdog `Task.sleep(nanoseconds:)` inside the continuation that fires `process.terminate()` after, say, 5 minutes. Same for `LocalLLMProcessor` (line 41-126). |
| F027 | Error handling | Sources/WhisperHot/Audio/AudioRecorder.swift:241-252 | Low | S | On `.AVAudioEngineConfigurationChange` the recorder calls `_ = try? self.stopRecording()` AND `self.onAutoStop?()`. If a configuration change fires *during* the user's own stop button press, `stopRecording()` runs twice. The `try?` swallows the resulting `notRecording` error, so the path is safe but obscure. | Replace `try?` with an `if isRecording { try? stopRecording() }` guard, or have `stopRecording` be idempotent and not throw on `notRecording`. |
| F028 | Error handling | Sources/WhisperHot/PostProcessing/LLMPostProcessor.swift:48-53 | Low | S | `JSONSerialization.data(withJSONObject:)` throws `invalidResponse` if it ever fails. The body is built from a hard-coded shape that cannot fail with the literal data passed in (model: String, temperature: Double, messages: [...]). The `do/catch` is dead defensive code that misclassifies "you can't reach this" as "the API returned something invalid". | Replace with `try!` and a comment, OR convert to `Encodable` struct with `JSONEncoder` so the type system enforces the shape. |
| F029 | Error handling | Sources/WhisperHot/ (61 NSLog call sites) | Low | M | `NSLog` is the sole logging mechanism; no levels, no categories, no structured output. `os.Logger` would give you per-subsystem filtering, OSLogStore queries, and Console.app integration for free. The `os` framework is already imported (in AudioRecorder for `OSAllocatedUnfairLock`). | Introduce a `Log.transcription`, `Log.audio`, `Log.history` set of `os.Logger` instances. Migrate hot paths first (Transcription, Audio, History). NSLog stays acceptable for catastrophic-only paths. |
| F030 | Security | Sources/WhisperHot/Keychain/Keychain.swift:35-148 | Low | S | `save(apiKey:)` and `saveData(_:)` are 90% identical (UTF-8 conversion is the only difference). `readAPIKey` and `readData` similar. ~50 lines of structural duplication; not a security issue but a maintenance one — a future fix to update-vs-add semantics has to be applied twice. | Extract a private `static func saveRaw(_ data: Data, account:)` and a private `static func readRaw(account:) -> Data`. The two public APIs become 2-line wrappers. |
| F031 | Security | Sources/WhisperHot/LocalSetup/WhisperInstaller.swift:167 | Low | S | `process.environment = ProcessInfo.processInfo.environment` passes ALL env vars (including HOMEBREW_INSTALL_FROM_API, HOMEBREW_NO_AUTO_UPDATE, etc.) to the brew subprocess. An attacker with shell access could already break Homebrew anyway, so the practical risk is low; but explicitly allowlisting `PATH`, `HOME`, `USER`, `LANG` is more hygienic. | `process.environment = ["PATH": ..., "HOME": ..., "USER": ..., "LANG": ...]`. Brew needs PATH and HOME at minimum. |
| F032 | Security | Sources/WhisperHot/PostProcessing/LLMPostProcessor.swift:78 | Low | S | `bodyText` from a non-2xx HTTP response is included in the user-facing error string (truncated to 300 chars at PostProcessingPreset.swift:74). Today no provider echoes the request body in error responses, so the transcript stays out of the error UI. If a future provider does echo (e.g. validation errors that re-quote the user message), the transcript leaks into a banner that may persist on screen. | Truncate to 100 chars and strip non-printable content before display. Or stop showing the body to the user and only log it. |
| F033 | Security | Sources/WhisperHot/Paste/PasteService.swift:50-108 | Low | n/a | Six-guard delivery sequence: pasteboard write → target captured → target alive → AX trust → frontmost match → secure input check → CGEventPost. Documented well in `decisions.md` and stable. The TOCTOU window between `IsSecureEventInputEnabled` and `keyDown.post` is microscopic and acknowledged in ARCHITECTURE.md residual risks. | Nothing material. Solid for the threat model. |
| F034 | Documentation drift | Sources/WhisperHot/MenuBarController.swift:618 | Low | S | Stale comment: `// Provider factories moved to TranscriptionCoordinator.swift` is a refactor breadcrumb that's been there since the v0.6.0 split. Pure noise to a fresh reader. | Delete. |
| F035 | Documentation drift | Sources/WhisperHot/PostProcessing/LocalLLMProcessor.swift:23 | Low | n/a | `// reuse error type` comment effectively documents tech debt F015. Honest, but the right fix is to remove the reuse, not to keep documenting it. | Solved when F015 is solved. |
| F036 | Documentation drift | ARCHITECTURE.md, CLAUDE.md, decisions.md | Low | n/a | Already corrected in this session: LOC counts updated to ~8700, MenuBarController to ~870, all version refs at 0.6.7. CHANGELOG and README current. | Nothing further. |

## Top 5 — if you fix nothing else, fix these

### 1. F001 — Backfill provider, Preferences, History, and Keychain tests

The audit found exactly two test files. Every release since v0.6.2 has been signed off via Codex review and manual smoke-testing in production, which has caught real bugs (the cancellation-propagation bug fixed in v0.6.7 is a textbook example). But manual review does not regress. The next refactor — splitting MenuBarController, splitting SettingsView, swapping a provider — will silently break things that today nobody notices.

Concrete first targets, in priority order:

- `WordReplacementTests.swift` — pure logic, no mocks needed, ~15 minutes.
- `KeychainTests.swift` — round-trip against a unique service name (`com.aleksejsupilin.WhisperHot.tests`).
- `HistoryStoreTests.swift` — encrypt/decrypt round-trip + the orphan detection (no key + file exists path).
- `OpenAICompatibleSTTProviderTests.swift` — `URLProtocol` mock for HTTP. Pin the multipart body shape, the missing-key path, the oversized-file path, and the 4xx body capture.

### 2. F003 + F004 + F015 — De-duplicate the small obvious things

These are three high-confidence, low-effort wins that together remove ~80 lines of duplication and one honest type lie.

```swift
// Sources/WhisperHot/Concurrency/DataBuffer.swift  (new file)
import Foundation

final class DataBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()
    func append(_ chunk: Data) { lock.lock(); defer { lock.unlock() }; storage.append(chunk) }
    func snapshot() -> Data { lock.lock(); defer { lock.unlock() }; return storage }
}
```

Then delete the three private copies. Same shape for `LocalWhisperReady`:

```swift
// Sources/WhisperHot/Settings/Preferences.swift  (add)
extension Preferences {
    static var isLocalWhisperReady: Bool {
        let bin = localWhisperBinaryPath, model = localWhisperModelPath
        guard !bin.isEmpty, !model.isEmpty else { return false }
        return FileManager.default.isExecutableFile(atPath: bin)
            && FileManager.default.fileExists(atPath: model)
    }
}
```

And for the `PostProcessingError` lie:

```swift
// Sources/WhisperHot/PostProcessing/PostProcessingPreset.swift  (modify)
enum PostProcessingError: LocalizedError {
    case missingAPIKey
    case missingLocalBinary(path: String)   // NEW
    case missingLocalModel(path: String)    // NEW
    case networkFailure(underlying: Error)
    case httpError(status: Int, body: String)
    case invalidResponse
    case emptyResponse
    // ...
}
```

### 3. F009 — Sweep inline `L10n.lang == .ru ? "..." : "..."` into L10n.swift

40 sites today. Not because anyone decided that was the pattern — because each site was a one-off "I'll just put the string here" decision that compounded. The L10n module exists; the discipline doesn't. Two tactical moves:

- **Now:** sweep all 40 sites into `L10n.swift` keys. Mechanical, ~1 hour with grep.
- **Going forward:** add a Codex check (or a lint pass in `swift-check`) that fails on any `L10n.lang == .ru` outside `L10n.swift` itself. Pattern: `grep -rn "L10n\.lang == \.ru" Sources/ | grep -v "Localization/L10n.swift"` returning non-empty = fail.

This is the single highest leverage change for keeping the L10n module from rotting further.

### 4. F005 + F006 — Schedule the SettingsView and MenuBarController split

Both are flagged in `decisions.md` already as known deferred work. The audit confirms: SettingsView at 1026 LOC and MenuBarController at 871 LOC are the two highest-churn files in the codebase, and every recent feature touches at least one of them.

Order matters: split SettingsView first. It has clean section boundaries (six tabs as computed properties) and the split is mostly mechanical — extract each tab to its own file, share a small `SettingsState` struct or a parent `@StateObject` if cross-tab state needs to flow. Aim for files <400 LOC each.

MenuBarController is harder — the state machine is intertwined with menu construction, hotkey transport, and window dispatching. Defer until SettingsView is split and the test scaffolding from F001 is in place.

### 5. F002 — Delete `Sources/WhisperHot/WhisperHotApp.swift`

14 lines of dead code at the project entry point will mislead the next reader. The fix is a `git rm` and a one-line edit to `Package.swift`. Do this in the same commit as the next housekeeping pass.

```diff
-        .target(
-            name: "WhisperHotLib",
-            path: "Sources/WhisperHot",
-            exclude: ["WhisperHotApp.swift"]
-        ),
+        .target(
+            name: "WhisperHotLib",
+            path: "Sources/WhisperHot"
+        ),
```

## Quick wins

Low-effort findings with immediate value:

- [ ] **F002** — Delete dead `WhisperHotApp.swift` + the `exclude:` directive. ~5 min.
- [ ] **F003** — Promote `DataBuffer` to a single shared file. ~15 min.
- [ ] **F004** — Move `isLocalWhisperReady` into `Preferences`. ~10 min.
- [ ] **F008** — Either expose `hadError` or delete the field. ~10 min.
- [ ] **F010** — Delete `IndicatorStyle.displayName`, point SettingsView at `L10n.indicatorStyleName`. ~10 min.
- [ ] **F012** — Convert localLLM path bindings to `@AppStorage`. ~10 min.
- [ ] **F013** — Add the missing `Defaults` entries + register them. ~15 min.
- [ ] **F015** — Add `missingLocalBinary` / `missingLocalModel` cases to `PostProcessingError`. ~15 min.
- [ ] **F022** — Add `WordReplacementTests`. ~20 min.
- [ ] **F034** — Delete the stale "moved to TranscriptionCoordinator" comment. ~30 sec.

These ten changes remove ~120 lines of duplication, fix one mis-typed error, eliminate dead code, and add the easiest possible test file. Roughly 90 minutes of work for a measurable health bump.

## Things that look bad but are actually fine

The protocol requires this section. None of these were flagged after deliberation:

- **`MenuBarController.swift` at 871 LOC.** Looks like a god class. In practice it's a state-machine hub with clear `MARK: -` sections, methods averaging 15-30 lines, and zero nested concerns. Splitting is in the backlog (F006); splitting prematurely would hurt more than it helps.
- **`@unchecked Sendable` on `DataBuffer` and `LLMPostProcessor`.** Looks like a Sendable-correctness skip. In practice both classes are correctly synchronized — `DataBuffer` via NSLock with all mutators private, `LLMPostProcessor` via stateless instance methods. `@unchecked` is the right marker because the compiler can't prove what NSLock does.
- **The 9 force-unwrapped `URL(string: "https://...")!` literals.** Looks dangerous. The literals are statically valid; this is `precondition`-style assertion, not actual error swallowing. Idiomatic Swift.
- **All 12 `try?` sites.** Looks like swallowed errors. Each one is a nondestructive cleanup path (file removal where missing-is-fine, JSON decode of stored prefs with a typed default fallback). The discipline is consistent.
- **Parallel switches in `Preferences` (`TranscriptionProvider.displayName/shortName/keychainAccount`, `PostProcessingProvider.displayName/keychainAccount/endpoint/extraHeaders`).** Looks like duplication. Each enum case has materially different attributes; converting to dictionaries would lose Swift's exhaustiveness checking — a real safety net for "add a new provider, forget a switch arm".
- **AVAudioEngineConfigurationChange auto-stop branch.** Looks racy (calls `stopRecording()` while the user might also be calling it). The `dispatchPrecondition(.onQueue(.main))` + `isRecording` guard makes the double-stop path safe. Flagged as F027 only because a comment would help; not a real bug.
- **`WhisperInstaller.DownloadDelegate.urlSession(_:task:didCompleteWithError:)` only fires `onComplete` on error.** Looks like a missing success path. `didFinishDownloadingTo` IS the success path, fires before `didCompleteWithError`, and gates on the move succeeding. Continuation can only resume once. Correct.
- **`HistoryStore.encryptionKey` four-step state machine.** Looks paranoid. It's actually solving a real problem: never silently mint a new key when ciphertext exists, never panic when both key and ciphertext are absent, never trust a key that's not exactly 32 bytes. The complexity is load-bearing.
- **`PasteService` six-guard sequence.** Looks like over-engineering. Each guard has a recorded incident or threat in the design log: TOCTOU on focus, Secure Event Input on password fields, AX trust prerequisite for CGEventPost, target-process-died, our-own-app-frontmost. All real, all kept.
- **Zero compile warnings + zero `TODO`/`FIXME` markers.** Looks suspicious for an 8.7k LOC project. Manual scan confirms it: the discipline really is this consistent. Worth keeping.

## Open questions for the maintainer

- **OQ1** — `Sources/WhisperHot/Settings/SettingsView.swift:622-633`: Was bypassing `@AppStorage` for the localLLM paths intentional (e.g., to avoid noisy `UserDefaults.didChange` notifications during text-field typing)? Or just missed when adding the local LLM feature in v0.6.0? This determines whether F012 is a 10-minute fix or whether the inline binding is load-bearing.

- **OQ2** — `Sources/WhisperHot/Settings/Preferences.swift:184-194`: Polza.ai's model picker pulls from `availableOpenAIModels`. Was this deliberate (because Polza is OpenAI-compatible and you expect users to know what to type) or a copy-paste oversight when Polza was added in v0.4.0? Same for the SettingsView model picker arm at line 888.

- **OQ3** — `decisions.md:290` lists MenuBarController split as deferred. Is **SettingsView** split also deferred, or just not yet considered? At 1026 LOC and 14-commit churn, it's arguably the more urgent of the two.

- **OQ4** — `IndicatorStyle.displayName` (Preferences.swift:449) returns English regardless of language; `L10n.indicatorStyleName(_:)` (L10n.swift:141) returns the localized version; SettingsView calls the former. Was the L10n version added later and the call site never migrated, or is the English-only version intentional in some contexts?

- **OQ5** — Is there appetite for a "minimum coverage gate" via a CI test count check? Two test files for an 8.7k LOC codebase is unusual for a project this disciplined; either the bar moves up over time or it stays here. The audit's ranking of F001 as Critical assumes the answer is "it should move up".
