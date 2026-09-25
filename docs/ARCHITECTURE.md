# Architecture

## Layout: feature-first, layered inside each feature

```text
lib/
  main.dart / bootstrap.dart   start-up: Firebase, crash reporting, memory budgets, audio service, DI overrides
  app/                         MaterialApp, go_router (redirect policy), tab shell with the floating dock
  core/
    config/                    AppConfig: flavors via --dart-define, limits, endpoints
    design_system/             tokens, themes, SynkColors extension, reusable components
    di/                        infrastructure providers (Firebase instances, HTTP, local store, theme)
    error/                     AppException: every error the UI sees is one of these
    network/                   ApiClient (retry, timeout, isolate JSON decode), TtlCache (LRU)
    storage/ utils/ logging/
  features/<feature>/
    domain/                    immutable models, pure logic (no Flutter/Firebase imports where possible)
    data/                      repositories and data sources (Firestore, RTDB, HTTP)
    application/               Riverpod providers and controllers (use cases + state)
    presentation/              screens and widgets
```

Features: `auth`, `profile`, `catalog` (media sources), `player`, `rooms` (including huddles), `home`, `search`,
`library`.

## Design system (`core/design_system`)

Flat and dark: deep navy neutrals (`ink950` background → `ink800` raised discs) with the logo's colours as solid
accents: violet for primary actions and the selected tab, pink for selections and likes, cyan for progress and "now
playing". The only gradient is the logo itself. Montserrat throughout. Section titles pair a heavy first word with a
light rest (`SectionHeader`, `SplitTitle`) beside a short accent bar.

Avatars are cartoon characters drawn in code (`CartoonAvatar`: six pop, six jazz; no image assets) or an emoji,
on an identity colour. A character is stored as `c:<n>` in the existing avatar field, which every surface already
syncs (profile, presence, chat, huddle, room host), so it needed no schema or rules change.

Building blocks: `CircleIconButton` / `CircleBackButton` (round raised icons in headers), `PlayStateButton` (track
rows), `PillButton` (Play/Playing, Room code), `SegmentIndicator` (carousels), `DuotoneCover` (artwork tinted one
colour, used on room tickets), `GridBackdrop` (faint studio grid), `BrandWordmark`. Screens use these and theme styles
rather than one-off colours.

## Media sources and playback engines

Two sources, chosen because both are free *and* legal to use this way:

| Source | Discovery | Playback | Background |
| --- | --- | --- | --- |
| YouTube | Data API v3 (`YouTubeApi`): regional music chart (1 unit), search (100 units, submit-only, cached 12h) | Official IFrame player (`YouTubeEngine` + `YouTubeStage`) | ❌ never — YouTube API policy III.I.9 |
| Live radio | Radio Browser (`RadioBrowserApi`) | just_audio + audio_service (`RadioEngine`) | ✅ with lock-screen controls |

`PlayerHub` routes each track to its engine and exposes one set of streams, so the solo queue and rooms don't
care about the source. YouTube compliance is structural: a player exists only while a `YouTubeStage` is on screen
(it creates the controller on mount and closes it on unmount), and the stage pauses the video when the app goes to
the background. Search results are filtered to embeddable, non-live videos, so users never land on "Video
unavailable". Rooms use seek-only drift correction for videos (YouTube has no fine playback-rate control) and
re-sync as soon as a stage comes back on screen.

**One player, moved between screens.** The app never has more than one YouTube player. Screens place it through a
`VideoSlot` (room, Now Playing, the floating card, the Android PiP window), and a `VideoStageRegistry` gives it to the
highest-priority slot that wants it (PiP > a full screen > the floating card). Every owner builds it under the same
`GlobalKey`, so changing owner *moves* the playing WebView instead of creating a new one: minimising the room hands the
video to the floating card mid-play, with no reload. The timing matters. Slots let go at event time (a route starting
to close, a PiP callback, an engine stream event), so the old and the new owner rebuild in the same frame. A slot that
claims while mounting takes over one frame later, so two slots never hold the player at once. Covered by
`test/widget/video_slot_test.dart`.

**Dependency rule.** `presentation → application → data → domain`. Features share code through
`core/` or through another feature's `application` providers, never through its widgets.

## State management rules (Riverpod 3)

