#!/usr/bin/env bash
# scripts/generate-signing-cert.sh
#
# Generates a persistent self-signed codesigning certificate for ClickToMin
# releases. Run ONCE on a trusted machine. The output .p12 (base64) goes
# into GitHub secrets for CI signing.
#
# Usage:
#   ./scripts/generate-signing-cert.sh
#
# Outputs:
#   - clicktomin-release.p12 in the current directory
#   - Base64 of the .p12 printed to stdout for pasting into GitHub secrets
#
# Requires: openssl

set -euo pipefail

CERT_CN="ClickToMin Release Signing"
CERT_VALIDITY_DAYS=7300  # ~20 years
P12_FILE="clicktomin-release.p12"
KEY_FILE="$(mktemp)"
CERT_FILE="$(mktemp)"

trap 'rm -f "$KEY_FILE" "$CERT_FILE"' EXIT

if [[ -f "$P12_FILE" ]]; then
    echo "ERROR: $P12_FILE already exists. Remove it to regenerate." >&2
    exit 1
fi

echo "Generating 2048-bit RSA key + self-signed cert (CN=$CERT_CN)..."
openssl req -new -x509 \
    -newkey rsa:2048 \
    -sha256 \
    -days "$CERT_VALIDITY_DAYS" \
    -nodes \
    -keyout "$KEY_FILE" \
    -out "$CERT_FILE" \
    -subj "/CN=$CERT_CN" \
    -addext "keyUsage=digitalSignature" \
    -addext "extendedKeyUsage=codeSigning" \
    2>/dev/null

echo ""
echo "Enter an export passphrase for the .p12 file."
echo "You will need this passphrase for the MACOS_SIGNING_P12_PASSWORD GitHub secret."
echo ""

openssl pkcs12 -export \
    -inkey "$KEY_FILE" \
    -in "$CERT_FILE" \
    -out "$P12_FILE" \
    -name "$CERT_CN" \
    -legacy

echo ""
echo "Created: $P12_FILE"
echo ""
echo "=== NEXT STEPS ==="
echo ""
echo "1. Add these GitHub secrets to ChrisNourse/click-to-min:"
echo ""
echo "   MACOS_SIGNING_P12_BASE64:"
echo "   (copy the base64 blob below)"
echo ""
base64 < "$P12_FILE"
echo ""
echo ""
echo "   MACOS_SIGNING_P12_PASSWORD:"
echo "   (the passphrase you just entered)"
echo ""
echo "2. Keep an encrypted backup of $P12_FILE in a secure location."
echo "   If this file is lost, existing users will need to re-grant"
echo "   Accessibility permission after the next update."
echo ""
echo "3. Delete $P12_FILE from this machine after adding the secret"
echo "   (the private key should not persist unencrypted on disk)."
echo ""
