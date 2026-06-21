---
name: release-whisperhot
description: End-to-end release pipeline for WhisperHot — version bump, Info.plist sync, CHANGELOG, swift test + Codex review, build .app + DMG, atomic git push, gh release create with DMG asset. User-only (has external side effects). Triggers on "release WhisperHot", "ship WhisperHot", "выпусти релиз", "релиз x.y.z".
disable-model-invocation: true
---

# /release-whisperhot

Full release pipeline. One command from a clean working tree to a published
GitHub release with the DMG attached.

> ⚠️ Side-effects: edits VERSION, Info.plist, CHANGELOG.md; creates a git
> commit + tag; pushes to origin; publishes a GitHub release. Always confirm
> the new version with the user before proceeding.

## Inputs

- New version (e.g. `0.6.8`). If user didn't provide one, ask. Strip leading `v`.
- Optional release notes (markdown). If not provided, draft from `git log
  $LAST_TAG..HEAD --oneline` and offer to user for approval.

## Pipeline order (fail-fast: prove green BEFORE any push)

```
1. pre-flight  →  2. version-validate  →  3. swift-check (clean main)
                                          ↓
4. edit VERSION + Info.plist + CHANGELOG (in working tree only)
                                          ↓
5. swift-check again (post-edit)  →  6. codex review of diff  →  7. release-validator
                                          ↓
8. local commit + local tag (NOT pushed yet)
                                          ↓
9. ./build.sh + ./build-dmg.sh (must succeed against the tagged commit)
                                          ↓
10. git push --atomic origin main vX.Y.Z  →  11. gh release create --verify-tag
                                          ↓
12. verify
```

The key invariant: **nothing leaves the local machine until the DMG is built
from the exact commit that will be tagged**. This eliminates the "tag pushed
but build broken" recovery scenario.

## Steps

### 1. Pre-flight (HALT on any failure)

```bash
git rev-parse --abbrev-ref HEAD             # expect "main"
git status --porcelain                      # expect empty
git fetch --tags origin
git rev-list HEAD..origin/main --count      # expect 0
LAST_TAG=$(git tag --list "v*" --sort=-v:refname | head -1)
```

If branch ≠ main, working tree dirty, or behind origin → STOP.

### 2. Validate version

```bash
NEW="0.6.8"  # user input, stripped of leading "v"
git tag --list "v$NEW"                                    # expect empty
git ls-remote --tags origin "refs/tags/v$NEW"             # expect empty
gh release view "v$NEW" >/dev/null 2>&1 && echo "PUBLISHED" || echo "ok"
```

If already exists → STOP. Memory: rolled-back versions cannot be reused —
`UpdateChecker.compareVersions` is strict `<`.

### 3. swift-check on clean main (early gate)

Invoke `/swift-check`. If FAIL → STOP. No edits made yet, so no rollback.

### 4. Edit release files (Bash, not Edit tool — bypasses version-guard hook)

The version-guard hook intentionally only covers Edit/Write/MultiEdit. Using
`plutil` and `sed` via Bash is the documented release-mode bypass — by design,
not a workaround.

```bash
# 4a. VERSION
printf '%s' "$NEW" > VERSION

# 4b. Info.plist — both the public version and the build number
plutil -replace CFBundleShortVersionString -string "$NEW" Resources/Info.plist
PREV_BUILD=$(plutil -extract CFBundleVersion raw -o - Resources/Info.plist)
NEW_BUILD=$((PREV_BUILD + 1))
plutil -replace CFBundleVersion -string "$NEW_BUILD" Resources/Info.plist
```

### 4c. CHANGELOG.md

Format used by this repo: `## [X.Y.Z] — YYYY-MM-DD`. Insert directly under
the top blurb (line ~3).

If user provided notes, use them. Otherwise draft from
`git log "$LAST_TAG"..HEAD --oneline` and ask the user to approve before
writing. Use today's date from system context (`currentDate`).

Use the Edit tool here (CHANGELOG.md is not version-guarded).

### 5. swift-check again (post-edit)

Same skill, second invocation. Catches: typo in CHANGELOG breaking markdown
linkifiers, accidentally edited files via fat-finger, etc.

### 6. Codex review of the staged diff (memory: codex review every stage)

```bash
git diff HEAD | codex exec --skip-git-repo-check "Review this WhisperHot
release-prep diff for v$NEW. Focus: VERSION matches Info.plist
CFBundleShortVersionString, CFBundleVersion bumped exactly +1, CHANGELOG
section corresponds to actual changes since $LAST_TAG, no stray unrelated
edits. Reply 'GREEN' or specific issues."
```

If Codex hangs >90s, kill (`pkill -f "codex exec"`) and re-run once. After
2 hung attempts, surface to user — don't loop forever (memory). If response
is not "GREEN" → STOP, surface issues.