- `Provider` / `StreamProvider` hold infrastructure and shared streams. Room-scoped data uses `.autoDispose.family`,
  so leaving a screen closes its listeners, and with them the bandwidth and the bill.
- `roomSessionProvider` is deliberately **kept alive**. Music continues while the user browses or the
  phone is locked.
- Widgets `ref.watch(provider.select(...))` only the fields they render. Only `PlayerProgress` watches the
  position stream (about 5 Hz), so full screens never rebuild at tick rate.
- Retry policy (`bootstrap.dart`): network errors are retried twice with backoff. Permission and validation errors are
  never retried.

## Data model

### Firestore (persistent, queried)

```text
users/{uid}                    username, displayName, avatarEmoji, avatarColor, vibes[], isPro
  likes/{trackId}              track{compact}, likedAt
  playlists/{id}               name, tracks[≤200 compact], updatedAt      ← one read per playlist
usernames/{name}               uid                                       ← uniqueness (rules + transaction)
rooms/{roomId}                 name, code, host*, visibility, mode, capacity, vibe,
                               listenerCount, isLive, closed, lastActiveAt, nowPlaying{}
roomCodes/{CODE}               roomId                                    ← join by code, private rooms
```

### Realtime Database (live, high-churn)

```text
roomsLive/{roomId}/meta            hostId, capacity, closed
roomsLive/{roomId}/playback        {track, status, positionMs, updatedAt: SERVER_TS, seq, by, qid}
roomsLive/{roomId}/queue/{push}    {track, by, byName, at}
roomsLive/{roomId}/presence/{uid}  {name, emoji, color, joinedAt}  + onDisconnect().remove()
roomsLive/{roomId}/skipVotes/{uid} = seq
roomChats/{roomId}/{push}          chat, kept separate so playback listeners never download chat
roomReactions/{roomId}/{push}      ephemeral, queried with startAt(now), so old reactions never replay
throttle/{uid}/{chat|react}        last write time; the rules use it for rate limiting
huddles/{roomId}/members/{uid}     {name, emoji, color, sid, mic, cam, joinedAt}  + onDisconnect().remove()
huddles/{roomId}/signals/{uid}/{push}  that member's inbox: {f, fs, ts, t: offer|answer|ice, sdp | c, at}
```

**Why two databases?** Firestore bills per document read. A 20-person room chatting 100 messages costs
2,000 reads. RTDB bills bandwidth: the same chat is about 0.5 MB. Persistent, queryable data goes to Firestore;
chatty live data goes to RTDB.

## Playback sync

The room never streams positions. It stores one **anchor**:

```text
playback = { track, status: playing, positionMs: P, updatedAt: T (server timestamp) }
expected(now) = P + (serverNow − T)              serverNow = localNow + .info/serverTimeOffset
```

Every client runs a 1 Hz loop (`RoomSessionController._tick`) and checks the drift between where its player is and
where it should be:

| Drift | Action | Why |
| --- | --- | --- |
| < 120 ms | nothing | inaudible |
| 120–900 ms | speed 1 ± up to 6% until caught up | smooth, and no audible jump |
| > 900 ms | seek to expected + 250 ms lead | covers late joins and buffering stalls |

Radio is live for everyone, so it is never time-corrected. Pause, play and seek by the host rewrite the anchor.
Bandwidth is the same for 2 listeners or 50.

## Advancing tracks without a server

- `seq` increases by one per track. Moving to the next track is an **RTDB transaction** that commits only if
  `seq` is still the value the client saw. Many clients may try; exactly one wins.
- The **leader** tries immediately. The leader is the host, or, if the host is away, the member who has been present
  longest (`RoomRules.leader`), which every client computes the same way from presence. Other clients wait 1.5–3 s,
  which covers a leader that crashed.
- Order of candidates: first the queue head, then autoplay (same-genre trending, excluding recently played tracks).
- The consumed queue item's id is stored in `playback.qid`. It is hidden from the queue and removed lazily, so a crash
  between "advance" and "remove" can never replay a song.
- Vote-to-skip: members write `skipVotes/{uid} = seq`. When a simple majority is reached, the room advances through
  the same transaction. Votes cast for an old `seq` are ignored automatically.

## Huddles (voice, plus camera, inside a room)

A huddle is an opt-in call among people in the same room, layered over the room's music. It needs no server:
media goes **peer to peer** (WebRTC mesh via `flutter_webrtc`), and only signalling goes through RTDB, a few KB
per connection.

