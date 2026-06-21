---
name: swift-check
description: Run a fresh `swift build -c release` and `swift test` for WhisperHot after Swift changes, before commit/PR, or whenever the user wants to verify the project. Triggers on phrases like "check the build", "run tests", "swift check", "does it compile", "is it green", "verify build", "проверь сборку", "проверь тесты", "проверь проект", "собери", "запусти тесты".
---

# swift-check

Fast correctness gate for WhisperHot: builds the SwiftPM package and runs the test
suite, then returns a compact summary instead of dumping raw compiler output.

## When to invoke

- After non-trivial Swift edits (multiple files, signature changes, new types)
- Before committing or creating a PR
- Before invoking `/codex` review
- When the user explicitly asks to check / verify / build / test the project

## Steps

1. **Run release build** (catches more warnings than debug, matches the release pipeline):
   ```bash
   swift build -c release 2>&1
   ```
   Capture exit code and full output.

2. **Run tests** (only if build succeeded — a failed build implies broken tests):
   ```bash
   swift test 2>&1
   ```
   Capture exit code and full output. Note: `swift test` can also fail during the
   test-target compile step, before any test executes.

3. **Parse output** — do NOT dump raw output to the user. Extract:
   - **Build:** `OK` / `FAIL` + warning count (count `warning:` occurrences).
   - **Tests:** prefer the XCTest final summary line (`Test Suite 'All tests' ... passed/failed`)
     when present; otherwise count `Test Case ... passed`, `Test Case ... failed`,
     and `Test Case ... skipped` (or `XCTSkip`) lines. If no reliable count, report
     `tests: completed` or `tests: FAIL`.
   - **Errors:** first 5 distinct compile/assertion diagnostics with `file:line —
     message`. Output is not order-stable when tests run concurrently — just take
     the first 5 in stream order.
   - **Test-compile failure:** if `swift test` exits non-zero with `error:` lines
     but no test cases ran, label it `tests: FAIL during test compile`.

4. **Report** in one of these exact shapes:

   Success:
   ```
   swift-check:
   ✓ build (release): OK — 0 warnings
   ✓ tests: 12 passed, 0 failed, 0 skipped
   ```

   Build fail:
   ```
   swift-check:
   ✗ build (release): FAIL
     • Sources/WhisperHot/Foo.swift:42 — cannot find 'bar' in scope
     • Sources/WhisperHot/Foo.swift:55 — value of type 'X' has no member 'y'
   tests: skipped (build failed)
   ```

   Test compile fail:
   ```
   swift-check:
   ✓ build (release): OK — 0 warnings
   ✗ tests: FAIL during test compile
     • Tests/WhisperHotTests/FooTests.swift:18 — ...
   ```

   Test runtime fail:
   ```
   swift-check:
   ✓ build (release): OK — 0 warnings
   ✗ tests: 10 passed, 2 failed, 0 skipped
     • ContextRouterTests.testFooBar — XCTAssertEqual failed: expected 1 got 0
   ```

## Anti-patterns

- DO NOT run `swift build` (debug) — release catches more issues and matches the build pipeline.
- DO NOT dump raw compiler output to the user — first-5 errors is a filtered summary, not raw output.
- DO NOT cache test results — always run fresh.
- DO NOT skip tests "because the diff was small" — small diffs break tests too.
- DO NOT rely on output order for meaning when tests run concurrently — just summarize.

## Notes

- Runtime budget: ~30s incremental, up to ~3 min cold cache. If `swift test` takes >2 min, mention it.
- `WhisperHotTests` currently has 2 files: `ContextRouterTests.swift`, `FallbackTranscriptionServiceTests.swift`.
- WhisperHot uses XCTest (no Swift Testing yet) — sticking with XCTest summary parsing is fine today.
- "0 tests" / no tests discovered usually means a target wasn't compiled or filter excluded everything — flag that explicitly.
