# Synk — listen together, in sync

A social music app in the spirit of Groic: create or join **rooms** where everyone watches the same YouTube
video or hears the same live radio at the same second. Rooms have live chat, emoji reactions, song dedications,
a shared queue with vote-to-skip. The MVP runs on free tiers with no server code.

> **Synk** is a placeholder brand. To rename it, change `AppConfig.appName`, `android:label`,
> `CFBundleDisplayName` and the bundle id `club.buildd.synk`.

| Layer | Choice |
| --- | --- |
| Framework | Flutter 3.41 / Dart 3.11, Android + iOS |
| State / routing | Riverpod 3 (no codegen), go_router 17 |
| Backend | Firebase Auth, Cloud Firestore, Realtime Database, Crashlytics, Analytics |
| Audio | just_audio + audio_service (background playback, lock-screen controls) |
| Media sources | **YouTube** via the official IFrame player + Data API v3 (songs & videos, on screen only) and **[Radio Browser](https://api.radio-browser.info)** (50k+ live stations, plays in the background) |

---

## Quick start

```bash
flutter pub get
flutter test                                        # unit + widget tests
cp env/dev.example.json env/dev.json                # then put your YouTube API key in it
flutter run --dart-define-from-file=env/dev.json    # or use the "Synk (dev)" VS Code launch config
```

### 1. Firebase project (one-time, about 10 minutes)

1. Create a project at <https://console.firebase.google.com>. Analytics is optional.
2. **Authentication → Sign-in method**: enable **Anonymous**, **Google** and **Apple**.
   Apple is needed for iOS App Store review whenever Google sign-in is offered.
3. **Firestore Database**: create it in *production mode*. For India, use region `asia-south1` (Mumbai).
4. **Realtime Database**: create it in *locked mode*. The nearest region to India is `asia-southeast1`.
5. Configure the Flutter app:

   ```bash
   dart pub global activate flutterfire_cli
   flutterfire configure --project=<project-id> --platforms=android,ios \
     --android-package-name=club.buildd.synk --ios-bundle-id=club.buildd.synk
   ```

   This overwrites `lib/firebase_options.dart` and adds the platform config files.
6. Deploy the security rules and indexes. **The app will not work without them.**

   ```bash
   firebase use <project-id>
   firebase deploy --only firestore,database
   ```

7. **Google Sign-In**
   - Android: add your debug and release **SHA-1** in Project settings → Android app.
     Get it with `cd android && ./gradlew signingReport`. Then re-download `google-services.json`.
   - iOS: add `REVERSED_CLIENT_ID` from `ios/Runner/GoogleService-Info.plist` as a URL scheme.
     `Info.plist` has a marked placeholder for it.
8. **Apple Sign-In** (iOS): in Xcode → Runner → Signing & Capabilities, add *Sign in with Apple*.
9. **YouTube Data API key** (for search and charts; playback itself needs no key):
   - Enable **YouTube Data API v3** in Google Cloud for the same project.
   - Create an API key. Restrict it to that API and to **Android apps**: package `club.buildd.synk` + your SHA-1.
   - Put it in `env/dev.json` as `YOUTUBE_API_KEY` (git-ignored). Without a key the app runs radio-only.
   - Release builds: add the release SHA-1 to the key and pass it as `ANDROID_CERT_SHA1`.

### 2. Run

```bash
flutter run --dart-define-from-file=env/dev.json
flutter build appbundle --dart-define-from-file=env/prod.json --obfuscate --split-debug-info=build/symbols
```

### Local backend (optional)

```bash
firebase emulators:start --project demo-synk   # Auth, Firestore, RTDB, and the UI on :4000
```

---

## What's in the MVP

| Area | Features |
| --- | --- |
| Onboarding | Guest mode ("just look around"), Google and Apple sign-in, a live username availability check, an emoji avatar builder, and vibe picker |
| Rooms | Public or code-only rooms, music or radio mode, capacity limit, synced playback, host controls, an acting host when the host leaves, shareable invite deep links (`synk://app/join/CODE`) |
| In-room | Live chat, floating reactions, dedications, shared queue, vote-to-skip, autoplay of similar songs when the queue runs dry |
| Discover | Live rooms, trending music videos for your country, radio for your vibe, radio near you, genre pages (videos + radio), search for videos and stations |
| Library | Likes, playlists (create, rename, delete, swipe to remove), recently played |
| Player | Radio: background playback with lock-screen and notification controls. YouTube: official on-screen player (pauses when the app is minimised, as YouTube requires). Mini player, full player, "Listen together" to turn solo listening into a room |
| Profile | Edit avatar, name and vibes, theme (dark/light/auto), link a guest account, sign out, **delete account** (required by both app stores) |

## Free-tier budget

Pricing and billing requirements below were checked in September 2026. Re-check <https://firebase.google.com/pricing>
before launch.

| Service | Free quota | How the app stays inside it |
| --- | --- | --- |
| Firestore | 50k reads and 20k writes per day, 1 GiB | Room discovery is a one-shot query cached for 60s, not a live listener. A playlist is one document. Recent history is stored on the device. Large map fields are excluded from indexing. |
| Realtime Database | 1 GB stored, 10 GB/month downloaded, **100 simultaneous connections on Spark** | Chat, presence and playback live here because RTDB bills bandwidth, not operations. Only one small anchor is written per play, pause or seek, never position ticks. |
| YouTube Data API | 10,000 units/day | Charts use `videos.list` (1 unit). Search (100 units) runs only on submit and is cached 12h on the device. Autoplay reuses the cached chart. Apply for a free quota increase before launch. |
| Auth | Anonymous, Google and Apple are free | SMS OTP is not free on Firebase, so it isn't used. |
| Crashlytics and Analytics | Free | — |
| Cloud Storage and Cloud Functions | **Require the Blaze plan** (Storage since Feb 2026) | The MVP needs neither. Avatars are generated from an emoji and a gradient, and security rules take the place of server code. |

**At launch**, switch to **Blaze with a $1 budget alert**. The free quotas still apply, so the bill stays at about $0.
Blaze removes the 100-connection Realtime Database cap and unlocks Functions, Storage and App Check with Play
Integrity.

## Launch checklist

- [ ] Set the real Privacy and Terms URLs in `AppConfig` and in the store listings
- [ ] Enable **App Check** (Play Integrity / App Attest) on Firestore and RTDB
- [ ] Create a release keystore and signing config (`android/app/build.gradle.kts` currently uses the debug key)
- [ ] Bundle the fonts (see `AppTheme`) for an offline first launch
- [ ] Replace the Google button icon with the official asset (Google branding guidelines)
- [ ] Add a report/block flow and moderation before opening public rooms widely
- [ ] Budget alerts in Google Cloud Billing
- [ ] Request a YouTube Data API quota increase (free; needs YouTube's API compliance review)
- [ ] Add the release SHA-1 to the YouTube API key restriction and pass `ANDROID_CERT_SHA1`

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the design, the sync algorithm and the scaling path.
