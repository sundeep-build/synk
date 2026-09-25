#!/usr/bin/env python3
"""Behavioural smoke test for firebase/database.rules.json against the RTDB emulator.

Run:  firebase emulators:exec --project demo-synk --only database "python3 scripts/rtdb_rules_smoke.py"
"""
import base64
import json
import sys
import time
import urllib.error
import urllib.request

HOST = "http://127.0.0.1:9000"
NS = "demo-synk-default-rtdb"
TS = {".sv": "timestamp"}
FAILURES = []


def token(uid):
    """Unsigned JWT the emulator accepts as a signed-in user."""
    enc = lambda d: base64.urlsafe_b64encode(json.dumps(d).encode()).rstrip(b"=").decode()
    now = int(time.time())
    payload = {"sub": uid, "user_id": uid, "iat": now, "exp": now + 3600,
               "aud": "demo-synk", "iss": "https://securetoken.google.com/demo-synk",
               "firebase": {"sign_in_provider": "anonymous", "identities": {}}}
    return f"{enc({'alg': 'none', 'typ': 'JWT'})}.{enc(payload)}."


def call(method, path, body=None, uid=None, admin=False):
    url = f"{HOST}/{path}.json?ns={NS}"
    if uid:
        url += f"&auth={token(uid)}"
    headers = {"Authorization": "Bearer owner"} if admin else {}
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(url, data=data, method=method, headers=headers)
    try:
        urllib.request.urlopen(req).read()
        return True
    except urllib.error.HTTPError:
        return False


def expect(name, ok, want=True):
    status = "✓" if ok == want else "✗"
    if ok != want:
        FAILURES.append(name)
    print(f"{status} {name}: {'allowed' if ok else 'denied'}")


def member(uid, name):
    return {"name": name, "emoji": "🎧", "color": 1, "joinedAt": TS}


track = {"id": "audius:1", "src": "audius", "t": "Song", "a": "Artist", "u": "https://s"}

call("PUT", "", {}, admin=True)  # clean slate
R = "roomsLive/r1"

expect("host creates room meta", call("PUT", f"{R}/meta", {"hostId": "host", "capacity": 10, "closed": False, "createdAt": TS}, uid="host"))
expect("stranger cannot hijack meta", call("PATCH", f"{R}/meta", {"capacity": 50}, uid="eve"), want=False)
expect("user joins presence as self", call("PUT", f"{R}/presence/alice", member("alice", "alice"), uid="alice"))
expect("cannot write someone else's presence", call("PUT", f"{R}/presence/bob", member("bob", "bob"), uid="alice"), want=False)
expect("host joins presence", call("PUT", f"{R}/presence/host", member("host", "host"), uid="host"))
expect("anyone signed in can read who's in a room (Home avatars)", call("GET", f"{R}/presence", uid="eve"))
expect("signed-out cannot read who's in a room", call("GET", f"{R}/presence"), want=False)

pb = lambda seq, by, status="playing": {"track": track, "status": status, "positionMs": 0, "updatedAt": TS, "seq": seq, "by": by}
expect("host starts playback (seq 1)", call("PUT", f"{R}/playback", pb(1, "host"), uid="host"))
expect("member cannot pause while host present", call("PUT", f"{R}/playback", pb(1, "alice", "paused"), uid="alice"), want=False)
expect("member may advance seq+1", call("PUT", f"{R}/playback", pb(2, "alice"), uid="alice"))
expect("member cannot jump seq+5", call("PUT", f"{R}/playback", pb(7, "alice"), uid="alice"), want=False)
expect("member cannot spoof 'by'", call("PUT", f"{R}/playback", pb(3, "host"), uid="alice"), want=False)
call("DELETE", f"{R}/presence/host", uid="host")
expect("acting host (host away) may pause", call("PUT", f"{R}/playback", pb(2, "alice", "paused"), uid="alice"))
expect("non-member cannot write playback", call("PUT", f"{R}/playback", pb(3, "eve"), uid="eve"), want=False)

msg = lambda uid: {"uid": uid, "name": uid, "emoji": "🎧", "color": 1, "text": "hi", "kind": "text", "ts": TS}
expect("chat without throttle stamp is rejected", call("PUT", "roomChats/r1/m0", msg("alice"), uid="alice"), want=False)
expect("chat with throttle stamp (multi-path)", call("PATCH", "", {"roomChats/r1/m1": msg("alice"), "throttle/alice/chat": TS}, uid="alice"))
expect("second message within 800ms is rate-limited", call("PATCH", "", {"roomChats/r1/m2": msg("alice"), "throttle/alice/chat": TS}, uid="alice"), want=False)
time.sleep(0.9)
expect("message after cooldown is allowed", call("PATCH", "", {"roomChats/r1/m3": msg("alice"), "throttle/alice/chat": TS}, uid="alice"))
expect("cannot post as someone else", call("PATCH", "", {"roomChats/r1/m4": msg("bob"), "throttle/alice/chat": TS}, uid="alice"), want=False)
expect("system messages can't be forged", call("PATCH", "", {"roomChats/r1/m5": {**msg("alice"), "kind": "system"}, "throttle/alice/chat": TS}, uid="alice"), want=False)
expect("non-member cannot read chat", call("GET", "roomChats/r1", uid="eve"), want=False)
expect("member can read chat", call("GET", "roomChats/r1", uid="alice"))

