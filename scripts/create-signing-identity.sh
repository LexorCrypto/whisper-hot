#!/usr/bin/env bash
set -euo pipefail

# Create a stable self-signed codesigning identity in the user's login
# keychain. Used by build.sh instead of ad-hoc signing so rebuilds keep
# the same designated requirement and Keychain ACLs stop prompting for
# the login password on every new binary.
#
# Idempotent: if an identity with the expected CN already exists AND
# passes a real end-to-end signing probe, the script prints the SHA-1
# and exits 0. If multiple valid identities share the CN, or an
# existing one fails the probe, the script fails loudly and points
# the user at Keychain Access.
#
# Why interactive: we ask for the macOS login password once so we can
# (a) unlock the login keychain, (b) import the new PKCS#12, and
# (c) call `security set-key-partition-list`, which is what actually
# authorises codesign to use the private key without prompting on
# every build.

COMMON_NAME="whisper-hot-local"

# Unified cleanup: restore terminal echo AND wipe the staging dir.
# Installed before any stty tweak or mktemp so a Ctrl-C during the
# password prompt cannot leave the terminal silent or the private key
# on disk.
STAGE_DIR=""
cleanup() {
    stty echo 2>/dev/null || true
    if [[ -n "${STAGE_DIR}" && -d "${STAGE_DIR}" ]]; then
        rm -rf "${STAGE_DIR}"
    fi
}
trap cleanup EXIT INT TERM

# Resolve the user's login keychain dynamically. `security login-keychain`
# prints something like:
#     "/Users/foo/Library/Keychains/login.keychain-db"
# Strip the leading whitespace and the wrapping quotes, but do NOT
# strip inner whitespace — a home directory with spaces is valid.
KEYCHAIN="$(
    security login-keychain 2>/dev/null \
        | awk -F'"' 'NF >= 3 { print $2; exit }'
)"
if [[ -z "${KEYCHAIN}" || ! -e "${KEYCHAIN}" ]]; then
    echo "error: could not resolve login keychain (got '${KEYCHAIN}')" >&2
    exit 1
fi

# Collect ALL SHA-1 hashes from codesigning identities whose CN
# matches. We deliberately do NOT pass `-v` here — self-signed leaves
# without installed trust are omitted by `-v` but codesign can still
# sign with them, so the presence listing (the Matching-identities
# block) is what we actually care about for idempotency / cleanup.
# `find-identity` without `-v` emits a `Matching identities` header
# followed by numbered lines; we filter to the numbered lines only.
find_all_hashes_for_cn() {
    security find-identity -p codesigning "${KEYCHAIN}" 2>/dev/null \
        | awk -v cn="${COMMON_NAME}" '
            /^[[:space:]]*[0-9]+\)[[:space:]]+[A-F0-9]{40}[[:space:]]+"/ {
                match($0, /[A-F0-9]{40}/)
                h = substr($0, RSTART, RLENGTH)
                split($0, parts, "\"")
                if (parts[2] == cn) print h
            }
        '
}

# SHA-1 fingerprint of a PEM cert, normalised to uppercase hex with no
# separators. `security find-identity` uses exactly this value as the
# identity hash, so computing it from the cert we just generated lets
# us skip a second parse of find-identity output after install.
fingerprint_from_crt() {
    openssl x509 -in "$1" -noout -fingerprint -sha1 \
        | awk -F= '{print $2}' \
        | tr -d ':' \
        | tr '[:lower:]' '[:upper:]'
}

# Real end-to-end signing probe. Compiles a tiny Mach-O, signs it with
# the given identity hash, and verifies the signature. Any failure —
# missing cc, failed compile, failed sign, failed verify — returns
# non-zero. Caller decides whether that's fatal.
#
# Scoped to its own tempdir so the global STAGE_DIR (only set in the
# install path) stays independent and we can probe before we ever
# commit to creating a new identity.
probe_identity() {
    local hash="$1"
    local probe_dir

    if ! command -v cc >/dev/null 2>&1; then
        echo "error: cc not found; install Xcode Command Line Tools:" >&2
        echo "       xcode-select --install" >&2
        return 1
    fi

    probe_dir="$(mktemp -d "${TMPDIR:-/tmp}/whisper-hot-probe.XXXXXX")"

    local ret=0
    printf 'int main(void){return 0;}\n' >"${probe_dir}/stub.c"
    if ! cc -o "${probe_dir}/stub" "${probe_dir}/stub.c" 2>"${probe_dir}/cc.log"; then
        echo "error: cc failed to compile the probe stub. Log:" >&2
        cat "${probe_dir}/cc.log" >&2
        ret=1
    elif ! codesign --force \
                    --sign "${hash}" \
                    --timestamp=none \
                    "${probe_dir}/stub" 2>"${probe_dir}/codesign.log"; then
        echo "error: codesign probe failed. Log:" >&2
        cat "${probe_dir}/codesign.log" >&2
        ret=1
    elif ! codesign --verify --verbose=0 "${probe_dir}/stub" 2>"${probe_dir}/verify.log"; then
        echo "error: signed stub failed codesign --verify. Log:" >&2
        cat "${probe_dir}/verify.log" >&2
        ret=1
    fi

    rm -rf "${probe_dir}"
    return $ret
}

