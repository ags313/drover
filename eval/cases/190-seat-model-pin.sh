# shellcheck shell=bash
# --- per-seat model pin and lead-only seats (a local model behind opencode) --------------------------------------
# A stub herdr logs every call. `fleet up` (shared-tree mode) spawns one seat per kind: the per-seat pin
# (FLEET_MODEL_<seat>, else DROVER_SEAT_MODELS) beats the kind pin for claude/opencode/agy, and codex/cursor get none.
mkdir -p "$T/hbin"
cat > "$T/hbin/herdr" <<'STUB'
#!/usr/bin/env bash
echo "$*" >> "$HERDR_LOG"
case "$1 $2" in
  'agent list') printf '{"result":{"agents":%s}}\n' "${HERDR_AGENTS:-[]}" ;;
  'workspace list') echo '{"result":{"workspaces":[{"workspace_id":"w1","label":"fleet"}]}}' ;;
  'tab list') echo '{"result":{"tabs":[]}}' ;;
  'tab create') echo '{"result":{"root_pane":{"pane_id":"w1:p1"}}}' ;;
  'agent prompt') printf '{"result":{"agent":{"name":"%s","agent_status":"working"}}}\n' "$3" ;;
  'agent get') if [ -n "${HERDR_CWD:-}" ]; then printf '{"result":{"agent":{"cwd":"%s"}}}\n' "$HERDR_CWD"; else echo '{}'; fi ;;
esac
exit 0
STUB
chmod +x "$T/hbin/herdr"
hf(){ env -u DROVER_PROJECT FLEET_HERDR="$T/hbin/herdr" HERDR_LOG="$T/herdr.log" FLEET_WORKTREES=0 FLEET_NPROC_LIMIT=0 FLEET_ROOT="$T/eb" "$@"; }
: > "$T/herdr.log"
hf env FLEET='oc-coder:opencode qwen-coder:opencode cl-coder:claude cx-coder:codex cu-coder:cursor ag-coder:agy' \
  FLEET_OPENCODE_MODEL=kind-oc FLEET_MODEL_qwen_coder=ollama/qwen3-coder-next:q4_K_M FLEET_MODEL_cl_coder=seat-cl \
  FLEET_MODEL_cx_coder=seat-cx FLEET_MODEL_cu_coder=seat-cu DROVER_SEAT_MODELS='ag-coder=pair-ag' "$BIN"/fleet up >"$T/up.out" 2>&1
args_of(){ sed -n "s/^agent start $1 .* -- //p" "$T/herdr.log"; }
[ "$(args_of oc-coder)" = '--auto --model kind-oc' ] && [ "$(args_of qwen-coder)" = '--auto --model ollama/qwen3-coder-next:q4_K_M' ] \
  && ok 'fleet up: two opencode seats spawn on two models (kind pin, per-seat pin)' \
  || bad "opencode seats: oc='$(args_of oc-coder)' qwen='$(args_of qwen-coder)' up: $(head -c 300 "$T/up.out")"
[ "$(args_of cl-coder)" = '--dangerously-skip-permissions --model seat-cl' ] && [ "$(args_of ag-coder)" = '--dangerously-skip-permissions --model pair-ag' ] \
  && ok 'fleet up: per-seat pin for claude, DROVER_SEAT_MODELS pin for agy' || bad "claude/agy: cl='$(args_of cl-coder)' ag='$(args_of ag-coder)'"
[ "$(args_of cx-coder)" = '--dangerously-bypass-approvals-and-sandbox' ] && [ "$(args_of cu-coder)" = '--yolo --approve-mcps --trust' ] \
  && ok 'fleet up: codex and cursor seats ignore a per-seat pin' || bad "codex/cursor got a model: cx='$(args_of cx-coder)' cu='$(args_of cu-coder)'"
# DROVER_YOLO=0 drops only the approval bypass: the pinned seat still gets its model, an unpinned codex seat gets nothing
: > "$T/herdr.log"
hf env DROVER_YOLO=0 FLEET='qwen-coder:opencode cx-coder:codex cl-coder:claude' FLEET_MODEL_qwen_coder=ollama/qwen3-coder-next:q4_K_M \
  FLEET_CLAUDE_MODEL=kind-cl "$BIN"/fleet up >"$T/up.out" 2>&1
