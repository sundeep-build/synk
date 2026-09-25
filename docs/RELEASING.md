# Releasing Synk to Google Play (testing tracks)

Package: `club.buildd.synk` · Firebase project: `synk-8f777`

## One-time setup

### 1. Create the upload key

```sh
mkdir -p ~/keys
keytool -genkey -v -keystore ~/keys/synk-upload.jks -keyalg RSA -keysize 2048 \
  -validity 10000 -alias upload
```

Back up the `.jks` file and its passwords in a password manager. Play App Signing
holds the real app-signing key, so a lost upload key can be reset through Play
support, but that takes days.

### 2. Point Gradle at it: `android/key.properties` (git-ignored)

```properties
storePassword=<keystore password>
keyPassword=<key password>
keyAlias=upload
storeFile=/Users/<you>/keys/synk-upload.jks
```

If this file is missing, release builds fall back to the debug key. That works
for `flutter run --release`, but Play Console rejects the bundle.

### 3. Production config: `env/prod.json` (git-ignored)

```sh
cp env/prod.example.json env/prod.json
```

- `YOUTUBE_API_KEY`: ideally a separate production key. In Google Cloud, restrict
  it to *Android apps*, package `club.buildd.synk`, plus the SHA-1 below, and to
  the *YouTube Data API v3*.
- `ANDROID_CERT_SHA1`: the app sends this value itself as `X-Android-Cert`, so
  it only has to match a SHA-1 listed on the key restriction. Use the upload
  key's SHA-1, without colons:

  ```sh
  keytool -list -v -keystore ~/keys/synk-upload.jks -alias upload | grep SHA1
  ```

### 4. Firebase: register the signing certificates (Google Sign-In)

Google Sign-In checks the certificate the installed app is really signed with.
Apps installed from Play are re-signed with Google's **app-signing key**, so:

1. Play Console → *Test and release → App integrity → App signing*: copy the
   **app signing key** SHA-1 and SHA-256. They appear once the first release
   exists. Copy the **upload key** fingerprints too.
2. Firebase console → Project settings → *Your apps → club.buildd.synk* →
   *Add fingerprint*: add all four.
3. Download the new `google-services.json` into `android/app/` and rebuild.

Until this is done, Google Sign-In fails on Play installs. Guest mode still
works.

## Every release

1. Bump the version in `pubspec.yaml`. The number after `+` is the versionCode,
   and it must go up with every upload:
   `version: 1.0.0+1` → `1.0.1+2` → …
2. Build:

   ```sh
   bash scripts/build_release.sh
   # if the Crashlytics mapping upload can't reach the network:
   SKIP_CRASHLYTICS_UPLOAD=1 bash scripts/build_release.sh
   ```

   Output: `build/app/outputs/bundle/release/app-release.aab`.
3. Upload the obfuscated Dart symbols, so Crashlytics traces are readable:

   ```sh
   firebase crashlytics:symbols:upload \
     --app=1:1048701967035:android:6a3c9b630b2458da80279e build/symbols/<version>
   ```

## Play Console: internal testing (fastest, up to 100 testers)

1. **Create app**: name *Synk*, default language, *App*, *Free*, then accept the
   declarations.
2. **Testing → Internal testing → Testers**: create an email list (the testers'
   Google accounts) and save it.
3. **Create new release**: accept *Play App Signing* (Google-managed key), upload
   `app-release.aab`, add release notes, then *Next → Save → Start rollout*.
4. **Testers tab → Copy link**: send the link to your testers. They open it
   signed in with a listed Google account, tap *Accept*, then install from Play.
5. Play Console lists any setup it still needs before the rollout goes through.
   Complete the **App content** section:
   - **Privacy policy URL**: required. `AppConfig.privacyUrl` is still a
     placeholder (`https://example.com/privacy`), so publish a real page and
     update it.
   - **App access**: everything works in guest mode, so there are no login
     credentials to provide.
   - **Ads**: no ads.
   - **Content rating**: fill in the questionnaire. The app has user chat, so
     answer *yes* to users interacting.
   - **Target audience**: 13+ or 18+.
   - **Data safety**: declare Firebase Auth (user IDs, and email with Google
     sign-in), usernames, chat messages, and Analytics/Crashlytics (app
     interactions, crash logs, diagnostics). Data is encrypted in transit, and
     users can delete their account (Profile → Delete account).
   - **Foreground service permissions**: `FOREGROUND_SERVICE_MEDIA_PLAYBACK`,
     used to keep radio playing in the background. Include a short screen
     recording if asked.

## Going to production later

New **personal** developer accounts must first run a **closed test with at least
12 testers opted in for 14 days in a row**. Internal testing doesn't count
towards this. Organisation accounts are exempt. Use *Testing → Closed testing*
the same way as above, then apply for production access from the dashboard.