# Collect existing matches into a bash array. mapfile is bash 4 only;
# macOS ships bash 3.2, so read the lines in a loop instead.
existing_hashes=()
while IFS= read -r h; do
    [[ -n "${h}" ]] && existing_hashes+=("${h}")
done < <(find_all_hashes_for_cn)

if [[ "${#existing_hashes[@]}" -gt 1 ]]; then
    echo "error: multiple valid codesigning identities named '${COMMON_NAME}' exist:" >&2
    for h in "${existing_hashes[@]}"; do
        echo "       - ${h}" >&2
    done
    echo "" >&2
    echo "       Open Keychain Access, filter to 'My Certificates', and delete" >&2
    echo "       the unwanted one(s) before re-running this script." >&2
    exit 1
fi

if [[ "${#existing_hashes[@]}" -eq 1 ]]; then
    existing="${existing_hashes[0]}"
    echo "Found existing identity: ${existing} (${COMMON_NAME})"
    echo "Verifying it is usable via signing probe..."
    if probe_identity "${existing}"; then
        echo ""
        echo "Probe passed. Identity is healthy; nothing to do."
        echo "build.sh will pick up this identity automatically on the next build."
        exit 0
    fi
    echo "" >&2
    echo "error: existing identity failed the signing probe." >&2
    echo "       It is likely missing partition-list registration or user-level" >&2
    echo "       trust. Open Keychain Access, find '${COMMON_NAME}' under 'My" >&2
    echo "       Certificates', delete it, then re-run this script for a clean" >&2
    echo "       install." >&2
    exit 1
fi

# ----- No existing identity: install a fresh one -----

command -v openssl >/dev/null 2>&1 || {
    echo "error: openssl not found in PATH" >&2
    exit 1
}

if [[ ! -t 0 ]] || [[ ! -t 1 ]]; then
    echo "error: run this script from an interactive terminal (tty required)." >&2
    echo "       (you need to type your macOS login password once)" >&2
    exit 1
fi

echo "Creating self-signed codesigning identity '${COMMON_NAME}' in:"
echo "  ${KEYCHAIN}"
echo ""
echo "You'll be asked for your macOS login password once. It is used"
echo "locally to unlock the login keychain and register codesign with"
echo "the new private key. It is never written to disk."
echo ""
printf "Login password: "
stty -echo
read -r KEYCHAIN_PASSWORD
stty echo
printf "\n\n"

if [[ -z "${KEYCHAIN_PASSWORD}" ]]; then
    echo "error: empty password — aborting" >&2
    exit 1
fi

if ! security unlock-keychain -p "${KEYCHAIN_PASSWORD}" "${KEYCHAIN}" 2>/dev/null; then
    echo "error: login keychain did not unlock — wrong password?" >&2
    unset KEYCHAIN_PASSWORD
    exit 1
fi

STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/whisper-hot-sign.XXXXXX")"

CONF="${STAGE_DIR}/cert.conf"
KEY="${STAGE_DIR}/cert.key"
CRT="${STAGE_DIR}/cert.crt"
P12="${STAGE_DIR}/cert.p12"

cat >"${CONF}" <<CONF_EOF
[ req ]
distinguished_name = req_dn
prompt             = no
x509_extensions    = v3_codesign

[ req_dn ]
CN = ${COMMON_NAME}

[ v3_codesign ]
basicConstraints       = critical,CA:FALSE
keyUsage               = critical,digitalSignature
extendedKeyUsage       = critical,codeSigning
subjectKeyIdentifier   = hash
CONF_EOF

echo "[1/7] Generating RSA 2048 key + self-signed cert (10y)"
openssl req -x509 \
    -newkey rsa:2048 \
    -keyout "${KEY}" \
    -out "${CRT}" \
    -days 3650 \
    -nodes \
    -config "${CONF}" >/dev/null 2>&1

expected_hash="$(fingerprint_from_crt "${CRT}")"
if [[ -z "${expected_hash}" ]]; then
    echo "error: could not compute cert fingerprint" >&2
    exit 1
fi