[ "$(args_of qwen-coder)" = '--model ollama/qwen3-coder-next:q4_K_M' ] && [ "$(args_of cl-coder)" = '--model kind-cl' ] \
  && grep -q '^agent start cx-coder ' "$T/herdr.log" && ! grep -q '^agent start cx-coder .* -- ' "$T/herdr.log" \
  && ok 'fleet up with DROVER_YOLO=0: model pins kept, no bypass flags' \
  || bad "DROVER_YOLO=0: qwen='$(args_of qwen-coder)' cl='$(args_of cl-coder)' cx: $(grep '^agent start cx-coder' "$T/herdr.log") up: $(head -c 300 "$T/up.out")"
# fleet status: a manual seat's TITLE says so; NAME/KIND/STATE are untouched for every parser
out=$(hf env FLEET='qwen-coder:opencode oc-coder:opencode' DROVER_MANUAL_SEATS=qwen-coder \
  HERDR_AGENTS='[{"name":"qwen-coder","agent":"opencode","agent_status":"idle","pane_id":"w1:p1","cwd":"/x/eb","terminal_title_stripped":"opencode"},{"name":"oc-coder","agent":"opencode","agent_status":"idle","pane_id":"w1:p2","cwd":"/x/eb","terminal_title_stripped":"opencode"}]' \
  "$BIN"/fleet status 2>&1)
awk '$1=="qwen-coder" && $3=="idle" && $6=="manual:" {f=1} END{exit !f}' <<<"$out" && ! awk '$1=="oc-coder" && /manual:/ {f=1} END{exit !f}' <<<"$out" \
  && ok 'fleet status marks only the manual seat, STATE column unchanged' || bad "status: $out"
# refill: the stub coder x-claude-coder is free and one bean is ready. Listed in DROVER_MANUAL_SEATS it gets no bean
# (the bean stays queued) but still gets a fix round queued for it; off the list the bean goes to it.
git init -q -b main "$T/mb"
( cd "$T/mb" && git config user.email e@x.invalid && git config user.name e && beans init >/dev/null \
  && beans create 'manual seat bean' -t task -s todo >/dev/null && git add -A && git commit -qm bean )
mid=$(ls "$T/mb/.beans" | sed -n 's/--.*//p' | head -1)
mpass(){ ( cd "$T/mb" && env -u DROVER_PROJECT DROVER_REPO="$T/mb" FLEET_QUEUE="$T/mq" FLEET_INBOX="$T/min" FLEET_TASKS="$T/mtasks" \
  FLEET_STATE="$T/mw/state" DISPATCHES="$T/mdispatches" "$@" "$T/dbin/fleet-watch" dispatch >/dev/null 2>"$T/m.err" ); }
mpass env DROVER_MANUAL_SEATS='qwen-coder x-claude-coder'; mpass env DROVER_MANUAL_SEATS='qwen-coder x-claude-coder'
[ ! -s "$T/mdispatches" ] && [ -n "$(ls "$T/mq" 2>/dev/null)" ] && ok 'refill: a free manual seat gets no bean over two passes; the bean stays queued' \
  || bad "manual refill: dispatches='$(cat "$T/mdispatches" 2>/dev/null)' queue='$(ls "$T/mq" 2>/dev/null)' $(grep -E 'SKIP|DISPATCH' "$T/mw/watch.log" 2>/dev/null | tail -2 | tr '\n' ' ')"
mkdir -p "$T/mw/state/followups"; printf 'x-zz99\t%s\n' "$T/mw/review.md" > "$T/mw/state/followups/x-claude-coder"
mpass env DROVER_MANUAL_SEATS=x-claude-coder
grep -q 'FOLLOWUP x-zz99 -> x-claude-coder' "$T/mw/watch.log" 2>/dev/null && [ ! -s "$T/mdispatches" ] \
  && ok 'refill: a manual seat still gets the fix round of a bean it holds' || bad "manual followup: $(grep -E 'FOLLOWUP|DISPATCH' "$T/mw/watch.log" 2>/dev/null | tail -2 | tr '\n' ' ')"