q = {"track": track, "by": "alice", "byName": "alice", "at": TS}
expect("member queues a song as self", call("PUT", f"{R}/queue/q1", q, uid="alice"))
expect("cannot queue as someone else", call("PUT", f"{R}/queue/q2", {**q, "by": "bob"}, uid="alice"), want=False)

# ── Huddles ────────────────────────────────────────────────────────────────
H = "huddles/r1"
hm = lambda name, sid: {"name": name, "emoji": "🎧", "color": 1, "sid": sid, "mic": True, "cam": False, "joinedAt": TS}
call("PUT", f"{R}/presence/bob", member("bob", "bob"), uid="bob")
expect("room member joins the huddle as self", call("PUT", f"{H}/members/alice", hm("alice", "sidalice01"), uid="alice"))
expect("non-member of the room cannot join its huddle", call("PUT", f"{H}/members/eve", hm("eve", "sideve0001"), uid="eve"), want=False)
expect("cannot join the huddle as someone else", call("PUT", f"{H}/members/bob", hm("bob", "sidbob0001"), uid="alice"), want=False)
expect("huddle entry needs a session id", call("PUT", f"{H}/members/bob", {**hm("bob", "x"), "sid": "short"}, uid="bob"), want=False)
expect("second room member joins the huddle", call("PUT", f"{H}/members/bob", hm("bob", "sidbob0001"), uid="bob"))
expect("member toggles own mic/camera", call("PATCH", f"{H}/members/alice", {"mic": False, "cam": True}, uid="alice"))
expect("cannot toggle someone else's mic", call("PATCH", f"{H}/members/bob", {"mic": False}, uid="alice"), want=False)
expect("room member can see who's in the huddle", call("GET", f"{H}/members", uid="alice"))
expect("outsider cannot see who's in the huddle", call("GET", f"{H}/members", uid="eve"), want=False)

sig = lambda f, to, **kw: {"f": f, "fs": "sid" + f, "ts": "sid" + to, "t": "offer", "sdp": "v=0", "at": TS, **kw}
expect("huddle member sends an offer to another", call("PUT", f"{H}/signals/bob/s1", sig("alice", "bob"), uid="alice"))
expect("cannot send a signal as someone else", call("PUT", f"{H}/signals/bob/s2", sig("carol", "bob"), uid="alice"), want=False)
expect("cannot overwrite a delivered signal", call("PUT", f"{H}/signals/bob/s1", sig("alice", "bob", t="ice"), uid="alice"), want=False)
expect("unknown signal types are rejected", call("PUT", f"{H}/signals/bob/s3", sig("alice", "bob", t="hack"), uid="alice"), want=False)
expect("oversized SDP is rejected", call("PUT", f"{H}/signals/bob/s4", sig("alice", "bob", sdp="x" * 20001), uid="alice"), want=False)
expect("ICE batch as one string", call("PUT", f"{H}/signals/bob/s5", sig("alice", "bob", t="ice", sdp=None, c="[]"), uid="alice"))
expect("recipient reads own inbox", call("GET", f"{H}/signals/bob", uid="bob"))
expect("others cannot read someone's inbox", call("GET", f"{H}/signals/bob", uid="alice"), want=False)
expect("sender cannot delete a delivered signal", call("DELETE", f"{H}/signals/bob/s1", uid="alice"), want=False)
expect("recipient acks (deletes) handled signals", call("PATCH", f"{H}/signals/bob", {"s1": None, "s5": None}, uid="bob"))
call("DELETE", f"{H}/members/bob", uid="bob")
expect("cannot signal someone who left the huddle", call("PUT", f"{H}/signals/bob/s6", sig("alice", "bob"), uid="alice"), want=False)
expect("leaving clears own membership and inbox together", call("PATCH", H, {"members/alice": None, "signals/alice": None}, uid="alice"))

call("PUT", f"{R}/presence/host", member("host", "host"), uid="host")
expect("host closes room", call("PUT", f"{R}/meta/closed", True, uid="host"))
expect("nobody can join a closed room", call("PUT", f"{R}/presence/carol", member("carol", "carol"), uid="carol"), want=False)
expect("nobody can join the huddle of a closed room", call("PUT", f"{H}/members/alice", hm("alice", "sidalice02"), uid="alice"), want=False)

print()
if FAILURES:
    print(f"{len(FAILURES)} rule expectation(s) failed: {FAILURES}")
    sys.exit(1)
print("All RTDB rule expectations hold.")
