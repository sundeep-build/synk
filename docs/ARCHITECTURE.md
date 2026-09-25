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

Features: `auth`, `profile`, `catalog` (media sources), `player`, `rooms`, `home`, `search`, `library`.

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
                               listenerCount, isLive, lastActiveAt, nowPlaying{}
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

## Security model

The rules in `firebase/` are the backend. Both files load cleanly into the Firebase emulators.

- Usernames: the `usernames/{name}` document is created in the same transaction as the profile. Rules require
  each to reference the other (`getAfter`), so a race for a name can't be won twice.
- Users can't grant themselves `isPro`. Profile updates may only touch whitelisted fields.
- Rooms: listing returns public rooms only. Heartbeat updates may change only live-status fields, bounded by capacity
  and stamped with `request.time`.
- RTDB:
  - Only present members can read chat or write queue, votes or chat.
  - Playback writes are allowed for the host, for anyone while the host is away (acting host), or for any member
    making a `seq+1` advance.
  - Chat is rate-limited to 1 message per 0.8 s and reactions to 1 per 0.25 s, using a multi-path write that stamps
    `throttle/{uid}` and the rule check `root(old) < now − limit`.
  - All timestamps must equal the server's `now`.

**Known MVP trade-offs**, each fixed by one Cloud Function on Blaze:

- Room capacity is checked on the client only.
- A member could force a skip without votes (`seq+1`).
- `listenerCount` is written by clients.
- Chat history is never pruned.

## Performance and memory budget

- Artwork is decoded at display size (`memCacheWidth`). A 1000 px cover shown at 56 dp uses about 50 KB, not about 4 MB.
- The ambient background decodes artwork at **48 px** and blurs it (about 9 KB).
- Global image cache is capped at 60 MB / 250 images, and the Firestore disk cache at 40 MB. RTDB persistence is
  **off** on purpose, so the app never plays stale room state.
- Only the dock (nav + mini player) uses a real `BackdropFilter`, and only one of them. Other "glass" is a translucent
  fill.
- Animations stop when idle or off-screen (equalizers, aurora), respect *Reduce motion*, and sit behind
  `RepaintBoundary`.
- Floating reactions are capped at 14 live animations, and chat at 200 messages in memory.
- Large JSON (above 48 KB) is decoded on a background isolate. A single pooled HTTP client is used, and catalog calls
  go through a 10-minute LRU cache.

## Scaling path

| When | Do |
| --- | --- |
| Going public | Blaze plan with a budget alert. App Check. Report/block and word filter. |
| Rooms above ~50 or abuse appears | Cloud Functions: presence → `listenerCount`, server-side capacity and skip enforcement, chat TTL pruning |
| Above ~100k daily users | Shard RTDB (one instance per region/room hash). Use FCM for invites and dedications. Move discovery to a precomputed "top rooms" document. |
| Mainstream catalog | Add a `TrackSource` for a licensed provider (the repository facade is the only change). Watch parties can use the official YouTube IFrame player, which is foreground-only under YouTube's terms. |

## Roadmap to Groic feature parity

1. Shorts or YouTube watch parties (IFrame player, synced with the same anchor model)
2. Pro subscription (RevenueCat free tier) and in-app currency for gifts. Pro perks: bigger rooms, a highlighted name.
3. Push notifications (FCM): dedications, "your friend went live"
4. Friends/follow, DMs, room history
5. User uploads (Cloud Storage on Blaze) with moderation
6. Collaborative playlists