rm -f "$T/mtasks/x-claude-coder"; mpass env
[ "$(cat "$T/mdispatches" 2>/dev/null)" = "$mid" ] && ok 'refill: the same seat off DROVER_MANUAL_SEATS takes the bean' \
  || bad "non-manual refill: dispatches='$(cat "$T/mdispatches" 2>/dev/null)' $(grep -E 'SKIP|DISPATCH' "$T/mw/watch.log" 2>/dev/null | tail -2 | tr '\n' ' ')"
# seat:<name> routing: rb holds one bean tagged seat:x-qwen-coder (the manual seat), one untagged and one tagged
# with a seat off the roster. A stub `fleet` lists x-claude-coder and x-qwen-coder; the real fleet-track records the
# dispatch. A seat with a task file is busy.
mkdir -p "$T/rbin"; cp "$BIN"/fleet-watch "$BIN"/fleet-track "$BIN"/fleet-ghost-reap "$BIN"/fleet-unblock "$BIN"/drover-env "$T/rbin/"
cat > "$T/rbin/fleet" <<'STUB'
#!/usr/bin/env bash
case $1 in
  status) printf 'NAME KIND STATE\nx-claude-coder claude idle\nx-qwen-coder opencode idle\n' ;;
  assign) echo "$2 $3" >> "$DISPATCHES"; echo "$3 <- $2: working" ;;
esac
exit 0
STUB
chmod +x "$T/rbin/fleet"
git init -q -b main "$T/rb"
( cd "$T/rb" && git config user.email e@x.invalid && git config user.name e && beans init >/dev/null \
  && beans create 'for qwen' -t task -s todo --tag seat:x-qwen-coder >/dev/null && beans create 'for anyone' -t task -s todo >/dev/null \
  && beans create 'for a ghost' -t task -s todo --tag seat:nobody-coder >/dev/null && git add -A && git commit -qm beans )
rq=$(cd "$T/rb" && beans list --json | python3 -c 'import json,sys; print({b["title"]: b["id"] for b in json.load(sys.stdin)}["for qwen"])')
ra=$(cd "$T/rb" && beans list --json | python3 -c 'import json,sys; print({b["title"]: b["id"] for b in json.load(sys.stdin)}["for anyone"])')
rg=$(cd "$T/rb" && beans list --json | python3 -c 'import json,sys; print({b["title"]: b["id"] for b in json.load(sys.stdin)}["for a ghost"])')
renv(){ ( cd "$T/rb" && env -u DROVER_PROJECT DROVER_REPO="$T/rb" FLEET_QUEUE="$T/rq" FLEET_INBOX="$T/rin" FLEET_TASKS="$T/rtasks" \
  FLEET_STATE="$T/rw/state" FLEET_REPORTS="$T/rreports" DISPATCHES="$T/rdispatches" DROVER_MANUAL_SEATS=x-qwen-coder "$@" ); }
rpass(){ renv "$T/rbin/fleet-watch" dispatch >/dev/null 2>>"$T/r.err"; }
rlog(){ grep -E 'SKIP|DISPATCH|QUEUE|REROUTE|queue empty' "$T/rw/watch.log" 2>/dev/null | tail -4 | tr '\n' ' '; }
mkdir -p "$T/rtasks"; printf '%s\t%s\t%s\t%s\n' 0 x-busy - - > "$T/rtasks/x-qwen-coder"   # the manual seat is busy
rpass
[ "$(cat "$T/rdispatches" 2>/dev/null)" = "$ra x-claude-coder" ] && [ "$(cat "$T/rq/"*"-$rq" 2>/dev/null)" = x-qwen-coder ] \
  && ok 'seat routing: the free automatic seat takes the untagged bean, never the one tagged for the busy manual seat' \
  || bad "routing pass 1: dispatches='$(tr '\n' '|' < "$T/rdispatches" 2>/dev/null)' queue='$(renv "$T/rbin/fleet-watch" queue | tr '\n' '|')' $(rlog)"
! compgen -G "$T/rq/*-$rg" >/dev/null && [ "$(grep -c "SKIP $rg — tagged seat:nobody-coder, which is not on the roster" "$T/rw/watch.log")" = 1 ] \
  && ok 'seat routing: a tag naming a seat off the roster is logged once and left out of the queue' || bad "ghost seat: queue='$(ls "$T/rq" | tr '\n' ' ')' $(rlog)"
