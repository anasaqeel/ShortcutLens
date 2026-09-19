#!/bin/bash
# Creates a self-signed code-signing identity in the login keychain, so
# CheatSheet keeps a stable code identity across rebuilds.
#
# Why this matters: with ad-hoc signing (`codesign --sign -`) macOS derives
# the app's identity from a hash of the binary. Every rebuild therefore looks
# like a completely different app, and the Accessibility permission you
# granted to the previous build no longer applies — you have to re-grant it
# after every single build. Signing with a stable certificate fixes that.
#
# The private key never leaves this Mac and is not usable for distributing
# software to anyone else; it only makes the local identity stable.
set -euo pipefail

IDENTITY_NAME="CheatSheet Local Signing"
KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -q "${IDENTITY_NAME}"; then
    echo "==> Identity '${IDENTITY_NAME}' already exists — nothing to do."
    exit 0
fi

WORK_DIR="$(mktemp -d)"
# The private key is written to disk only briefly while it is imported.
trap 'rm -rf "${WORK_DIR}"' EXIT

echo "==> Generating a self-signed code-signing certificate"
cat > "${WORK_DIR}/openssl.cnf" <<'EOF'
[ req ]
distinguished_name = dn
prompt             = no
x509_extensions    = codesign

[ dn ]
CN = CheatSheet Local Signing

[ codesign ]
basicConstraints     = critical,CA:false
keyUsage             = critical,digitalSignature
extendedKeyUsage     = critical,codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -config "${WORK_DIR}/openssl.cnf" \
    -keyout "${WORK_DIR}/key.pem" \
    -out "${WORK_DIR}/cert.pem" 2>/dev/null

# A throwaway password for the transfer file only: `security import` and an
# empty-password PKCS#12 written by LibreSSL disagree on the MAC, so the
# import fails outright without one. It is discarded with WORK_DIR below.
TRANSFER_PASSWORD="$(openssl rand -hex 16)"

openssl pkcs12 -export \
    -inkey "${WORK_DIR}/key.pem" \
    -in "${WORK_DIR}/cert.pem" \
    -out "${WORK_DIR}/identity.p12" \
    -passout "pass:${TRANSFER_PASSWORD}" 2>/dev/null

echo "==> Importing into the login keychain"
# -T grants only codesign access to the key, rather than every application.
security import "${WORK_DIR}/identity.p12" \
    -k "${KEYCHAIN}" \
    -P "${TRANSFER_PASSWORD}" \
    -T /usr/bin/codesign

echo "==> Trusting the certificate for code signing"
echo "    (macOS will ask for your login password)"
security add-trusted-cert \
    -p codeSign \
    -k "${KEYCHAIN}" \
    "${WORK_DIR}/cert.pem"

echo
echo "==> Done. Verifying:"
security find-identity -v -p codesigning | grep "${IDENTITY_NAME}" || {
    echo "    Identity was not found — check the output above." >&2
    exit 1
}

echo
echo "    Rebuild with ./Scripts/build_app.sh --install to sign with it."
echo "    You will need to grant Accessibility access once more after that"
echo "    (the identity changes this one last time), and then it will stick."
