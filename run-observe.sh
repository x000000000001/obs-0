#!/usr/bin/env bash

REPO="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO"

# macOS cron no hereda el SSH agent; intentar socket de launchd
if [[ -z "$SSH_AUTH_SOCK" ]]; then
  SOCK=$(ls /private/tmp/com.apple.launchd.*/Listeners 2>/dev/null | head -1)
  [[ -n "$SOCK" ]] && export SSH_AUTH_SOCK="$SOCK"
fi

./observe.sh

LAST=$(tail -n 1 0/log.ndjson 2>/dev/null)
[[ -z "$LAST" ]] && exit 0

EPOCH=$(python3 -c "import json,sys; b=json.loads(sys.stdin.read()).get('body'); print(b[2] if isinstance(b,list) and len(b)>2 else 'x')" <<< "$LAST" 2>/dev/null || echo "x")
STATUS=$(python3 -c "import json,sys; print('ok' if json.loads(sys.stdin.read()).get('ok') else 'fail')" <<< "$LAST" 2>/dev/null || echo "fail")

git add 0/log.ndjson
git diff --cached --quiet && exit 0
git commit -m "${EPOCH}:${STATUS}"
git push origin main
