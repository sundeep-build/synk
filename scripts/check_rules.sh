#!/usr/bin/env bash
# Compiles firebase/*.rules against the running emulators and fails on any error.
# Usage: firebase emulators:exec --project demo-synk --only firestore,database "bash scripts/check_rules.sh"
set -euo pipefail
cd "$(dirname "$0")/.."
FIRESTORE_RULES="${FIRESTORE_RULES:-firebase/firestore.rules}"
DATABASE_RULES="${DATABASE_RULES:-firebase/database.rules.json}"

rtdb=$(curl -s -X PUT "http://127.0.0.1:9000/.settings/rules.json?ns=demo-synk-default-rtdb" \
  -H "Authorization: Bearer owner" --data-binary @"$DATABASE_RULES")
if [[ "$rtdb" != *'"status":"ok"'* ]]; then
  echo "✗ Realtime Database rules: $rtdb"; exit 1
fi
echo "✓ Realtime Database rules compile"

python3 - "$FIRESTORE_RULES" <<'PY'
import json, sys, urllib.request, urllib.error
rules = open(sys.argv[1]).read()
body = json.dumps({"rules": {"files": [{"name": "firestore.rules", "content": rules}]}}).encode()
req = urllib.request.Request(
    "http://127.0.0.1:8080/emulator/v1/projects/demo-synk:securityRules",
    data=body, method="PUT", headers={"Content-Type": "application/json"})
try:
    urllib.request.urlopen(req).read()
except urllib.error.HTTPError as e:
    print("✗ Firestore rules:", e.read().decode()); sys.exit(1)
print("✓ Firestore rules compile")
PY
