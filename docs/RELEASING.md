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
   `version: 1.1.0+2` → `1.1.1+3` → …
2. If anything in `firebase/` changed, deploy it first. Builds rely on the rules
   and indexes being live:
   `firebase deploy --only firestore,database`
3. Build:

   ```sh
   bash scripts/build_release.sh
   # if the Crashlytics mapping upload can't reach the network:
   SKIP_CRASHLYTICS_UPLOAD=1 bash scripts/build_release.sh
   ```

   Output: `build/app/outputs/bundle/release/app-release.aab`.
4. The script also uploads the obfuscated Dart symbols, so Crashlytics traces are
   readable. If it couldn't, or you skipped it, upload them by hand:

   ```sh
   firebase crashlytics:symbols:upload \
     --app=1:1048701967035:android:6a3c9b630b2458da80279e release-symbols/<version>
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
   - **Foreground service permissions**: declare both types, with a short
     screen recording of each:
     - `FOREGROUND_SERVICE_MEDIA_PLAYBACK`: keeps radio playing in the
       background.
     - `FOREGROUND_SERVICE_MICROPHONE`: keeps a huddle (voice call in a room)
       running while the app is in the background. The user starts it, and an
       "In a huddle" notification shows while it runs.
   - **Data safety** for huddles: the app uses the **microphone** (voice) and
     the **camera** (optional video) only while you're in a huddle. Streams go
     directly between the phones in the call. Nothing is recorded or stored,
     and none of it passes through our servers. Declare *Audio: voice* and
     *Photos and videos: videos* as shared with other users in the call, not
     stored, and optional.
   - **Permissions** new in 1.1.0: `RECORD_AUDIO`, `CAMERA` and
     `BLUETOOTH_CONNECT` (headset audio in huddles). Play shows these to users
     on the store page automatically.

## Going to production later

New **personal** developer accounts must first run a **closed test with at least
12 testers opted in for 14 days in a row**. Internal testing doesn't count
towards this. Organisation accounts are exempt. Use *Testing → Closed testing*
the same way as above, then apply for production access from the dashboard.
