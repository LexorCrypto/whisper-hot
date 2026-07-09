# Codex audit — commit `1440a19`

**Commit:** `1440a19` — build(dmg): default to Developer ID signing + notarization
**Date:** 2026-07-09
**Tool:** OpenAI Codex CLI (`codex exec -s read-only`, `model_reasoning_effort=high`)
**Scope:** committed diff of `build-dmg.sh` (HEAD vs parent)

## Verdict

```
VERDICT: SHIP

No [P1] or [P2] findings in commit 1440a19.

I verified build-dmg.sh against build.sh: the default is now developer-id,
auto-detection is SHA-1 keyed, ambiguity fails closed, and the resolved
SIGNING_MODE / DEVELOPER_ID_APPLICATION_IDENTITY are propagated into build.sh.
SIGNING_MODE=local ./build-dmg.sh still skips DMG signing/notarization.

Checks run: bash -n build-dmg.sh build.sh, shellcheck build-dmg.sh build.sh.
I did not run the full signing/notarization flow because this keychain (Codex
sandbox) currently reports 0 valid identities found. LightRAG was not queried
because the instruction forbids reading the ~/.claude config path.
```

## Notes

- **Gate: PASS** — no P1, no P2.
- An earlier in-session Codex audit of the pre-commit working tree raised one
  `[P2]` (auto-detect deduped candidates by common name, not by cert hash). That
  was fixed before commit by keying the dedupe on the SHA-1; this final audit of
  the committed bytes is clean.
- The "0 valid identities" line is a Codex-sandbox artifact (no keychain access),
  not a repo issue. The real keychain has the Developer ID Application identity
  (Team ID `3Z9833DUR3`), and the full `./build-dmg.sh` run this session
  completed notarization (Apple: Accepted) + staple + `spctl` accepted end-to-end.
