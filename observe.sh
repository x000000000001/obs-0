#!/usr/bin/env bash

BASE="https://0-six-dun.vercel.app"
LOG="$(dirname "$0")/0/log.ndjson"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

_get() {
  /usr/bin/curl -sS -o "${TMP}/$1" -w "%{http_code}" "${BASE}/$2" 2>/dev/null || echo "000"
}

S_ROOT=$(_get root "")
S_WK=$(_get wk ".well-known/0")
S_STATE=$(_get state "api/0")
S_LLMS=$(_get llms "llms.txt")
S_ROBOTS=$(_get robots "robots.txt")
S_UNK=$(_get unk "x")

python3 - "$TMP" "$LOG" "$S_ROOT" "$S_WK" "$S_STATE" "$S_LLMS" "$S_ROBOTS" "$S_UNK" "$(date +%s)" << 'PYEOF'
import json, sys, hashlib

tmp, log, s_root, s_wk, s_state, s_llms, s_robots, s_unk, t = sys.argv[1:]

try:
    body = json.loads(open(f"{tmp}/state").read())
except Exception:
    body = None

ok = (
    s_root   == "200" and
    s_wk     == "200" and
    s_state  == "200" and
    s_llms   == "200" and
    s_robots == "200" and
    s_unk    == "404" and
    isinstance(body, list) and
    len(body) == 7
)

chain_mode = None
gap        = False
chain_ok   = None

if ok:
    version = body[0]
    epoch   = body[2]
    cur_h   = body[3]
    prev_h  = body[4]
    value   = body[5]
    prev_e  = body[6]

    chain_mode = "active" if version == 1 else "degraded"

    o = body[1] - body[2] * 3600
    if hashlib.sha256(f"{epoch}:{o}".encode()).hexdigest()[:8] != value:
        ok = False

if ok:
    history = {}
    try:
        with open(log) as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                eb = json.loads(line).get("body")
                if isinstance(eb, list) and len(eb) == 7 and eb[2] not in history:
                    history[eb[2]] = eb
    except (FileNotFoundError, json.JSONDecodeError):
        pass

    epoch  = body[2]
    cur_h  = body[3]
    prev_h = body[4]
    prev_e = body[6]

    if history and epoch < max(history.keys()):
        ok = False

    if ok and epoch in history and cur_h != history[epoch][3]:
        ok = False

    if ok and prev_e is not None and prev_h is not None:
        if prev_e in history:
            if prev_h == history[prev_e][3]:
                chain_ok = True
            else:
                chain_ok = False
                ok = False
        else:
            gap      = True
            chain_ok = None

entry = {
    "observed_at": int(t),
    "root":        int(s_root),
    "well_known":  int(s_wk),
    "state":       int(s_state),
    "llms":        int(s_llms),
    "robots":      int(s_robots),
    "unknown":     int(s_unk),
    "body":        body,
    "chain":       chain_mode,
    "gap":         gap,
    "chain_ok":    chain_ok,
    "ok":          ok,
}

with open(log, "a") as f:
    f.write(json.dumps(entry, separators=(",", ":")) + "\n")

print("0 ok" if ok else "0 fail")
PYEOF
