# shellcheck shell=bash
# --- BLOCKED parks the bean: top-up and refill stop handing it back every tick -------------------------------
# The one-bean board from the top-up case, a copy of fleet-watch + fleet-unblock beside a stub `fleet` whose
# only coder records each assign. The seat "answers" through the real fleet-done.
mkdir -p "$T/dbin"; cp "$BIN"/fleet-watch "$BIN"/fleet-unblock "$BIN"/fleet-ghost-reap "$BIN"/drover-env "$T/dbin/"
cat > "$T/dbin/fleet" <<'STUB'
#!/usr/bin/env bash
case $1 in
  status) printf 'NAME KIND STATE\nx-claude-coder claude idle\n' ;;
  assign) echo "$2" >> "$DISPATCHES"; printf '%s\t%s\n' "$(date +%s)" "$2" > "$FLEET_TASKS/$3"; echo "$3 <- $2: working" ;;
esac
exit 0
STUB
chmod +x "$T/dbin/fleet"
bid=$(ls "$T/eb/.beans" | sed -n 's/--.*//p' | head -1)
denv(){ ( cd "$T/eb" && env -u DROVER_PROJECT DROVER_REPO="$T/eb" FLEET_QUEUE="$T/dq" FLEET_INBOX="$T/din" FLEET_TASKS="$T/dtasks" \
  FLEET_STATE="$T/dw/state" DISPATCHES="$T/dispatches" "$@" ); }
dpass(){ denv "$T/dbin/fleet-watch" dispatch >/dev/null 2>>"$T/d.err"; }
nd(){ if [ -f "$T/dispatches" ]; then wc -l < "$T/dispatches" | tr -d ' '; else echo 0; fi; }
answer(){ denv "$BIN"/fleet-done x-claude-coder "$bid" BLOCKED "$1" "$T/d-report.md" >/dev/null 2>&1; }
dstate(){ echo "dispatches=$(nd) parked='$(cat "$T/dw/state/parked/$bid" 2>/dev/null)' queue='$(ls "$T/dq" 2>/dev/null | tr '\n' ' ')' $(grep -E 'SKIP|UNPARK|BLOCKED' "$T/dw/watch.log" 2>/dev/null | tail -2 | tr '\n' ' ')"; }
dpass
[ "$(nd)" = 1 ] && ok "dispatch pass hands the ready bean to the free coder" || bad "first dispatch: $(dstate) err: $(head -c 300 "$T/d.err")"
answer 'HUMAN: needs a live account'; dpass; dpass
[ "$(nd)" = 1 ] && [ -f "$T/dw/state/parked/$bid" ] && ok 'a BLOCKED bean is dispatched once over two passes, not every pass' || bad "BLOCKED re-dispatch: $(dstate)"
out=$(denv "$T/dbin/fleet-watch" unpark "$bid"); rc=$?; dpass
[ "$rc" = 0 ] && [ "$(nd)" = 2 ] && ok 'fleet-watch unpark re-queues it: a second dispatch' || bad "unpark (rc=$rc, $out): $(dstate)"
denv "$T/dbin/fleet-watch" unpark "$bid" >/dev/null; rc=$?
[ "$rc" = 1 ] && [ -z "$(ls "$T/dq" 2>/dev/null)" ] && ok 'unpark of a bean that is not parked: exit 1, nothing queued' || bad "unpark not-parked rc=$rc queue=$(ls "$T/dq" 2>/dev/null)"
answer 'HUMAN: needs a live account'; dpass
grep -q '^REPEAT ' "$T/dw/state/parked/$bid" 2>/dev/null && [ "$(nd)" = 2 ] && ok 'the same BLOCKED reason twice -> a REPEAT park' || bad "repeat park: $(dstate)"
denv "$T/dbin/fleet-unblock" >/dev/null 2>&1; dpass
[ "$(nd)" = 2 ] && [ -f "$T/dw/state/parked/$bid" ] && grep -q "^$bid	" "$T/dw/state/human-decisions" 2>/dev/null \
  && ok 'unblock digests a HUMAN park and keeps it parked' || bad "unblock HUMAN: $(dstate) human='$(cat "$T/dw/state/human-decisions" 2>/dev/null)'"