out=$(hf env FLEET='x-qwen-coder:opencode' DROVER_MANUAL_SEATS=x-qwen-coder FLEET_QUEUE="$T/rq" \
  HERDR_AGENTS='[{"name":"x-qwen-coder","agent":"opencode","agent_status":"idle","pane_id":"w1:p1","cwd":"/x/rb","terminal_title_stripped":"opencode"}]' \
  "$BIN"/fleet status 2>&1)
awk -v b="$rq" '$1=="x-qwen-coder" && $3=="idle" && $6=="manual:" && $7=="waiting" && $8==b {f=1} END{exit !f}' <<<"$out" \
  && ok 'fleet status: the manual seat shows "manual: waiting <bean>" for its queued tagged bean' || bad "status waiting: $out"
# Finish the plain bean before freeing its seat, so it is no longer ready for another top-up.
( cd "$T/rb" && beans update "$ra" -s completed >/dev/null && git add -A && git commit -qm 'done plain bean' )
rm -f "$T/rtasks/x-claude-coder"; rpass
[ "$(wc -l < "$T/rdispatches")" = 1 ] && compgen -G "$T/rq/*-$rq" >/dev/null && grep -q 'queue empty but for seat-routed beans — nothing for x-claude-coder' "$T/rw/watch.log" \
  && ok 'seat routing: a second free automatic seat pass still leaves the tagged bean queued' \
  || bad "routing pass 2: dispatches='$(tr '\n' '|' < "$T/rdispatches")' $(rlog)"
rm -f "$T/rtasks/x-claude-coder" "$T/rtasks/x-qwen-coder"; rpass
[ "$(sed -n 2p "$T/rdispatches")" = "$rq x-qwen-coder" ] && [ "$(wc -l < "$T/rdispatches")" = 2 ] && [ "$(cut -f2 "$T/rtasks/x-qwen-coder" 2>/dev/null)" = "$rq" ] \
  && [ -z "$(ls "$T/rq")" ] && ok 'seat routing: the tagged bean goes to its manual seat on the first pass it is free; fleet-track holds it on that seat' \
  || bad "routing pass 3: dispatches='$(tr '\n' '|' < "$T/rdispatches")' task='$(cat "$T/rtasks/x-qwen-coder" 2>/dev/null)' queue='$(ls "$T/rq")' $(rlog)"
# a hand-enqueued entry (no route) for a tagged bean: with the repo off main top-up stands down, so refill pops the
# stale entry and the pop-time tag check drops it; back on main, top-up re-routes the entry itself
rid(){ (cd "$T/rb" && beans list --json | T="$1" python3 -c 'import json,os,sys; print({b["title"]: b["id"] for b in json.load(sys.stdin)}[os.environ["T"]])'); }
rtag(){ ( cd "$T/rb" && beans update "$1" "${@:2}" >/dev/null && git add -A && git commit -qm "tag $1" ); }
rroute(){ cat "$T/rq/"*"-$1" 2>/dev/null; }
rdone(){ for b in "$@"; do (cd "$T/rb" && beans update "$b" -s completed >/dev/null && git add -A && git commit -qm "done $b"); done; }
rdone "$ra" "$rq"; rm -f "$T/rtasks/"*; : > "$T/rdispatches"; : > "$T/rtasks/x-qwen-coder"
( cd "$T/rb" && beans create 'for qwen too' -t task -s todo --tag seat:x-qwen-coder >/dev/null && git add -A && git commit -qm bean2 )
rq2=$(rid 'for qwen too')
git -C "$T/rb" checkout -q -b side; renv "$T/rbin/fleet-watch" enqueue "$rq2" >/dev/null; rpass; git -C "$T/rb" checkout -q main
[ ! -s "$T/rdispatches" ] && grep -q "SKIP $rq2 — routed to 'any seat' in the queue but tagged 'seat:x-qwen-coder'" "$T/rw/watch.log" \
  && ok 'seat routing: an unrouted queue entry for a tagged bean is dropped at pop time, not dispatched elsewhere' \
  || bad "hand-queued tagged bean: dispatches='$(tr '\n' '|' < "$T/rdispatches")' $(rlog)"
