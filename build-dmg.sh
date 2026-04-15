#!/usr/bin/env bash
set -euo pipefail

# Build a distributable .dmg containing WhisperLocal.app and an
# Applications-folder symlink. Ad-hoc signed, no notarization — fine for
# personal / side-loading distribution. Run from the project root.

cd "$(dirname "$0")"

APP_NAME="WhisperLocal"
BUILD_OUT_DIR="${BUILD_OUT_DIR:-${HOME}/Library/Caches/WhisperLocal-build}"

# Sanity-check BUILD_OUT_DIR before we ever hand it to `rm -rf`. The env
# override is convenient for tooling but it must not be a shared or root
# path on someone's machine.
if [[ -z "${BUILD_OUT_DIR}" || "${BUILD_OUT_DIR}" == "/" ]]; then
  echo "error: BUILD_OUT_DIR is empty or points at '/'. Refusing to continue." >&2
  exit 1
fi
case "${BUILD_OUT_DIR}" in
  "${HOME}/Library/Caches/"*|/tmp/*|/private/tmp/*)
    ;;
  *)
    echo "error: BUILD_OUT_DIR (${BUILD_OUT_DIR}) must live under \$HOME/Library/Caches, /tmp, or /private/tmp." >&2
    exit 1
    ;;
esac

APP_BUNDLE="${BUILD_OUT_DIR}/${APP_NAME}.app"

echo "[1/6] Building ${APP_NAME}.app via build.sh"
./build.sh

if [[ ! -d "${APP_BUNDLE}" ]]; then
  echo "error: expected ${APP_BUNDLE} after build.sh, not found" >&2
  exit 1
fi

# Pull version from the bundled Info.plist so the DMG filename stays in
# sync with CFBundleShortVersionString. Wrap the command substitution in
# an `if` so `set -e` does not swallow the extraction failure before we
# can surface a clean message.
echo "[2/6] Reading CFBundleShortVersionString"
if ! VERSION="$(plutil -extract CFBundleShortVersionString raw -o - "${APP_BUNDLE}/Contents/Info.plist")"; then
  echo "error: plutil could not extract CFBundleShortVersionString from ${APP_BUNDLE}/Contents/Info.plist" >&2
  exit 1
fi
if [[ -z "${VERSION}" ]]; then
  echo "error: CFBundleShortVersionString is present but empty" >&2
  exit 1
fi

# Unique stage dir + EXIT trap so an `hdiutil create` failure or a Ctrl-C
# leaves no half-built stage behind for the next run to worry about.
mkdir -p "${BUILD_OUT_DIR}"
STAGE_DIR="$(mktemp -d "${BUILD_OUT_DIR}/dmg-stage.XXXXXX")"
trap 'rm -rf "${STAGE_DIR}"' EXIT

DMG_OUT="${BUILD_OUT_DIR}/${APP_NAME}-${VERSION}.dmg"
rm -f "${DMG_OUT}"

echo "[3/6] Copying ${APP_NAME}.app into ${STAGE_DIR} (no extended attributes)"
# ditto --noextattr mirrors the bundle byte-for-byte but drops Finder info,
# provenance flags, and any other xattr hdiutil / codesign-on-read might
# choke on later. Same reasoning as build.sh.
ditto --noextattr "${APP_BUNDLE}" "${STAGE_DIR}/${APP_NAME}.app"

echo "[4/6] Adding /Applications drop target"
ln -s /Applications "${STAGE_DIR}/Applications"

echo "[5/6] Creating ${DMG_OUT}"
# HFS+ is the right filesystem for a drag-install DMG in 2026: APFS offers
# no advantage here and sacrifices broad compatibility with older readers.
hdiutil create \
  -volname "${APP_NAME}" \
  -srcfolder "${STAGE_DIR}" \
  -ov \
  -format UDZO \
  -imagekey zlib-level=9 \
  -fs HFS+ \
  "${DMG_OUT}"

echo "[6/6] Stage cleanup handled by EXIT trap"

echo ""
echo "DMG ready: ${DMG_OUT}"
echo ""
echo "Install:"
echo "  1. open \"${DMG_OUT}\""
echo "  2. drag ${APP_NAME}.app to the Applications shortcut"
echo "  3. eject the DMG volume"
echo ""
echo "First launch of the INSTALLED copy (from /Applications) will hit"
echo "Gatekeeper because the build is ad-hoc signed, not notarized:"
echo "  right-click /Applications/${APP_NAME}.app → Open,"
echo "  or System Settings → Privacy & Security → 'Open Anyway'."
echo ""
echo "Do NOT launch ${APP_NAME}.app directly from the mounted DMG volume —"
echo "SMAppService and the startup sweep assume a stable install path."