```text
HuddleController (application)   one task queue: member changes, signals, retries and camera toggles never interleave
  ├─ HuddleSignaling (data)      members list + each member's own inbox in RTDB
  ├─ HuddleMedia (data)          mic, camera, audio routing
  └─ PeerLink × (n−1) (data)     one RTCPeerConnection per other member
```

| Decision | Why |
| --- | --- |
| Mesh, capped at **8 people / 4 cameras** (`AppConfig`) | Free and serverless. Every camera is encoded once per peer, so the caps keep a phone under ~1.5 Mbps up and a mid-range CPU cool. |
| The member whose uid sorts first sends the offer (`HuddleRules.isOfferer`) | Both sides agree without talking, so offers never cross ("glare"). |
| One inbox per member (`signals/{uid}`), read only by its owner | Signalling traffic per phone grows with the group, not with its square. Handled messages are deleted in one batched write per second. |
| Every message carries `fs`/`ts` session ids; each join gets a new `sid` | Messages meant for a previous join are ignored, and a rejoin rebuilds connections cleanly. |
| Audio and video transceivers negotiated up front | Camera on/off is a local `replaceTrack`, with no renegotiation. `members/{uid}/cam` tells others to show video or the avatar. |
| Opus fmtp rewritten: `usedtx=1; useinbandfec=1; stereo=0; maxaveragebitrate=32000` | Near-zero bitrate while silent, which is most of a group call. FEC rides out mobile packet loss. |
| Video budget per connection (`HuddleRules`): ~1.2 Mbps total split across peers (150–600 kbps each), 24→15 fps, 640×480 → ×1.5/×2 smaller as the group grows | The per-peer encode cost falls as the mesh grows. |
| ICE candidates batched (150 ms, ≤10 per write), sent only after the SDP | Fewer writes, and the receiver never gets ICE for a connection it hasn't created. |
| Failed connection → the offerer rebuilds it with backoff (2/4/8/16 s, then shows "Can't connect") | Survives network switches. An ICE restart would save one round trip, but a rebuild is simpler and always recovers. |
| Server dropped us (onDisconnect fired during a blip) → rejoin under a new sid | Peers had already torn down; a new session reconnects everyone. |

**Audio.** Android runs in communication mode (hardware echo cancelling) but **does not take audio focus**,
because just_audio would pause the room's radio. iOS uses `playAndRecord` + `videoChat` (loudspeaker by default).
Leaving hands the session back to the music configuration. Speaking rings come from WebRTC `audioLevel` stats,
sampled every 400 ms and only while a widget watches `huddleSpeakingProvider`.

**Background.** Android 11+ allows background mic access only from a foreground service of type `microphone`
(`HuddleService.kt`, "In a huddle" notification), started while the app is visible. The camera switches off
while the app is hidden and back on when it returns. iOS keeps the mic through the existing `audio` background
mode.

**Memory.** Video renderers (GPU textures) exist only for cameras that are on *and* on screen: the huddle view's
grid is lazy, and the in-room strip shows avatars with a camera badge, not video. Turning the camera off stops
capture and disposes the stream, rather than muting it.

