# shellcheck shell=bash
# --- push batching: auto_push starts the verify+push only for a big enough or old enough batch ----------------
# A copy of fleet-watch beside a stub verify (green, counts its calls) and a stub fleet-slot (runs the command).
cd "$DROVER_REPO" || exit 1
git checkout -q main; git push -q origin main; git fetch -q origin
mkdir -p "$T/abin"; cp "$BIN"/fleet-watch "$BIN"/drover-env "$T/abin/"
printf '#!/usr/bin/env bash\necho x >> "%s"\n' "$T/verify.calls" > "$T/abin/fleet-verify-main"
printf '#!/usr/bin/env bash\nwhile [ "$1" != -- ]; do shift; done; shift; exec "$@"\n' > "$T/abin/fleet-slot"
chmod +x "$T/abin/fleet-verify-main" "$T/abin/fleet-slot"
rm -f "$FLEET_STATE/land-paused" "$FLEET_STATE/push-backoff"; rm -rf "$FLEET_STATE/.push-lock" "$FLEET_STATE/.land-lock"
n_pb=0
pb_commit(){ n_pb=$((n_pb+1)); echo "$n_pb" > src/pb.txt; git add src/pb.txt; GIT_COMMITTER_DATE="${1:-}" git commit -qm "feat: pb $n_pb"; }
pb_push(){ : > "$T/verify.calls"; FLEET_MIN_FREE_GB=0 FLEET_MAX_PROCS=1000000 "$T/abin/fleet-watch" auto-push >/dev/null 2>&1; }
pb_ahead(){ git rev-list --count origin/main..main; }
pb_commit; pb_push
[ "$(pb_ahead)" = 0 ] && ok 'push batching off by default: 1 ahead is pushed' || bad "default: $(pb_ahead) ahead, verify calls $(wc -l < "$T/verify.calls")"
export DROVER_PUSH_MIN_AHEAD=3
pb_commit; pb_commit; pb_push
[ "$(pb_ahead)" = 2 ] && [ ! -s "$T/verify.calls" ] && ok 'MIN_AHEAD=3: 2 ahead starts no verify, no push' || bad "2 ahead: $(pb_ahead) ahead after the pass, verify calls $(wc -l < "$T/verify.calls")"
pb_commit; pb_push
[ "$(pb_ahead)" = 0 ] && ok 'MIN_AHEAD=3: 3 ahead is pushed' || bad "3 ahead: $(pb_ahead) ahead after the pass"
export DROVER_PUSH_MAX_WAIT_MIN=60
pb_commit; pb_push
[ "$(pb_ahead)" = 1 ] && [ ! -s "$T/verify.calls" ] && ok 'MAX_WAIT=60: a fresh single commit waits' || bad "fresh 1 ahead: $(pb_ahead) ahead, verify calls $(wc -l < "$T/verify.calls")"
git reset -q --hard origin/main; pb_commit "$(date -d '2 hours ago' -R 2>/dev/null || date -v-2H -R)"; pb_push
[ "$(pb_ahead)" = 0 ] && ok 'MAX_WAIT=60: 1 ahead older than 60 min is pushed' || bad "old 1 ahead: $(pb_ahead) ahead after the pass"
# five lands through the real fleet-land-bean, the watcher's push pass after each: one verify, one push
export DROVER_PUSH_MIN_AHEAD=5 DROVER_PUSH_MAX_WAIT_MIN=0
git reset -q --hard origin/main; : > "$T/verify.calls"; five=""
for i in 1 2 3 4 5; do
  git checkout -qb "fleet/c1-bean-f$i"; echo "$i" > "src/f$i.txt"; git add "src/f$i.txt"; git commit -qm "feat: f$i (bean-f$i)"; git checkout -q main
  "$BIN"/fleet-land-bean "bean-f$i" 2>&1 | grep -q "^LANDED bean-f$i" || five="$five land$i-failed"
  FLEET_MIN_FREE_GB=0 FLEET_MAX_PROCS=1000000 "$T/abin/fleet-watch" auto-push >/dev/null 2>&1
  five="$five $(pb_ahead)"
done
[ "$five" = " 1 2 3 4 0" ] && [ "$(wc -l < "$T/verify.calls")" = 1 ] && ok 'MIN_AHEAD=5: five lands make one push' \
  || bad "five lands: ahead after each pass:$five, verify calls $(wc -l < "$T/verify.calls")"
unset DROVER_PUSH_MIN_AHEAD DROVER_PUSH_MAX_WAIT_MIN