### 7. release-validator subagent

Invoke via Agent tool with `subagent_type: release-validator`,
`prompt: "Validate readiness for v$NEW release."`. Any CRITICAL/HIGH → STOP.

### 8. Commit + local tag (NOT pushed)

```bash
git add VERSION Resources/Info.plist CHANGELOG.md
git commit -m "chore: bump to v$NEW (build $NEW_BUILD)"
git tag "v$NEW"
```

Note: tag is local-only at this point. Nothing has left the machine.

### 9. Build artifacts (against the tagged commit)

```bash
SIGNING_MODE=developer-id ./build-dmg.sh
# Uses DEVELOPER_ID_APPLICATION_IDENTITY and NOTARY_PROFILE=WhisperHotNotary.
# Falls back to local signing only when the user explicitly asks for a
# personal/non-public build.
```

If the build or notarization fails → STOP. Recovery: investigate, then either fix forward
(`git commit --fixup` + new run, do NOT amend) or `git tag -d v$NEW &&
git reset --soft HEAD~1` to undo locally, fix, redo from step 4. The tag
is local so this is safe.

Verify the produced bundle:
```bash
APP=~/Library/Caches/WhisperHot-build/WhisperHot.app
plutil -extract CFBundleShortVersionString raw -o - "$APP/Contents/Info.plist"  # expect $NEW
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dv "$APP" 2>&1 | grep -q "Authority=Developer ID Application"
```

### 10. Atomic push (branch + tag together)

```bash
git push --atomic origin main "v$NEW"
```

Either both refs land or neither does — no half-pushed state to clean up.
If the push is rejected (e.g. someone pushed in the window between step 1
and now), STOP and surface — do NOT force-push.

### 11. Publish GitHub release (memory: do NOT wait for permission here)

```bash
DMG=~/Library/Caches/WhisperHot-build/WhisperHot-$NEW.dmg
NOTES=$(awk -v v="$NEW" '
  $0 ~ "^## \\["v"\\]" { flag=1; next }
  /^## \[/ { flag=0 }
  flag
' CHANGELOG.md)
gh release create "v$NEW" "$DMG" \
  --verify-tag \
  --latest \
  --title "WhisperHot $NEW" \
  --notes "$NOTES"
```

`--verify-tag` ensures the remote tag matches the commit we just pushed.
The `awk` uses literal `## [X.Y.Z]` to match this repo's CHANGELOG header
style.

### 12. Verify

```bash
gh release view "v$NEW" --json url,assets,name -q '.url, .name, (.assets[].name)'
```

Print URL to user. Done.

## Failure recovery (granular)

| Failed at                          | What's persisted                | Recovery |
|------------------------------------|---------------------------------|----------|
| 1-3 (pre-flight / early swift-check) | nothing                       | nothing to undo |
| 4a-4c (file edits)                 | unstaged working-tree changes   | `git checkout -- VERSION Resources/Info.plist CHANGELOG.md` |
| 5-7 (gates after edit)             | unstaged working-tree changes   | same as 4a-4c |
| 8 (commit succeeds, tag fails)     | bump commit on main             | re-run `git tag v$NEW` directly (the tag is absent) |
| 8 (commit + local tag)             | local commit + local tag        | `git tag -d v$NEW && git reset --soft HEAD~1` then re-run from 4 |
| 9 (build fail)                     | local commit + local tag        | fix code → `git tag -d v$NEW && git commit --amend` (allowed: nothing pushed yet) → `git tag v$NEW` → retry from 9 |
| 10 (atomic push fails)             | local commit + local tag        | resolve remote conflict (probably `git pull --rebase` then redo tag) — atomic means nothing landed |
| 11 (gh release fails)              | branch + tag pushed             | re-run step 11. Tag exists, DMG exists; only the release record was missed |
| 12 (verify fails)                  | release published               | inspect manually; usually a `gh` cache issue |

## Anti-patterns

- DO NOT skip Codex review (step 6) — every-stage rule (memory).
- DO NOT skip release-validator (step 7) — catches Info.plist/VERSION desync.
- DO NOT push tag before build succeeds — that creates "tag without DMG" recovery.
- DO NOT reuse a tag that was rolled back (memory: v0.6.3 rollback shows
  UpdateChecker is strict-greater-than).
- DO NOT publish a release without the DMG attached.
- `--amend` policy: allowed BEFORE step 10 (atomic push). Forbidden once
  `git push --atomic` has succeeded. The recovery row at step 9 uses amend
  because the tag is still local-only there.
- DO NOT wait for user permission to publish the release after build is green
  (memory: explicit auto-publish preference).
- DO NOT temporarily disable `.Codex/settings.json` hooks — use the Bash
  `plutil`/`sed` path which intentionally bypasses the version-guard.