echo "[2/7] Packaging into PKCS#12 (legacy PBE for macOS security(1))"
# Two independent incompatibilities between OpenSSL 3.x and Apple's
# `security import` on macOS 13+ conspire here:
#
#   1. OpenSSL 3.x keeps PBE-SHA1-3DES, RC2-40, MD5, etc. in a legacy
#      provider that is NOT loaded by default. Without `-legacy`,
#      `-keypbe`/`-certpbe PBE-SHA1-3DES` flags are silently ignored
#      and the output gets AES-256-CBC + SHA-256 instead — which the
#      Apple tool cannot read.
#
#   2. Apple's `security` rejects PKCS#12 bundles protected with an
#      empty passphrase, even when the format is otherwise correct,
#      failing with "MAC verification failed during PKCS12 import
#      (wrong password?)". A non-empty transport passphrase works.
#
# We pick a random transport passphrase, hand it to both `openssl`
# and `security`, and let it evaporate with the tempdir (STAGE_DIR is
# cleaned by the EXIT trap). The passphrase never protects anything
# at rest — it only carries the key across the openssl → security
# hand-off.
PKCS12_LEGACY=()
if openssl pkcs12 -help 2>&1 | grep -q -- '-legacy'; then
    PKCS12_LEGACY=(-legacy)
fi
P12_PASS="$(openssl rand -hex 16)"
openssl pkcs12 -export \
    "${PKCS12_LEGACY[@]}" \
    -out "${P12}" \
    -inkey "${KEY}" \
    -in "${CRT}" \
    -name "${COMMON_NAME}" \
    -passout "pass:${P12_PASS}" \
    -keypbe PBE-SHA1-3DES \
    -certpbe PBE-SHA1-3DES \
    -macalg sha1 >/dev/null 2>&1

echo "[3/7] Importing into login keychain"
# -P must match the passphrase baked into the PKCS#12 in step 2.
# Passing "" here while openssl used a non-empty -passout is exactly
# the bug we hit the first time round.
security import "${P12}" \
    -k "${KEYCHAIN}" \
    -P "${P12_PASS}" \
    -T /usr/bin/codesign >/dev/null

# The transport passphrase has done its job — the private key is now
# inside the keychain, protected by the user's login keychain ACL
# rather than by this one-shot string. Zero it from the environment.
unset P12_PASS

echo "[4/7] Registering codesign in the key partition list"
security set-key-partition-list \
    -S "apple-tool:,apple:,codesign:" \
    -s \
    -k "${KEYCHAIN_PASSWORD}" \
    "${KEYCHAIN}" >/dev/null

echo "[5/7] Trusting cert as a user-level codesigning root"
# codesign(1) builds a chain to a trusted anchor while signing. For a
# self-signed leaf, `find-identity -v` will typically not list the
# identity as "valid" until some form of user-level trust is written,
# and depending on macOS version codesign may also refuse to sign.
#
# We show add-trusted-cert's stderr (no 2>&1 suppression) so any real
# authorisation failure is visible. If it still fails, the probe in
# step 7 is the authoritative backstop.
trust_installed=1
trust_err="${STAGE_DIR}/add-trusted-cert.log"
if ! security add-trusted-cert \
        -r trustAsRoot \
        -p codeSign \
        -k "${KEYCHAIN}" \
        "${CRT}" 2>"${trust_err}"; then
    trust_installed=0
    echo "  add-trusted-cert returned non-zero. Output:"
    sed 's/^/    /' "${trust_err}" >&2 || true
    echo "  The probe in step 7 will decide whether signing still works."
fi

unset KEYCHAIN_PASSWORD

echo "[6/7] Verifying the cert is present in the keychain"
# Presence check ONLY — we deliberately do NOT use `find-identity -v`
# here because `-v` filters to identities considered "valid for code
# signing", which on macOS usually requires either a full Apple-issued
# chain or user-installed trust. For a freshly-imported self-signed
# leaf, `-v` can return empty even when codesign is perfectly happy
# to sign with it (verified by the probe in step 7). We look it up by
# SHA-1 via the presence-only listing instead.
if ! security find-identity -p codesigning "${KEYCHAIN}" 2>/dev/null \
        | awk '/^[[:space:]]*[0-9]+\)[[:space:]]+[A-F0-9]{40}/' \
        | grep -q "${expected_hash}"; then
    echo "error: expected identity ${expected_hash} not present in the keychain." >&2
    echo "       Check Keychain Access for '${COMMON_NAME}'." >&2
    exit 1
fi

echo "[7/7] Running signing probe (authoritative)"
if ! probe_identity "${expected_hash}"; then
    echo "" >&2
    if [[ "${trust_installed}" -eq 0 ]]; then
        echo "Trust was not installed in step 5 and the probe failed." >&2
        echo "Open Keychain Access, find '${COMMON_NAME}' under 'My Certificates'," >&2
        echo "and set 'When using this certificate → Always Trust', then re-run" >&2
        echo "this script." >&2
    else
        echo "Trust installed but probe still failed. Check the codesign log above" >&2
        echo "and Keychain Access for '${COMMON_NAME}'." >&2
    fi
    exit 1
fi

echo ""
echo "Installed identity: ${expected_hash} (${COMMON_NAME})"
echo "Probe passed: codesign --sign + --verify on a stub binary OK."
echo "build.sh will pick up this identity automatically on the next build."
