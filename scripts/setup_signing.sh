#!/usr/bin/env bash
# Writes android/key.properties for release signing — asks for the keystore
# password (hidden), checks it against the keystore, and only then saves it.
# Usage: bash scripts/setup_signing.sh [path/to/upload.jks]
set -euo pipefail
cd "$(dirname "$0")/.."

store="${1:-$HOME/keys/synk-upload.jks}"
alias_name=upload
[[ -f "$store" ]] || { echo "✗ No keystore at $store — create it first (docs/RELEASING.md, step 1)"; exit 1; }

read -r -s -p "Keystore password for $store: " pass; echo
if ! keytool -list -keystore "$store" -storepass "$pass" -alias "$alias_name" >/dev/null 2>&1; then
  echo "✗ That password doesn't open $store (or it has no '$alias_name' key). Nothing was written."
  echo "  Forgot it? Delete the .jks and create it again (docs/RELEASING.md, step 1) — it hasn't been used on Play yet."
  exit 1
fi

umask 077  # readable by you only
printf 'storePassword=%s\nkeyPassword=%s\nkeyAlias=%s\nstoreFile=%s\n' "$pass" "$pass" "$alias_name" "$store" > android/key.properties
echo "✓ android/key.properties written (git-ignored). Now run: bash scripts/build_release.sh"
