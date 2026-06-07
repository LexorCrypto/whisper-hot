#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="WhisperHot"
BUILD_CONFIG="${BUILD_CONFIG:-release}"
SIGNING_MODE="${SIGNING_MODE:-local}"

case "${SIGNING_MODE}" in
    local|developer-id)
        ;;
    *)
        echo "error: SIGNING_MODE must be 'local' or 'developer-id' (got '${SIGNING_MODE}')" >&2
        exit 1
        ;;
esac

if [[ "${SIGNING_MODE}" == "developer-id" ]]; then
    SIGNING_COMMON_NAME="${DEVELOPER_ID_APPLICATION_IDENTITY:-${SIGNING_COMMON_NAME:-}}"
    ENTITLEMENTS_FILE="${ENTITLEMENTS_FILE:-Resources/WhisperHot.entitlements}"

    if [[ -z "${SIGNING_COMMON_NAME}" ]]; then
        echo "error: DEVELOPER_ID_APPLICATION_IDENTITY is required for SIGNING_MODE=developer-id." >&2
        echo "       Example:" >&2
        echo "       export DEVELOPER_ID_APPLICATION_IDENTITY='Developer ID Application: Your Name (TEAMID)'" >&2
        exit 1
    fi
    if [[ "${SIGNING_COMMON_NAME}" != Developer\ ID\ Application:* ]]; then
        echo "error: SIGNING_MODE=developer-id requires a Developer ID Application identity." >&2
        echo "       Got: ${SIGNING_COMMON_NAME}" >&2
        exit 1
    fi
    if [[ ! -f "${ENTITLEMENTS_FILE}" ]]; then
        echo "error: entitlements file not found: ${ENTITLEMENTS_FILE}" >&2
        exit 1
    fi
else
    SIGNING_COMMON_NAME="${SIGNING_COMMON_NAME:-whisper-hot-local}"
fi

# Script-owned tempdir, cleaned on any exit path. Used to capture
# stderr from resolve_signing_identity so we are not subject to races
# or symlink attacks on a shared /tmp path. Created via mktemp so two
# concurrent builds (or a hostile pre-existing /tmp/whisper-hot-build)
# cannot collide.
BUILD_TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/whisper-hot-build.XXXXXX")"
trap 'rm -rf "${BUILD_TMP_DIR}"' EXIT

# Resolve the requested codesigning identity by SHA-1. We sign by hash
# rather than by common name so a stray duplicate in the keychain can
# never silently pick the wrong cert. If the identity is missing we bail
# instead of falling back to ad-hoc signing — ad-hoc is the exact bug
# we're here to avoid, and a silent downgrade would mask it.
#
# Note: we use `find-identity` WITHOUT `-v`. A self-signed leaf with no
# user-installed trust is filtered out by `-v` (it returns
# CSSMERR_TP_NOT_TRUSTED), but `codesign --sign` works on it just
# fine — trust is only needed for verification against Gatekeeper,
# which we do not gate on for a personal ad-hoc build. So we accept
# the presence listing and let the signing step be the real arbiter.
resolve_signing_identity() {
    security find-identity -p codesigning 2>/dev/null \
        | awk -v cn="${SIGNING_COMMON_NAME}" '
            /^[[:space:]]*[0-9]+\)[[:space:]]+[A-F0-9]{40}[[:space:]]+"/ {
                match($0, /[A-F0-9]{40}/)
                h = substr($0, RSTART, RLENGTH)
                split($0, parts, "\"")
                if (parts[2] == cn && !seen[h]++) hashes[++n] = h
            }
            END {
                if (n == 1) { print hashes[1]; exit 0 }
                if (n == 0) { exit 2 }
                # Multiple matches: emit them all on stderr for the
                # caller to surface, and exit non-zero.
                for (i = 1; i <= n; i++) print hashes[i] > "/dev/stderr"
                exit 3
            }
        '
}

# The project lives in ~/Documents which is synchronised by iCloud Drive.
# The iCloud File Provider continuously re-adds `com.apple.FinderInfo` and
# `com.apple.fileprovider.fpfs#P` extended attributes to files inside that
# tree — fast enough to re-appear between `xattr -cr` and `codesign`. That
# makes codesign refuse with "resource fork, Finder information, or similar
# detritus not allowed".
#
# Assemble and sign the .app outside of the iCloud-synced tree instead.
BUILD_OUT_DIR="${BUILD_OUT_DIR:-${HOME}/Library/Caches/WhisperHot-build}"
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

# Copy app icon into the bundle if it exists.
if [ -f "Resources/WhisperHot.icns" ]; then
    ditto --noextattr Resources/WhisperHot.icns "${APP_BUNDLE}/Contents/Resources/WhisperHot.icns"
    echo "  copied app icon to bundle"
fi

# Copy custom sounds into the app bundle if they exist.
if [ -d "Resources/Sounds" ]; then
    mkdir -p "${APP_BUNDLE}/Contents/Resources/Sounds"
    ditto --noextattr Resources/Sounds/ "${APP_BUNDLE}/Contents/Resources/Sounds/"
    echo "  copied custom sounds to bundle"
fi

echo "[4/5] Signing with stable identity"
# Final defensive sweep in case anything slipped through.
xattr -cr "${APP_BUNDLE}"

SIGNING_HASH=""
SIGNING_DUPS_FILE="${BUILD_TMP_DIR}/signing-dups"
set +e
SIGNING_HASH="$(resolve_signing_identity 2>"${SIGNING_DUPS_FILE}")"
resolve_status=$?
set -e

case "${resolve_status}" in
    0)
        echo "  using identity: ${SIGNING_HASH} (${SIGNING_COMMON_NAME})"
        ;;
    2)
        echo "error: codesigning identity '${SIGNING_COMMON_NAME}' not found." >&2
        if [[ "${SIGNING_MODE}" == "developer-id" ]]; then
            echo "       Install your Apple Developer ID Application certificate in Keychain Access." >&2
        else
            echo "       Run: ./scripts/create-signing-identity.sh" >&2
            echo "       (one-time setup; see the script header for details)" >&2
        fi
        exit 1
        ;;
    3)
        echo "error: multiple valid identities named '${SIGNING_COMMON_NAME}':" >&2
        # `sed` on our own tempdir file; the EXIT trap owns cleanup.
        # Guard against an empty file so `set -e` + an empty sed
        # pipeline do not muddle the error path.
        if [[ -s "${SIGNING_DUPS_FILE}" ]]; then
            sed 's/^/       - /' "${SIGNING_DUPS_FILE}" >&2
        fi
        echo "       Open Keychain Access, delete duplicates, then retry." >&2
        exit 1
        ;;
    *)
        echo "error: resolve_signing_identity exited ${resolve_status} (unexpected)" >&2
        exit 1
        ;;
esac

if [[ "${SIGNING_MODE}" == "developer-id" ]]; then
    echo "  mode: Developer ID + Hardened Runtime"
    codesign --force \
        --deep \
        --options runtime \
        --timestamp \
        --entitlements "${ENTITLEMENTS_FILE}" \
        --sign "${SIGNING_HASH}" \
        "${APP_BUNDLE}"
    codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"
else
    echo "  mode: local self-signed"
    codesign --force --deep --sign "${SIGNING_HASH}" --timestamp=none "${APP_BUNDLE}"
fi

echo "[5/5] Done"
echo "Launch with: open \"${APP_BUNDLE}\""
