#!/usr/bin/env bash
# Builds a signed Android App Bundle for Play Console.
# Usage: bash scripts/build_release.sh            (version from pubspec.yaml)
# Needs: android/key.properties (upload key) and env/prod.json — see docs/RELEASING.md.
set -euo pipefail
cd "$(dirname "$0")/.."

[[ -f android/key.properties ]] || { echo "✗ android/key.properties missing (upload key) — see docs/RELEASING.md"; exit 1; }
[[ -f env/prod.json ]] || { echo "✗ env/prod.json missing — copy env/prod.example.json and fill it in"; exit 1; }

# Fail fast (not after a 1-minute build) if the signing password is wrong.
prop() { sed -n "s/^$1=//p" android/key.properties | head -1; }
if ! keytool -list -keystore "$(prop storeFile)" -storepass "$(prop storePassword)" -alias "$(prop keyAlias)" >/dev/null 2>&1; then
  echo "✗ android/key.properties can't open the keystore (wrong password, path or alias)."
  echo "  Fix it with: bash scripts/setup_signing.sh"
  exit 1
fi

version=$(grep -E '^version:' pubspec.yaml | awk '{print $2}')
echo "→ Building Synk $version (versionName+versionCode) for Play…"

flutter clean >/dev/null
flutter pub get >/dev/null
flutter test --reporter failures-only
flutter build appbundle --release \
  --dart-define-from-file=env/prod.json \
  --obfuscate --split-debug-info=release-symbols/"$version"

aab=build/app/outputs/bundle/release/app-release.aab
echo
echo "✓ $aab ($(du -h "$aab" | cut -f1)) — this is the file to upload"

# Optional: readable crash traces in Crashlytics. Never fails the build.
# SKIP_CRASHLYTICS_UPLOAD=1 skips it (offline, or not logged in to Firebase).
app_id=$(grep -A6 'android = FirebaseOptions' lib/firebase_options.dart | sed -nE "s/.*appId: '([^']+)'.*/\1/p")
if [[ "${SKIP_CRASHLYTICS_UPLOAD:-}" == 1 ]]; then
  echo "→ Crashlytics symbol upload skipped (SKIP_CRASHLYTICS_UPLOAD=1)."
elif command -v firebase >/dev/null 2>&1 && [[ -n "$app_id" ]]; then
  echo "→ Uploading crash symbols to Crashlytics (optional)…"
  if firebase crashlytics:symbols:upload --app="$app_id" "release-symbols/$version" >/dev/null 2>&1; then
    echo "  ✓ Dart symbols"
  else
    echo "  ⚠ Dart symbols not uploaded — retry: firebase crashlytics:symbols:upload --app=$app_id release-symbols/$version"
  fi
  res=build/app/generated/res/injectCrashlyticsMappingFileIdRelease/values/com_google_firebase_crashlytics_mappingfileid.xml
  map=build/app/outputs/mapping/release/mapping.txt
  if firebase crashlytics:mappingfile:upload --app="$app_id" --resource-file="$res" "$map" >/dev/null 2>&1; then
    echo "  ✓ Android mapping"
  else
    echo "  ⚠ Android mapping not uploaded — retry: firebase crashlytics:mappingfile:upload --app=$app_id --resource-file=$res $map"
  fi
fi
echo "  Keep release-symbols/$version — it turns obfuscated crash traces back into readable ones."
echo
echo "Next: Play Console → Internal testing → Create new release → upload the .aab"
