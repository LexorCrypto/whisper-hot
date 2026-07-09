#!/usr/bin/env bash
set -euo pipefail

# Build a distributable .dmg containing WhisperHot.app and an
# Applications-folder symlink. By default it runs the full release-correct
# flow: Developer ID signing + Hardened Runtime + notarization + staple,
# auto-detecting the Developer ID Application identity from the keychain so
# no env var is required. For a quick unsigned personal build that skips
# notarization, run: SIGNING_MODE=local ./build-dmg.sh
# Run from the project root.

cd "$(dirname "$0")"

APP_NAME="WhisperHot"
BUILD_OUT_DIR="${BUILD_OUT_DIR:-${HOME}/Library/Caches/WhisperHot-build}"
SIGNING_MODE="${SIGNING_MODE:-developer-id}"
NOTARIZE="${NOTARIZE:-auto}"
NOTARY_PROFILE="${NOTARY_PROFILE:-WhisperHotNotary}"

case "${SIGNING_MODE}" in
  local|developer-id)
    ;;
  *)
    echo "error: SIGNING_MODE must be 'local' or 'developer-id' (got '${SIGNING_MODE}')" >&2
    exit 1
    ;;
esac

case "${NOTARIZE}" in
  auto|1|true|yes|on|0|false|no|off)
    ;;
  *)
    echo "error: NOTARIZE must be auto, yes, or no (got '${NOTARIZE}')" >&2
    exit 1
    ;;
esac

should_notarize=false
case "${NOTARIZE}" in
  auto)
    [[ "${SIGNING_MODE}" == "developer-id" ]] && should_notarize=true
    ;;
  1|true|yes|on)
    should_notarize=true
    ;;
esac

if [[ "${should_notarize}" == "true" && "${SIGNING_MODE}" != "developer-id" ]]; then
  echo "error: notarization requires SIGNING_MODE=developer-id." >&2
  exit 1
fi

# Discover the Developer ID Application identity from the keychain so a
# release build "just works" without the caller exporting an env var. Emits
# the single common name on stdout; on 0 or >1 matches it lists candidates
# on stderr and exits non-zero. Success and failure use disjoint streams, so
# the caller can safely merge them with 2>&1 and branch on the exit code.
auto_detect_developer_id() {
  security find-identity -v -p codesigning 2>/dev/null \
    | awk '
      /"Developer ID Application:/ {
        # Key on the cert SHA-1 so two identities that share a common name
        # but differ by hash count as two candidates (ambiguous -> fail),
        # not one. Fall back to the whole line if no hash is present.
        key = (match($0, /[A-F0-9]{40}/)) ? substr($0, RSTART, RLENGTH) : $0
        split($0, parts, "\"")
        cn = parts[2]
        if (!seen[key]++) names[++n] = cn
      }
      END {
        if (n == 1) { print names[1]; exit 0 }
        if (n == 0) { exit 2 }
        for (i = 1; i <= n; i++) print names[i] > "/dev/stderr"
        exit 3
      }
    '
}

DEVELOPER_ID_APPLICATION_IDENTITY="${DEVELOPER_ID_APPLICATION_IDENTITY:-${SIGNING_COMMON_NAME:-}}"
if [[ "${SIGNING_MODE}" == "developer-id" && -z "${DEVELOPER_ID_APPLICATION_IDENTITY}" ]]; then
  set +e
  detected_identity="$(auto_detect_developer_id 2>&1)"
  autodetect_status=$?
  set -e
  case "${autodetect_status}" in
    0)
      DEVELOPER_ID_APPLICATION_IDENTITY="${detected_identity}"
      echo "[sign] auto-detected Developer ID identity: ${DEVELOPER_ID_APPLICATION_IDENTITY}"
      ;;
    2)
      echo "error: no 'Developer ID Application' identity found in the keychain." >&2
      echo "       Install your Apple Developer ID Application certificate, or run a" >&2
      echo "       quick unsigned build with: SIGNING_MODE=local ./build-dmg.sh" >&2
      exit 1
      ;;
    3)
      echo "error: multiple 'Developer ID Application' identities found:" >&2
      printf '%s\n' "${detected_identity}" | sed 's/^/       - /' >&2
      echo "       Pick one explicitly:" >&2
      echo "       export DEVELOPER_ID_APPLICATION_IDENTITY='Developer ID Application: Your Name (TEAMID)'" >&2
      exit 1
      ;;
    *)
      echo "error: auto_detect_developer_id exited ${autodetect_status} (unexpected)" >&2
      exit 1
      ;;
  esac
fi
if [[ "${SIGNING_MODE}" == "developer-id" && "${DEVELOPER_ID_APPLICATION_IDENTITY}" != Developer\ ID\ Application:* ]]; then
  echo "error: SIGNING_MODE=developer-id requires a Developer ID Application identity." >&2
  echo "       Got: ${DEVELOPER_ID_APPLICATION_IDENTITY}" >&2
  exit 1
