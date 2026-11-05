#!/bin/bash
# WoWGrok: one-time setup of a stable self-signed code-signing identity.
#
# Run once on the Mac that builds WoWGrok (as the user the GitHub Actions
# runner runs as):   bash wow-grok/scripts/mac-setup-signing.sh
#
# Why: ad-hoc signed builds get a new code hash each release, so macOS asks
# for Screen Recording again after every update. Signing every build with the
# same certificate keeps the app's designated requirement (identifier +
# certificate) the same, so the permission sticks.
#
# What it does (no sudo, no Python, nothing trusted system-wide):
#   - creates a dedicated keychain ~/Library/Keychains/wowgrok-signing.keychain-db
#     with a random password saved (never printed) in
#     ~/.config/wowgrok/signing-keychain-password (mode 600)
#   - creates a self-signed certificate "WoWGrok Local Signing" (codeSigning
#     extended key usage, ~10 years) with openssl and imports it there
#   - lets /usr/bin/codesign use the key without prompts
#   - adds the keychain to your user search list (keeps existing ones)
# Safe to re-run: if the identity already exists it does nothing.
set -euo pipefail
umask 077

IDENTITY="WoWGrok Local Signing"
KEYCHAIN="$HOME/Library/Keychains/wowgrok-signing.keychain-db"
PW_DIR="$HOME/.config/wowgrok"
PW_FILE="$PW_DIR/signing-keychain-password"
OPENSSL=/usr/bin/openssl
SECURITY=/usr/bin/security

print_identity() {
  local sha1
  sha1=$("$SECURITY" find-certificate -c "$IDENTITY" -Z "$KEYCHAIN" | awk '/SHA-1 hash:/ {print $3; exit}')
  echo "Identity: $IDENTITY"
  echo "SHA-1:    $sha1"
}

add_to_search_list() {
  # Keep every keychain already in the user search list; append ours once.
  local existing=()
  while IFS= read -r line; do
    line="${line#"${line%%[![:space:]]*}"}"; line="${line%\"}"; line="${line#\"}"
    [[ -n "$line" ]] && existing+=("$line")
  done < <("$SECURITY" list-keychains -d user)
  for k in "${existing[@]}"; do
    [[ "$k" == "$KEYCHAIN" ]] && return 0
  done
  "$SECURITY" list-keychains -d user -s "${existing[@]}" "$KEYCHAIN"
}

if [[ -f "$KEYCHAIN" ]] && "$SECURITY" find-certificate -c "$IDENTITY" "$KEYCHAIN" >/dev/null 2>&1; then
  add_to_search_list
  echo "Already set up; nothing to do."
  print_identity
  exit 0
fi

mkdir -p "$PW_DIR"
chmod 700 "$PW_DIR"
if [[ ! -s "$PW_FILE" ]]; then
  "$OPENSSL" rand -hex 32 > "$PW_FILE"
fi
chmod 600 "$PW_FILE"
KC_PW=$(cat "$PW_FILE")

if [[ ! -f "$KEYCHAIN" ]]; then
  "$SECURITY" create-keychain -p "$KC_PW" "$KEYCHAIN"
fi
"$SECURITY" set-keychain-settings "$KEYCHAIN"   # no auto-lock timeout
"$SECURITY" unlock-keychain -p "$KC_PW" "$KEYCHAIN"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cat > "$WORK/cert.cnf" <<CNF
[ req ]
distinguished_name = dn
x509_extensions = ext
prompt = no
[ dn ]
CN = $IDENTITY
[ ext ]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
CNF
"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 -sha256 \
  -config "$WORK/cert.cnf" -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null
P12_PW=$("$OPENSSL" rand -hex 16)
"$OPENSSL" pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -name "$IDENTITY" -out "$WORK/id.p12" -passout "pass:$P12_PW"
"$SECURITY" import "$WORK/id.p12" -k "$KEYCHAIN" -f pkcs12 -P "$P12_PW" -T /usr/bin/codesign >/dev/null
"$SECURITY" set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KC_PW" "$KEYCHAIN" >/dev/null

add_to_search_list
echo "Done."
print_identity