renv "$T/rbin/fleet-watch" enqueue "$rq2" >/dev/null; rpass
[ ! -s "$T/rdispatches" ] && [ "$(rroute "$rq2")" = x-qwen-coder ] && grep -q "REROUTE $rq2 — queued for 'any seat', now 'x-qwen-coder'" "$T/rw/watch.log" \
  && ok 'seat routing: top-up re-routes an unrouted entry for a tagged bean to its seat' \
  || bad "re-route hand-queued: dispatches='$(tr '\n' '|' < "$T/rdispatches")' route='$(rroute "$rq2")' $(rlog)"
# A routed bean waiting for its busy manual seat never gates plain top-up. A queued plain bean still does.
( cd "$T/rb" && beans create 'plain while routed waits' -t task -s todo >/dev/null && git add -A && git commit -qm plain1 )
rp1=$(rid 'plain while routed waits'); renv "$T/rbin/fleet-watch" top-up >/dev/null 2>>"$T/r.err"
compgen -G "$T/rq/*-$rp1" >/dev/null && [ "$(rroute "$rq2")" = x-qwen-coder ] \
  && ok 'seat routing: a routed-only queue admits a ready plain bean while the manual seat is busy' \
  || bad "plain top-up: queue='$(ls "$T/rq")' $(rlog)"
( cd "$T/rb" && beans create 'plain on next tick' -t task -s todo >/dev/null && git add -A && git commit -qm plain2 )
rp2=$(rid 'plain on next tick'); renv "$T/rbin/fleet-watch" top-up >/dev/null 2>>"$T/r.err"
! compgen -G "$T/rq/*-$rp2" >/dev/null && compgen -G "$T/rq/*-$rp1" >/dev/null \
  && ok 'seat routing: an existing plain queue entry still gates further plain top-up' \
  || bad "plain queue gate: queue='$(ls "$T/rq")' $(rlog)"
rpass
[ "$(cat "$T/rdispatches")" = "$rp1 x-claude-coder" ] && [ "$(rroute "$rq2")" = x-qwen-coder ] \
  && ok 'seat routing: the idle automatic coder dispatches the plain bean while the routed bean waits' \
  || bad "plain dispatch: dispatches='$(cat "$T/rdispatches")' $(rlog)"
rdone "$rp1"; rm -f "$T/rtasks/x-claude-coder"; rpass
[ "$(sed -n 2p "$T/rdispatches")" = "$rp2 x-claude-coder" ] && [ "$(wc -l < "$T/rdispatches")" = 2 ] \
  && [ "$(rroute "$rq2")" = x-qwen-coder ] && [ -f "$T/rtasks/x-qwen-coder" ] \
  && ok 'seat routing: the next tick tops up and dispatches another plain bean while the manual seat stays busy' \
  || bad "next tick plain dispatch: dispatches='$(cat "$T/rdispatches")' $(rlog)"
rdone "$rp2"; rm -f "$T/rtasks/x-claude-coder"; : > "$T/rdispatches"
# retag while the old seat stays busy: top-up queued the bean for x-qwen-coder; it moves to the newly named idle seat
rdone "$rq2"; rm -f "$T/rq/"*
( cd "$T/rb" && beans create 'retag me' -t task -s todo --tag seat:x-qwen-coder >/dev/null && git add -A && git commit -qm bean5 )
rq5=$(rid 'retag me'); rpass
[ ! -s "$T/rdispatches" ] && [ "$(rroute "$rq5")" = x-qwen-coder ] || bad "retag setup: dispatches='$(tr '\n' '|' < "$T/rdispatches")' route='$(rroute "$rq5")' $(rlog)"
rtag "$rq5" --remove-tag seat:x-qwen-coder --tag seat:x-claude-coder; rpass
[ "$(cat "$T/rdispatches")" = "$rq5 x-claude-coder" ] && [ -f "$T/rtasks/x-qwen-coder" ] && [ -z "$(ls "$T/rq")" ] \
  && ok 'seat routing: retagged to an idle seat while the old seat is busy -> dispatched to the new seat on the next pass' \
  || bad "retag busy->idle: dispatches='$(tr '\n' '|' < "$T/rdispatches")' queue='$(renv "$T/rbin/fleet-watch" queue | tr '\n' '|')' $(rlog)"