fi

resolve_signing_identity() {
  local cn="$1"
  security find-identity -p codesigning 2>/dev/null \
    | awk -v cn="${cn}" '
      /^[[:space:]]*[0-9]+\)[[:space:]]+[A-F0-9]{40}[[:space:]]+"/ {
        match($0, /[A-F0-9]{40}/)
        h = substr($0, RSTART, RLENGTH)
        split($0, parts, "\"")
        if (parts[2] == cn && !seen[h]++) hashes[++n] = h
      }
      END {
        if (n == 1) { print hashes[1]; exit 0 }
        if (n == 0) { exit 2 }
        for (i = 1; i <= n; i++) print hashes[i] > "/dev/stderr"
        exit 3
      }
    '
}

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

echo "[1/6] Building ${APP_NAME}.app via build.sh (signing mode: ${SIGNING_MODE})"
# Propagate the resolved mode and identity so the .app inside the DMG is
# signed exactly like the DMG. Without this, build.sh would fall back to its
# own default and the app could be self-signed inside a Developer ID DMG.
SIGNING_MODE="${SIGNING_MODE}" \
DEVELOPER_ID_APPLICATION_IDENTITY="${DEVELOPER_ID_APPLICATION_IDENTITY}" \
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

if [[ "${SIGNING_MODE}" == "developer-id" ]]; then
  echo "[sign] Signing DMG with Developer ID"
  DMG_SIGNING_DUPS_FILE="${STAGE_DIR}/dmg-signing-dups"
  set +e
  DMG_SIGNING_HASH="$(resolve_signing_identity "${DEVELOPER_ID_APPLICATION_IDENTITY}" 2>"${DMG_SIGNING_DUPS_FILE}")"
  resolve_status=$?
  set -e

  case "${resolve_status}" in
    0)
      echo "  using identity: ${DMG_SIGNING_HASH} (${DEVELOPER_ID_APPLICATION_IDENTITY})"
      ;;
    2)
      echo "error: Developer ID Application identity not found:" >&2
      echo "       ${DEVELOPER_ID_APPLICATION_IDENTITY}" >&2
      exit 1
      ;;
    3)
      echo "error: multiple identities named '${DEVELOPER_ID_APPLICATION_IDENTITY}':" >&2
      if [[ -s "${DMG_SIGNING_DUPS_FILE}" ]]; then
        sed 's/^/       - /' "${DMG_SIGNING_DUPS_FILE}" >&2
      fi
      exit 1
      ;;
    *)
      echo "error: resolve_signing_identity exited ${resolve_status} (unexpected)" >&2
      exit 1
      ;;
  esac

  codesign --force --sign "${DMG_SIGNING_HASH}" --timestamp "${DMG_OUT}"
  codesign --verify --verbose=2 "${DMG_OUT}"
fi

if [[ "${should_notarize}" == "true" ]]; then
  echo "[notary] Submitting DMG to Apple notarization"
  if ! xcrun notarytool --help >/dev/null 2>&1; then
    echo "error: xcrun notarytool is unavailable. Install current Xcode or Xcode Command Line Tools." >&2
    exit 1
  fi

  xcrun notarytool submit "${DMG_OUT}" \
    --keychain-profile "${NOTARY_PROFILE}" \
    --wait

  echo "[notary] Stapling notarization ticket"
  xcrun stapler staple -v "${DMG_OUT}"
  xcrun stapler validate -v "${DMG_OUT}"

  echo "[notary] Verifying Gatekeeper assessment"
  spctl -a -vv --type open --context context:primary-signature "${DMG_OUT}"
fi

echo ""
echo "DMG ready: ${DMG_OUT}"
echo ""
echo "Install:"
echo "  1. open \"${DMG_OUT}\""
echo "  2. drag ${APP_NAME}.app to the Applications shortcut"
echo "  3. eject the DMG volume"
echo ""
if [[ "${SIGNING_MODE}" == "developer-id" && "${should_notarize}" == "true" ]]; then
  echo "Developer ID notarization is complete; Gatekeeper should accept"
  echo "the DMG and installed app without Open Anyway."
elif [[ "${SIGNING_MODE}" == "developer-id" ]]; then
  echo "Developer ID signing is complete, but notarization was skipped;"
  echo "Gatekeeper may still warn until you build with NOTARIZE=yes."
else
  echo "First launch of the INSTALLED copy (from /Applications) will hit"
  echo "Gatekeeper because the build is locally signed, not notarized:"
  echo "  right-click /Applications/${APP_NAME}.app -> Open,"
  echo "  or System Settings -> Privacy & Security -> 'Open Anyway'."
fi
echo ""
echo "Do NOT launch ${APP_NAME}.app directly from the mounted DMG volume —"
echo "SMAppService and the startup sweep assume a stable install path."
