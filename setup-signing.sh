#!/bin/bash
# Creates (if needed) and trusts a local, self-signed code-signing certificate
# named ClaudeUsageLocalSign in your login keychain.
#
# Why this exists: build.sh signs ClaudeUsage.app with this identity instead of
# ad-hoc ("-") signing. Ad-hoc signatures are derived from the binary's own hash,
# so every rebuild looks like a "different app" to the Keychain and macOS
# re-prompts for your password every time. A stable certificate-based identity
# fixes that -- but only if the certificate is also *trusted*; an untrusted
# self-signed cert still gets silently re-validated (and re-prompts you) after
# things like sleep/wake or a keychain idle-timeout. This script does both
# steps: create the identity, and trust it for code signing.
#
# Everything here is scoped to your own login keychain -- no sudo, no
# system-wide trust changes.
set -euo pipefail

IDENTITY_NAME="ClaudeUsageLocalSign"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "${IDENTITY_NAME}" "${KEYCHAIN}" >/dev/null 2>&1; then
    echo "Certificate '${IDENTITY_NAME}' already exists in your login keychain."
else
    echo "==> Generating a local self-signed code-signing certificate"
    TMP=$(mktemp -d)
    trap 'rm -rf "${TMP}"' EXIT

    openssl req -x509 -newkey rsa:2048 -keyout "${TMP}/key.pem" -out "${TMP}/cert.pem" -days 3650 -nodes \
        -subj "/CN=${IDENTITY_NAME}" \
        -addext "keyUsage=digitalSignature" \
        -addext "extendedKeyUsage=codeSigning" >/dev/null 2>&1

    # -legacy is needed on OpenSSL 3.x so the PKCS#12 file uses an encryption
    # scheme macOS's Security framework can actually import; older OpenSSL
    # builds don't understand -legacy, so fall back if it's not supported.
    openssl pkcs12 -export -out "${TMP}/cert.p12" -inkey "${TMP}/key.pem" -in "${TMP}/cert.pem" \
        -passout pass:tempimportpass -legacy >/dev/null 2>&1 || \
    openssl pkcs12 -export -out "${TMP}/cert.p12" -inkey "${TMP}/key.pem" -in "${TMP}/cert.pem" \
        -passout pass:tempimportpass >/dev/null 2>&1

    echo "==> Importing it into your login keychain"
    security import "${TMP}/cert.p12" -k "${KEYCHAIN}" -P tempimportpass -T /usr/bin/codesign -A

    echo "==> Trusting it for code signing (this is what makes 'Always Allow' stick)"
    security add-trusted-cert -p codeSign -k "${KEYCHAIN}" "${TMP}/cert.pem"

    echo "Done. '${IDENTITY_NAME}' is ready."
fi

echo "Run ./build.sh (or re-run it) to build and sign with this identity."
