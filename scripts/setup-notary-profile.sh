#!/usr/bin/env bash
set -euo pipefail

# Store Apple notarization credentials in the login keychain for xcrun
# notarytool. The app-specific password is read silently and is never
# printed or written to project files.

PROFILE="${NOTARY_PROFILE:-WhisperHotNotary}"
APP_PASSWORD=""

cleanup() {
    stty echo 2>/dev/null || true
    unset APP_PASSWORD
}
trap cleanup EXIT INT TERM

if [[ ! -t 0 ]] || [[ ! -t 1 ]]; then
    echo "error: run this script from an interactive terminal (tty required)." >&2
    exit 1
fi

if ! xcrun notarytool --help >/dev/null 2>&1; then
    echo "error: xcrun notarytool is unavailable. Install current Xcode or Xcode Command Line Tools." >&2
    exit 1
fi

echo "This stores a notarytool keychain profile named '${PROFILE}'."
echo "Use an Apple app-specific password, not your normal Apple ID password."
echo ""

read -r -p "Apple ID email: " APPLE_ID
read -r -p "Team ID: " TEAM_ID
printf "App-specific password: "
stty -echo
read -r APP_PASSWORD
stty echo
printf "\n"

if [[ -z "${APPLE_ID}" || -z "${TEAM_ID}" || -z "${APP_PASSWORD}" ]]; then
    echo "error: Apple ID, Team ID, and app-specific password are required." >&2
    exit 1
fi

xcrun notarytool store-credentials "${PROFILE}" \
    --apple-id "${APPLE_ID}" \
    --team-id "${TEAM_ID}" \
    --password "${APP_PASSWORD}"

echo ""
echo "Stored notarytool profile: ${PROFILE}"
echo "Use with: NOTARY_PROFILE='${PROFILE}' SIGNING_MODE=developer-id ./build-dmg.sh"