# tag removed while queued for the busy manual seat: the bean is free for any automatic seat
rdone "$rq5"; rm -f "$T/rtasks/x-claude-coder"; : > "$T/rdispatches"
( cd "$T/rb" && beans create 'untag me' -t task -s todo --tag seat:x-qwen-coder >/dev/null && git add -A && git commit -qm bean3 )
rq3=$(rid 'untag me'); rpass
[ ! -s "$T/rdispatches" ] && [ "$(rroute "$rq3")" = x-qwen-coder ] || bad "untag setup: dispatches='$(tr '\n' '|' < "$T/rdispatches")' route='$(rroute "$rq3")' $(rlog)"
rtag "$rq3" --remove-tag seat:x-qwen-coder; rpass
[ "$(cat "$T/rdispatches")" = "$rq3 x-claude-coder" ] && ok 'seat routing: a tag removed while queued -> the next free automatic seat takes the bean' \
  || bad "untag: dispatches='$(tr '\n' '|' < "$T/rdispatches")' $(rlog)"
# retagged to a seat off the roster: the queue entry is removed and logged, nothing is dispatched
rdone "$rq3"; rm -f "$T/rtasks/x-claude-coder"; : > "$T/rdispatches"
( cd "$T/rb" && beans create 'ghost me' -t task -s todo --tag seat:x-qwen-coder >/dev/null && git add -A && git commit -qm bean4 )
rq4=$(rid 'ghost me'); rpass
rtag "$rq4" --remove-tag seat:x-qwen-coder --tag seat:gone-coder; rpass
[ ! -s "$T/rdispatches" ] && [ -z "$(rroute "$rq4")" ] && ! compgen -G "$T/rq/*-$rq4" >/dev/null \
  && grep -q "SKIP $rq4 — tagged seat:gone-coder, which is not on the roster; left out of the queue" "$T/rw/watch.log" \
  && ok 'seat routing: retagged off the roster -> the queued entry is removed and logged, no dispatch' \
  || bad "retag off-roster: dispatches='$(tr '\n' '|' < "$T/rdispatches")' queue='$(ls "$T/rq")' $(rlog)"
# fleet assign: the lead hands a bean to the manual seat directly (x-ab12 is on $DROVER_REPO's main)
: > "$T/herdr.log"
out=$(cd "$DROVER_REPO" && hf env FLEET_ROOT="$DROVER_REPO" FLEET='qwen-coder:opencode' DROVER_MANUAL_SEATS=qwen-coder FLEET_BRIEFS="$T/home/briefs" \
  "$BIN"/fleet assign x-ab12 qwen-coder 2>&1); rc=$?
[ "$rc" = 0 ] && grep -q '^agent prompt qwen-coder New bean: .* x-ab12' "$T/herdr.log" && [ -f "$T/home/briefs/assign-qwen-coder-x-ab12.txt" ] \
  && ok 'fleet assign <bean> <manual seat> dispatches to it' || bad "assign to a manual seat (rc=$rc): $out herdr: $(grep 'agent prompt' "$T/herdr.log" | head -c 200)"
# land routing: an ownerless conflicted bean is never handed to a manual seat (the only live coder here)
# shellcheck disable=SC2154  # rl_reason is set in 070-route-land-conflicts.sh
printf '%s\n' "$rl_reason" > "$FLEET_STATE/needs-land/bean-mn"
python3 -c 'import os, sys, time; t = time.time() - 300; os.utime(sys.argv[1], (t, t))' "$FLEET_STATE/needs-land/bean-mn"
DROVER_MANUAL_SEATS=claude-coder FLEET_BRIEFS="$T/home/briefs" "$T/wbin/fleet-watch" route-land >/dev/null 2>&1
[ -e "$FLEET_STATE/needs-land/bean-mn" ] && ! grep -q '^bean-mn	' "$FLEET_STATE/followups/claude-coder" 2>/dev/null \
  && ok 'route-land never hands an ownerless conflict to a manual seat' || bad 'route-land routed a conflict to a manual seat'
rm -f "$FLEET_STATE/needs-land/bean-mn"