# heal-drift restores bean files (same content, new mtime); the beans CLI bumps updated_at: neither is an answer
python3 -c 'import os, re, sys, time; p = sys.argv[1]; s = open(p).read(); open(p, "w").write(re.sub(r"(?m)^updated_at:.*$", "updated_at: 2099-01-01T00:00:00Z", s)); t = time.time() + 60; os.utime(p, (t, t))' "$T/eb/.beans/$bid"--*.md; dpass
[ "$(nd)" = 2 ] && [ -f "$T/dw/state/parked/$bid" ] && ok 'an mtime/updated_at-only rewrite of the bean keeps the park' || bad "mtime-only rewrite lifted the park: $(dstate)"
printf '\nLead: the account exists now, go ahead.\n' >> "$(ls "$T/eb/.beans/$bid"--*.md)"; dpass
[ "$(nd)" = 3 ] && [ ! -e "$T/dw/state/parked/$bid" ] && ok 'an edit to the bean content lifts the park' || bad "bean edit: $(dstate)"
rm -f "$T/dw/state/human-decisions"
answer 'flaky suite, could not tell'; dpass; denv "$T/dbin/fleet-unblock" >"$T/u.out" 2>&1; dpass
[ "$(nd)" = 4 ] && [ ! -e "$T/dw/state/parked/$bid" ] && ok 'unblock re-dispatches an actionable park' || bad "unblock actionable: $(dstate) unblock: $(grep -E 'RE-DISPATCH|LEAD|HUMAN' "$T/u.out" | head -2 | tr '\n' ' ')"
answer 'flaky suite, could not tell'; dpass; denv "$T/dbin/fleet-unblock" >"$T/u.out" 2>&1; dpass
[ "$(nd)" = 4 ] && [ -f "$T/dw/state/parked/$bid" ] && grep -q "^$bid	blocked twice with the same reason" "$T/dw/state/lead-decisions" 2>/dev/null \
  && ok 'unblock hands a REPEAT park to the lead, no re-dispatch' || bad "unblock repeat: $(dstate) unblock: $(grep -E 'RE-DISPATCH|LEAD|HUMAN' "$T/u.out" | head -2 | tr '\n' ' ') lead='$(cat "$T/dw/state/lead-decisions" 2>/dev/null)'"

# the ghost reaper must not "rescue" a parked in-progress bean: its reset to todo rewrote the bean file, and that
# rewrite lifted the park and re-queued blocked work (review of drover-3lof). HUMAN park, then REPEAT park.
denv "$T/dbin/fleet-watch" unpark "$bid" >/dev/null; dpass
( cd "$T/eb" && beans update "$bid" -s in-progress >/dev/null && git add -A && git commit -qm 'chore(beans): in progress' )
reap(){ denv env DROVER_GHOST_GRACE_MIN=0 "$T/dbin/fleet-ghost-reap" >"$T/g.out" 2>&1; dpass; }
bst(){ ( cd "$T/eb" && beans show "$bid" --json 2>/dev/null | python3 -c 'import sys, json; d = json.load(sys.stdin); print((d.get("bean") or d).get("status"))' ); }
answer 'HUMAN: needs prod credentials'; dpass; reap
[ "$(nd)" = 5 ] && [ -f "$T/dw/state/parked/$bid" ] && [ "$(bst)" = in-progress ] && [ -z "$(ls "$T/dq" 2>/dev/null)" ] \
  && ok 'ghost-reap leaves a parked (HUMAN) in-progress bean alone; nothing re-queued' || bad "ghost-reap HUMAN park: status=$(bst) $(dstate) reap: $(head -c 200 "$T/g.out")"
answer 'HUMAN: needs prod credentials'; dpass; reap
grep -q '^REPEAT ' "$T/dw/state/parked/$bid" 2>/dev/null && [ "$(nd)" = 5 ] && [ "$(bst)" = in-progress ] \
  && ok 'ghost-reap leaves a REPEAT park alone' || bad "ghost-reap REPEAT park: status=$(bst) $(dstate) reap: $(head -c 200 "$T/g.out")"

