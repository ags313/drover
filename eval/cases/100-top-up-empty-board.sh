# shellcheck shell=bash
# --- top-up on an empty board: `beans list --json --ready` prints null, not [] ------------------------------
# A copy of fleet-watch beside a stub `fleet` runs the tick's top-up step against a fresh beans project. Empty
# board -> no stderr, nothing queued. One ready bean -> queued.
mkdir -p "$T/qbin"; cp "$BIN"/fleet-watch "$BIN"/drover-env "$T/qbin/"
printf '#!/bin/sh\n[ "$1" = status ] && printf "NAME KIND STATE\\n"\nexit 0\n' > "$T/qbin/fleet"; chmod +x "$T/qbin/fleet"
git init -q -b main "$T/eb"; ( cd "$T/eb" && git config user.email e@x.invalid && git config user.name e && beans init >/dev/null && git add -A && git commit -qm init )
top_up(){ ( cd "$T/eb" && env -u DROVER_PROJECT DROVER_REPO="$T/eb" FLEET_QUEUE="$T/q" "$T/qbin/fleet-watch" top-up >/dev/null 2>"$T/q.err" ); }
top_up; rc=$?
[ "$rc" = 0 ] && [ ! -s "$T/q.err" ] && [ -z "$(ls "$T/q" 2>/dev/null)" ] \
  && ok 'top-up on an empty board: no stderr, nothing queued' || bad "top-up on an empty board (rc=$rc): $(head -c 300 "$T/q.err")"
( cd "$T/eb" && beans create 'one ready bean' -t task -s todo >/dev/null && git add -A && git commit -qm bean )
top_up; [ "$(ls "$T/q" 2>/dev/null | grep -c .)" = 1 ] && ok 'top-up queues a ready bean' || bad "top-up queued: $(ls "$T/q" 2>/dev/null | tr '\n' ' ') err: $(head -c 300 "$T/q.err")"
