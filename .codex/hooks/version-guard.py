#!/usr/bin/env python3
"""PreToolUse hook: block direct edits to release-critical files.

Blocks Edit/Write/MultiEdit on VERSION and Resources/Info.plist unless
WH_ALLOW_VERSION_EDIT=1. Forces version bumps through /release-whisperhot
so VERSION, Info.plist build number, CHANGELOG, and gh release stay in sync.

Path comparison uses os.path.realpath to defeat ./, ../, //, and symlink
bypasses. Falls closed (exit 2) on malformed input — this is a UX guard
against Claude making accidental version edits, not a security boundary
(Bash with sed/echo > can still bypass; enforce in CI/pre-commit if needed).
"""
import json
import os
import sys


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except Exception:
        sys.stderr.write("[version-guard] malformed payload — blocking conservatively\n")
        return 2

    file_path = (payload.get("tool_input") or {}).get("file_path") or ""
    if not file_path:
        return 0

    project = os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
    if not project:
        sys.stderr.write("[version-guard] no project dir — blocking conservatively\n")
        return 2

    def canon(p: str) -> str:
        if not os.path.isabs(p):
            p = os.path.join(project, p)
        return os.path.realpath(p).lower()  # lower() for HFS+/APFS case-insensitive

    target = canon(file_path)
    guarded = {
        canon(os.path.join(project, "VERSION")),
        canon(os.path.join(project, "Resources", "Info.plist")),
    }

    if target not in guarded:
        return 0

    if os.environ.get("WH_ALLOW_VERSION_EDIT") == "1":
        return 0

    sys.stderr.write(
        '[version-guard] Blocked edit to a release-critical file '
        f'(resolved to {target}).\n\n'
        'VERSION and Resources/Info.plist control the WhisperHot release.\n'
        'Editing them directly bypasses the release pipeline\n'
        '(CHANGELOG, build, DMG, gh release).\n\n'
        'If you really mean to bump version:\n'
        '  • use /release-whisperhot (recommended), or\n'
        '  • re-run with WH_ALLOW_VERSION_EDIT=1 to override\n'
    )
    return 2


if __name__ == "__main__":
    sys.exit(main())
