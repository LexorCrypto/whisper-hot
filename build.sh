#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="WhisperLocal"
BUILD_CONFIG="${BUILD_CONFIG:-release}"

# The project lives in ~/Documents which is synchronised by iCloud Drive.
# The iCloud File Provider continuously re-adds `com.apple.FinderInfo` and
# `com.apple.fileprovider.fpfs#P` extended attributes to files inside that
# tree — fast enough to re-appear between `xattr -cr` and `codesign`. That
# makes codesign refuse with "resource fork, Finder information, or similar
# detritus not allowed".
#
# Assemble and sign the .app outside of the iCloud-synced tree instead.
BUILD_OUT_DIR="${BUILD_OUT_DIR:-${HOME}/Library/Caches/WhisperLocal-build}"
APP_BUNDLE="${BUILD_OUT_DIR}/${APP_NAME}.app"

echo "[1/5] swift build -c ${BUILD_CONFIG}"
swift build -c "${BUILD_CONFIG}"

echo "[2/5] Resolving SwiftPM bin path"
BIN_DIR="$(swift build -c "${BUILD_CONFIG}" --show-bin-path)"
BIN_PATH="${BIN_DIR}/${APP_NAME}"
if [[ ! -x "${BIN_PATH}" ]]; then
  echo "error: binary not found at ${BIN_PATH}" >&2
  exit 1
fi

echo "[3/5] Assembling ${APP_BUNDLE}"
mkdir -p "${BUILD_OUT_DIR}"
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"
# ditto --noextattr copies bytes without extended attributes, so whatever
# xattrs SwiftPM/iCloud left on the intermediate binary never reach the bundle.
ditto --noextattr "${BIN_PATH}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
ditto --noextattr Resources/Info.plist "${APP_BUNDLE}/Contents/Info.plist"

# TODO (Block 6+): when SwiftPM target gains resources (.caf sounds, etc.),
# copy generated ${APP_NAME}_${APP_NAME}.bundle from ${BIN_DIR} into
# ${APP_BUNDLE}/Contents/Resources/ so Bundle.module resolves at runtime.

echo "[4/5] Ad-hoc signing"
# Final defensive sweep in case anything slipped through.
xattr -cr "${APP_BUNDLE}"
codesign --force --deep --sign - --timestamp=none "${APP_BUNDLE}"

echo "[5/5] Done"
echo "Launch with: open \"${APP_BUNDLE}\""
