#!/usr/bin/env bash
# One-time: create a self-signed code signing identity in the login keychain.
# Signing every build with the same certificate keeps the app's designated
# requirement stable, so macOS keeps Microphone / Screen Recording grants
# across rebuilds. Ad-hoc signatures tie grants to the binary hash instead.
set -euo pipefail

IDENTITY="${SIGN_IDENTITY:-Hearsay Local Signing}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning | grep -qF "\"$IDENTITY\""; then
    echo "✓ Signing identity \"$IDENTITY\" already exists"
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $IDENTITY
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

echo "▸ Creating \"$IDENTITY\"…"
# System LibreSSL writes PKCS#12 that `security import` can read (OpenSSL 3 defaults can't).
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -config "$WORK/cert.cnf" -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null
/usr/bin/openssl pkcs12 -export -passout pass:temp \
    -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -out "$WORK/identity.p12"

security import "$WORK/identity.p12" -k "$KEYCHAIN" -P temp -T /usr/bin/codesign >/dev/null

echo "✓ Created \"$IDENTITY\" in the login keychain"