**NAT traversal.** Google STUN is the default. Some mobile carriers need a TURN relay. Set `TURN_URLS`,
`TURN_USERNAME` and `TURN_CREDENTIAL` in `env/*.json` (e.g. Metered's free tier). Without them most calls still
connect, but some on strict networks won't.

## Security model

The rules in `firebase/` are the backend. Both files load cleanly into the Firebase emulators.

- Usernames: the `usernames/{name}` document is created in the same transaction as the profile. Rules require
  each to reference the other (`getAfter`), so a race for a name can't be won twice.
- Users can't grant themselves `isPro`. Profile updates may only touch whitelisted fields.
- Rooms: listing returns public rooms, plus a host's own rooms (Home → *Your rooms*). Heartbeat updates may change
  only live-status fields, bounded by capacity and stamped with `request.time`. Only the host can set `closed`, a
  closed room stays closed, and it can never be marked live again. `scripts/firestore_rules_smoke.py` checks this.

**Room lifecycle.** *Live* while people are in it (the leader's heartbeat keeps `isLive` and `lastActiveAt` fresh).
*Idle* once the last person leaves (`isLive: false`), or *stale* when the app was killed without a clean leave (no
heartbeat for 3 minutes). Either way it drops out of Live now, but its host still sees it under *Your rooms*
(`hostedBy`: `hostId ==` + `createdAt desc`, one composite index) and reopening it makes it live again. Listeners can't
join an idle room until its host is back. *Closed* when the host ends it: gone for good.
- RTDB:
  - Only present members can read chat or write queue, votes or chat.
  - Playback writes are allowed for the host, for anyone while the host is away (acting host), or for any member
    making a `seq+1` advance.
  - Chat is rate-limited to 1 message per 0.8 s and reactions to 1 per 0.25 s, using a multi-path write that stamps
    `throttle/{uid}` and the rule check `root(old) < now − limit`.
  - All timestamps must equal the server's `now`.
  - Huddles: only people present in the room can join its huddle or see who's in it, and not once it's closed.
    Members edit only their own entry. A signal may be sent only by a huddle member, as themselves, to another
    huddle member. Each inbox is readable and deletable only by its owner. Signals are size-capped
    (SDP ≤ 20 KB, ICE batch ≤ 12 KB).

**Known MVP trade-offs**, each fixed by one Cloud Function on Blaze:

- Room capacity is checked on the client only.
- A member could force a skip without votes (`seq+1`).
- `listenerCount` is written by clients.
- Chat history is never pruned.
- Huddle size and camera caps are checked on the client only, and signals aren't rate-limited.

## Performance and memory budget

- Artwork is decoded at display size (`memCacheWidth`). A 1000 px cover shown at 56 dp uses about 50 KB, not about 4 MB.
- The ambient background decodes artwork at **48 px** and blurs it (about 9 KB).
- Global image cache is capped at 60 MB / 250 images, and the Firestore disk cache at 40 MB. RTDB persistence is
  **off** on purpose, so the app never plays stale room state.
- No `BackdropFilter` anywhere: a live blur re-renders on every frame of scrolling beneath it, the main source of jank
  on budget Android phones. The dock is a solid panel. The studio grid behind brand screens is painted once and
  cached.
- Long track lists use a fixed row extent (`TrackListView` / `SliverPrototypeExtentList` with
  `TrackTile.prototype`), so layout doesn't grow with list length. Rows repaint only when *their* play state changes.
- Tinted covers (`DuotoneCover`) tint through the image's own colour filter, so they add no extra layer.
- Animations stop when idle or off-screen (equalizers, aurora), respect *Reduce motion*, and sit behind
  `RepaintBoundary`.
- Floating reactions are capped at 14 live animations, and chat at 200 messages in memory.
- Huddles: see *Huddles → Memory* above (renderers only for visible cameras, camera fully released when off,
  stats polled only while watched).
- Large JSON (above 48 KB) is decoded on a background isolate. A single pooled HTTP client is used, and catalog calls
  go through a 10-minute LRU cache.

## Scaling path

| When | Do |
| --- | --- |
| Going public | Blaze plan with a budget alert. App Check. Report/block and word filter. |
| Rooms above ~50 or abuse appears | Cloud Functions: presence → `listenerCount`, server-side capacity and skip enforcement, chat TTL pruning |
| Huddles above 8 people, or "stage" rooms with many listeners | Switch `PeerLink` for an SFU (LiveKit or mediasoup, self-hosted or cloud). Each phone then sends one stream. It needs a Cloud Function to mint access tokens. `HuddleController` and the UI stay as they are. |
| Above ~100k daily users | Shard RTDB (one instance per region/room hash). Use FCM for invites and dedications. Move discovery to a precomputed "top rooms" document. |
| Mainstream catalog | Add a `TrackSource` for a licensed provider (the repository facade is the only change). Watch parties can use the official YouTube IFrame player, which is foreground-only under YouTube's terms. |

## Roadmap to Groic feature parity

1. Shorts or YouTube watch parties (IFrame player, synced with the same anchor model)
2. Pro subscription (RevenueCat free tier) and in-app currency for gifts. Pro perks: bigger rooms, a highlighted name.
3. Push notifications (FCM): dedications, "your friend went live"
4. Friends/follow, DMs, room history
5. User uploads (Cloud Storage on Blaze) with moderation
6. Collaborative playlists
