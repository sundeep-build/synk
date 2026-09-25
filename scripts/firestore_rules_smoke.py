#!/usr/bin/env python3
"""Behavioural smoke test for the room rules in firebase/firestore.rules, against the Firestore emulator.

Run:  firebase emulators:exec --project demo-synk --only firestore "python3 scripts/firestore_rules_smoke.py"
"""
import base64
import json
import sys
import time
import urllib.error
import urllib.request

BASE = "http://127.0.0.1:8080/v1/projects/demo-synk/databases/(default)/documents"
DOC = "projects/demo-synk/databases/(default)/documents"
FAILURES = []


def token(uid):
    """Unsigned JWT the emulator accepts as a signed-in user."""
    enc = lambda d: base64.urlsafe_b64encode(json.dumps(d).encode()).rstrip(b"=").decode()
    now = int(time.time())
    payload = {"sub": uid, "user_id": uid, "iat": now, "exp": now + 3600,
               "aud": "demo-synk", "iss": "https://securetoken.google.com/demo-synk",
               "firebase": {"sign_in_provider": "anonymous", "identities": {}}}
    return f"{enc({'alg': 'none', 'typ': 'JWT'})}.{enc(payload)}."


def call(method, url, body=None, uid=None, admin=False):
    headers = {"Content-Type": "application/json"}
    if admin:
        headers["Authorization"] = "Bearer owner"
    elif uid:
        headers["Authorization"] = f"Bearer {token(uid)}"
    data = None if body is None else json.dumps(body).encode()
    try:
        urllib.request.urlopen(urllib.request.Request(url, data=data, method=method, headers=headers)).read()
        return True
    except urllib.error.HTTPError:
        return False


def expect(name, ok, want=True):
    if ok != want:
        FAILURES.append(name)
    print(f"{'✓' if ok == want else '✗'} {name}: {'allowed' if ok else 'denied'}")


def value(v):
    if isinstance(v, bool):
        return {"booleanValue": v}
    if isinstance(v, int):
        return {"integerValue": str(v)}
    return {"stringValue": v}


def room(host, visibility, created):
    fields = {"name": "Room", "code": "ABC234", "hostId": host, "hostName": host, "hostEmoji": "🎧",
              "hostColor": 1, "visibility": visibility, "mode": "music", "capacity": 10,
              "listenerCount": 1, "isLive": True}
    return {"fields": {**{k: value(v) for k, v in fields.items()},
                       "createdAt": {"timestampValue": created}, "lastActiveAt": {"timestampValue": created}}}


def by_host(host, public_only=False):
    filters = [{"fieldFilter": {"field": {"fieldPath": "hostId"}, "op": "EQUAL", "value": value(host)}}]
    if public_only:
        filters.append({"fieldFilter": {"field": {"fieldPath": "visibility"}, "op": "EQUAL", "value": value("public")}})
    return {"structuredQuery": {
        "from": [{"collectionId": "rooms"}],
        "where": {"compositeFilter": {"op": "AND", "filters": filters}},
        "orderBy": [{"field": {"fieldPath": "createdAt"}, "direction": "DESCENDING"}],
        "limit": 10,
    }}


def update(room_id, uid, **fields):
    """Directory update with lastActiveAt = request.time, like the app's writes."""
    return call("POST", f"{BASE}:commit", {"writes": [{
        "update": {"name": f"{DOC}/rooms/{room_id}", "fields": {k: value(v) for k, v in fields.items()}},
        "updateMask": {"fieldPaths": list(fields)},
        "updateTransforms": [{"fieldPath": "lastActiveAt", "setToServerValue": "REQUEST_TIME"}],
    }]}, uid=uid)


call("DELETE", BASE.replace("/v1/", "/emulator/v1/"), admin=True)  # clean slate
call("POST", f"{BASE}/rooms?documentId=pub", room("host", "public", "2026-01-01T00:00:00Z"), admin=True)
call("POST", f"{BASE}/rooms?documentId=priv", room("host", "private", "2026-01-02T00:00:00Z"), admin=True)

expect("host lists their own rooms, private ones included", call("POST", f"{BASE}:runQuery", by_host("host"), uid="host"))
expect("others cannot list someone's rooms (would leak private ones)",
       call("POST", f"{BASE}:runQuery", by_host("host"), uid="eve"), want=False)
expect("others can list someone's public rooms", call("POST", f"{BASE}:runQuery", by_host("host", public_only=True), uid="eve"))

expect("any member refreshes the directory (heartbeat)", update("pub", "eve", listenerCount=2, isLive=True))
expect("only the host can end a room", update("pub", "eve", closed=True, isLive=False, listenerCount=0), want=False)
expect("an ended room can't be shown live", update("pub", "host", closed=True, isLive=True, listenerCount=0), want=False)
expect("host ends their room", update("pub", "host", closed=True, isLive=False, listenerCount=0))
expect("an ended room stays ended", update("pub", "host", closed=False, isLive=True, listenerCount=1), want=False)
expect("a heartbeat can't revive an ended room", update("pub", "eve", isLive=True, listenerCount=1), want=False)

print()
if FAILURES:
    print(f"{len(FAILURES)} rule expectation(s) failed: {FAILURES}")
    sys.exit(1)
print("All Firestore rule expectations hold.")
