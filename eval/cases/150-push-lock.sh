# shellcheck shell=bash
# --- push lock: a push releases its lock, and a dead owner's lock never blocks a land ------------------------
# The lock dir holds a pid file, so the old `rmdir` never removed it; with nothing to push, auto_push returned
# before the stale-lock check and auto_land skipped every tick behind the lock (panel2, 2026-10-12).
cd "$DROVER_REPO" || exit 1
export FLEET_MIN_FREE_GB=0 FLEET_MAX_PROCS=1000000 DROVER_TEST_ALL=
PK="$FLEET_STATE/.push-lock"
sh -c 'exit 0' & dead=$!; wait "$dead"
lock(){ rm -rf "$PK"; mkdir -p "$PK"; echo "$1" > "$PK/pid"; }
lane(){ DROVER_BUILD=$1 "$BIN"/fleet-watch land-lane >/dev/null 2>&1; }
pushed(){ [ "$(git rev-parse main)" = "$(git rev-parse origin/main)" ]; }
# finish-first stops auto_land before its own stale-lock check, so the push cases see auto_push alone
: > "$FLEET_STATE/finish-first"
echo pl > src/pl.txt; git add src/pl.txt; git commit -qm 'feat: pl'
lock $$; lane true
[ -d "$PK" ] && ! pushed && ok 'push lane keeps a live owner lock and does not push' || bad "push lane live lock: lock=$([ -d "$PK" ] && echo kept || echo gone) pushed=$(pushed && echo yes || echo no)"
lock "$dead"; lane true
pushed && [ ! -e "$PK" ] && ok 'green push after a takeover leaves no lock' || bad "green push: pushed=$(pushed && echo yes || echo no) lock=$(ls -A "$PK" 2>/dev/null | tr '\n' ' ')$([ -e "$PK" ] || echo gone) $(tail -3 "$FLEET_STATE/auto-push-verify.log" 2>/dev/null | tr '\n' ' ')"
echo pl2 > src/pl.txt; git commit -qam 'feat: pl2'
lock "$dead"; lane false
[ -f "$FLEET_STATE/land-paused" ] && ! pushed && [ ! -e "$PK" ] && ok 'red push after a takeover leaves no lock' \
  || bad "red push: paused=$([ -f "$FLEET_STATE/land-paused" ] && echo yes || echo no) lock=$([ -e "$PK" ] && echo kept || echo gone)"
rm -f "$FLEET_STATE/land-paused" "$FLEET_STATE/push-backoff" "$FLEET_STATE/finish-first"; git push -q origin main; git fetch -q origin
# nothing to push, a dead owner's lock, one approved bean: the lock is cleared and the bean lands
git checkout -qb fleet/c1-bean-ll; echo ll > src/ll.txt; git add src/ll.txt; git commit -qm 'feat: ll (bean-ll)'; git checkout -q main
mkdir -p "$FLEET_STATE/approved"; : > "$FLEET_STATE/approved/bean-ll"
lock "$dead"; lane true
[ ! -e "$PK" ] && grep -q 'bean-ll' <<<"$(git log --format=%s main)" && ok 'a dead lock with nothing to push no longer blocks a land' \
  || bad "ahead-0 lock: lock=$([ -e "$PK" ] && echo kept || echo gone) landed=$(git log --format=%s main | grep -c bean-ll) $(grep -E 'push lock|AUTO-LAND' "$FLEET_STATE/../watch.log" 2>/dev/null | tail -2 | tr '\n' ' ')"
