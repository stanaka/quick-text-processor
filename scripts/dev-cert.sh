#!/bin/sh
# Create a self-signed "QuickTextProcessor Dev" code-signing certificate in
# the login keychain, so `make app` can sign with a stable identity and macOS
# keeps the Accessibility (TCC) grant across rebuilds.
#
# Idempotent: exits 0 without changes if the identity already exists.
# One-time GUI prompts to expect:
#   1. an authorization dialog when the cert is marked trusted for code signing,
#   2. on the first `make app`, a keychain dialog "codesign wants to sign using
#      key ..." -> click "Always Allow".
set -eu

CERT_NAME="QuickTextProcessor Dev"
# System LibreSSL: its .p12 output is always importable by `security import`
# (Homebrew OpenSSL 3 defaults to PBES2/AES, which import has choked on).
OPENSSL=/usr/bin/openssl
DAYS=3650

if [ "$(uname -s)" != "Darwin" ]; then
    echo "dev-cert.sh: this script only works on macOS." >&2
    exit 1
fi

if security find-identity -v -p codesigning 2>/dev/null | grep -Fq "\"$CERT_NAME\""; then
    echo "Identity \"$CERT_NAME\" already exists and is valid for code signing. Nothing to do."
    exit 0
fi

KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
if [ ! -f "$KEYCHAIN" ]; then
    # Pre-Sierra keychain layout.
    KEYCHAIN="$HOME/Library/Keychains/login.keychain"
fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/qtp-dev-cert.XXXXXX")
trap 'rm -rf "$WORK"' EXIT INT TERM

# 1. Self-signed cert with the extensions codesign requires.
cat > "$WORK/openssl.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions    = codesign_ext
prompt             = no
[dn]
CN = $CERT_NAME
[codesign_ext]
keyUsage         = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:FALSE
EOF
"$OPENSSL" req -x509 -newkey rsa:2048 -sha256 -days "$DAYS" -nodes \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -config "$WORK/openssl.cnf" \
    >/dev/null 2>&1

# 2. Bundle key+cert into a throwaway-passphrase .p12 and import it,
#    pre-authorizing /usr/bin/codesign to use the private key.
P12PASS=$("$OPENSSL" rand -hex 16)
"$OPENSSL" pkcs12 -export -name "$CERT_NAME" \
    -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -out "$WORK/dev.p12" -passout "pass:$P12PASS"
security import "$WORK/dev.p12" -k "$KEYCHAIN" -f pkcs12 -P "$P12PASS" \
    -T /usr/bin/codesign

# 3. Trust the cert for code signing (user trust domain, no sudo). Required:
#    an untrusted self-signed cert is not a valid code-signing identity.
echo "Marking \"$CERT_NAME\" as trusted for code signing (macOS will ask you to authorize this once)..."
if ! security add-trusted-cert -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"; then
    cat >&2 <<'EOM'
warning: could not set trust settings automatically.
Fallback: open Keychain Access, find "QuickTextProcessor Dev" in the login
keychain, Get Info -> Trust -> Code Signing: Always Trust, then re-run
`make cert` to verify.
EOM
    exit 1
fi

# 4. Verify the identity is now usable.
if security find-identity -v -p codesigning | grep -Fq "\"$CERT_NAME\""; then
    echo "Done. 'make app' / 'make run' will now sign with \"$CERT_NAME\" automatically."
    echo "Grant Accessibility once more after the next build; the grant then persists."
else
    echo "error: identity was imported but is not valid for code signing." >&2
    echo "See the Accessibility section of the README for the Keychain Access fallback." >&2
    exit 1
fi
