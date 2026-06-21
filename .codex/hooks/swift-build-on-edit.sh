#!/bin/bash
# PostToolUse hook: incremental `swift build` after Edit/Write/MultiEdit on .swift files.
# Lock + timeout prevent concurrent builds and runaway compile time.
# Always exits 0 so a build failure never blocks the tool result from reaching Claude.

set -u

PAYLOAD=$(cat)
FILE_PATH=$(printf '%s' "$PAYLOAD" | jq -r '.tool_input.file_path // empty')

case "$FILE_PATH" in
  *.swift) ;;
  *) exit 0 ;;
esac

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$PROJECT_DIR" || exit 0

mkdir -p .build 2>/dev/null
LOCK_DIR=".build/.hook-build.lock"

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  echo "[swift-build-hook] another build is running — skipping"
  exit 0
fi
trap 'rmdir "$LOCK_DIR" 2>/dev/null; exit 0' EXIT INT TERM

# Always-available 60s timeout via perl (bundled with macOS)
perl -e 'alarm 60; exec @ARGV' swift build 2>&1 | tail -40

exit 0
