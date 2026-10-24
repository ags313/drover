# shellcheck shell=bash
# --- remote pulls: separate real repositories, no external network --------------------------
REAL_GIT=$(command -v git)
mkdir -p "$T/pull-bin"
cat > "$T/pull-bin/git" <<'G'
#!/usr/bin/env bash
for arg in "$@"; do
  case $arg in
    fetch|push) echo "$arg" >> "$PULL_CALLS" ;;
  esac
  if [ "$arg" = fetch ] && [ "${PULL_HANG_FETCH:-0}" = 1 ]; then
    printf '%s\n' "${GIT_TERMINAL_PROMPT:-unset}" > "$PULL_PROMPT"
    echo "$$" > "$PULL_FETCH_PID"
    # A descendant that survives its parent would write this marker after the deadline.
    (sleep 3; echo survived > "$PULL_SURVIVED") &
    wait
    exit 0
  fi
done
exec "$REAL_GIT" "$@"
G
chmod +x "$T/pull-bin/git"
export REAL_GIT PULL_CALLS="$T/pull-calls"
pull_setup(){
  local name=$1
  export DROVER_REPO="$T/pull-$name/local" FLEET_STATE="$T/pull-$name/state" FLEET_INBOX="$T/pull-$name/inbox"
  export DROVER_REMOTE=origin DROVER_MAIN_BRANCH=main
  mkdir -p "$T/pull-$name"
  git init -q --bare "$T/pull-$name/origin.git"
  git init -q -b main "$DROVER_REPO"
  git -C "$DROVER_REPO" config user.email eval@example.invalid
  git -C "$DROVER_REPO" config user.name eval
  mkdir -p "$DROVER_REPO/.beans"
  echo base > "$DROVER_REPO/file"
  echo board > "$DROVER_REPO/.beans/board.md"
  git -C "$DROVER_REPO" add .; git -C "$DROVER_REPO" commit -qm base
  git -C "$DROVER_REPO" remote add origin "$T/pull-$name/origin.git"
  git -C "$DROVER_REPO" push -q origin main
  git clone -q -b main "$T/pull-$name/origin.git" "$T/pull-$name/remote"
  remote_repo="$T/pull-$name/remote"
  git -C "$remote_repo" config user.email eval@example.invalid
  git -C "$remote_repo" config user.name eval
  : > "$PULL_CALLS"
}
remote_commit(){
  echo "remote $(git -C "$remote_repo" rev-list --count HEAD)" > "$remote_repo/$1"
  git -C "$remote_repo" add .; git -C "$remote_repo" commit -qm remote
  git -C "$remote_repo" push -q origin main
  remote_tip=$(git -C "$remote_repo" rev-parse HEAD)
}
pull_run(){ PATH="$T/pull-bin:$PATH" "$BIN/fleet" pull; }
pull_setup ff; remote_commit other
old=$(git -C "$DROVER_REPO" rev-parse HEAD)
out=$(pull_run)
[ "$(git -C "$DROVER_REPO" rev-parse HEAD)" = "$remote_tip" ] && [[ "$out" = *"PULL main $old..$remote_tip (1 commits)"* ]] \
  && ok 'pull: behind fast-forwards with commit count' || bad "pull ff: $out"
# New tip is deliberately absent from the local remote-tracking ref before fleet-push.
remote_commit another
out=$(PATH="$T/pull-bin:$PATH" FLEET_PUSH_FORCE=1 "$BIN/fleet-push"); rc=$?
[ "$rc" = 1 ] && [ "$out" = 'fleet-push: main is behind origin/main — run fleet pull' ] && ! grep -qx push "$PULL_CALLS" \
  && ok 'fleet-push: fetches and refuses behind main without a push attempt' || bad "push behind: $out"
pull_setup diverged; remote_commit other
echo local > "$DROVER_REPO/local"; git -C "$DROVER_REPO" add .; git -C "$DROVER_REPO" commit -qm local
local_tip=$(git -C "$DROVER_REPO" rev-parse HEAD)
out=$(pull_run)
[ "$(git -C "$DROVER_REPO" rev-parse HEAD^1)" = "$local_tip" ] && [ "$(git -C "$DROVER_REPO" rev-parse HEAD^2)" = "$remote_tip" ] \
  && [[ "$out" = *"PULL merged origin/main $remote_tip into main"* ]] && [ -f "$DROVER_REPO/local" ] && [ -f "$DROVER_REPO/other" ] \
  && ok 'pull: clean divergence creates a merge preserving both trees' || bad "pull divergence: $out"
pull_setup conflict; remote_commit file
echo local > "$DROVER_REPO/file"; git -C "$DROVER_REPO" commit -qam local
local_tip=$(git -C "$DROVER_REPO" rev-parse HEAD)
pull_run >/dev/null; pull_run >/dev/null
[ "$(git -C "$DROVER_REPO" rev-parse HEAD)" = "$local_tip" ] && [ -z "$(git -C "$DROVER_REPO" status --porcelain)" ] \
  && [ "$(grep -c 'PULL CONFLICT' "$FLEET_STATE/../watch.log")" = 1 ] && [ "$(find "$FLEET_INBOX" -name '*.note' | wc -l)" = 1 ] \
  && ok 'pull: conflict leaves main and tree untouched, logs and notes once per tip' || bad 'pull conflict rollback/dedup'
remote_commit file
pull_run >/dev/null
[ "$(grep -c 'PULL CONFLICT' "$FLEET_STATE/../watch.log")" = 2 ] && [ "$(find "$FLEET_INBOX" -name '*.note' | wc -l)" = 2 ] \
  && ok 'pull: a new conflicting remote tip gets a new notice' || bad 'pull conflict new tip notice'
pull_setup dirty; remote_commit other
old=$(git -C "$DROVER_REPO" rev-parse HEAD)
echo dirty > "$DROVER_REPO/file"
out=$(pull_run)
[ "$(git -C "$DROVER_REPO" rev-parse HEAD)" = "$old" ] && [ "$(cat "$DROVER_REPO/file")" = dirty ] && [[ "$out" = *'PULL skipped: dirty checkout (tracked changes)'* ]] \
  && ok 'pull: tracked dirt skips without changing main or file' || bad "pull dirty: $out"
git -C "$DROVER_REPO" add file
out=$(pull_run)
[ "$(git -C "$DROVER_REPO" rev-parse HEAD)" = "$old" ] && [[ "$out" = *'PULL skipped: dirty checkout (tracked changes)'* ]] \
  && ok 'pull: staged tracked dirt also skips' || bad "pull staged dirt: $out"
pull_setup beans; remote_commit other
echo updated > "$DROVER_REPO/.beans/board.md"
pull_run >/dev/null
[ "$(git -C "$DROVER_REPO" log -1 --format=%s HEAD^1)" = 'chore(beans): sync board state' ] \
  && [ "$(cat "$DROVER_REPO/.beans/board.md")" = updated ] && [ -z "$(git -C "$DROVER_REPO" status --porcelain)" ] \
  && git -C "$DROVER_REPO" merge-base --is-ancestor "$remote_tip" HEAD \
  && ok 'pull: bean-only dirt commits board state before merging' || bad 'pull bean-only changes'
pull_setup off; remote_commit other
PATH="$T/pull-bin:$PATH" DROVER_PULL_MIN=0 "$BIN/fleet-watch" pull >/dev/null
[ ! -s "$PULL_CALLS" ] && ok 'pull: DROVER_PULL_MIN=0 performs no fetch' || bad 'pull off fetched'
PATH="$T/pull-bin:$PATH" DROVER_PULL_MIN=15 "$BIN/fleet-watch" pull >/dev/null
PATH="$T/pull-bin:$PATH" DROVER_PULL_MIN=15 "$BIN/fleet-watch" pull >/dev/null
[ "$(grep -c '^fetch$' "$PULL_CALLS")" = 1 ] && ok 'pull: repeated watcher passes respect the interval' || bad 'pull interval fetched twice'
remote_commit new
PATH="$T/pull-bin:$PATH" DROVER_PULL_MIN=0 "$BIN/fleet" pull >/dev/null
[ "$(git -C "$DROVER_REPO" rev-parse HEAD)" = "$remote_tip" ] && ok 'pull: manual fleet pull works with periodic pulls off' || bad 'manual pull off'

# A fetch hung in credentials/network is bounded in both entry points and kills descendants.
pull_setup timeout; remote_commit other
export PULL_PROMPT="$T/pull-prompt" PULL_FETCH_PID="$T/pull-fetch-pid" PULL_SURVIVED="$T/pull-survived"
old=$(git -C "$DROVER_REPO" rev-parse HEAD)
start=$SECONDS
out=$(PATH="$T/pull-bin:$PATH" PULL_HANG_FETCH=1 DROVER_FETCH_TIMEOUT_SEC=1 "$BIN/fleet-watch" pull); rc=$?
[ "$rc" = 1 ] && [ $((SECONDS-start)) -lt 5 ] && [ "$(cat "$PULL_PROMPT")" = 0 ] \
  && ! kill -0 "$(cat "$PULL_FETCH_PID")" 2>/dev/null && [ ! -d "$FLEET_STATE/.pull-lock" ] \
  && [ "$(git -C "$DROVER_REPO" rev-parse HEAD)" = "$old" ] && [[ "$out" = *'PULL fetch failed'* ]] \
  && ok 'pull: a stalled fetch times out without prompting and releases its lock' || bad "pull timeout: $out"
start=$SECONDS
out=$(PATH="$T/pull-bin:$PATH" PULL_HANG_FETCH=1 DROVER_FETCH_TIMEOUT_SEC=1 FLEET_PUSH_FORCE=1 "$BIN/fleet-push"); rc=$?
[ "$rc" = 1 ] && [ $((SECONDS-start)) -lt 5 ] && [ "$(cat "$PULL_PROMPT")" = 0 ] \
  && ! kill -0 "$(cat "$PULL_FETCH_PID")" 2>/dev/null && ! grep -qx push "$PULL_CALLS" \
  && [[ "$out" = *'fleet-push: fetch failed'* ]] \
  && ok 'fleet-push: stalled fetch times out without prompting, gating, or pushing' || bad "push timeout: $out"
sleep 3
[ ! -e "$PULL_SURVIVED" ] && ok 'fetch timeout kills credential/network descendants too' || bad 'fetch timeout leaked descendants'
# A transient timeout does not poison future pulls.
pull_run >/dev/null
[ "$(git -C "$DROVER_REPO" rev-parse HEAD)" = "$remote_tip" ] && ok 'pull: fetch succeeds after a timeout' || bad 'pull timeout left a permanent lock'

# Simulate process death and the acquisition window before an owner writes its pid.
sh -c 'exit 0' & pull_dead=$!; wait "$pull_dead"
pull_setup locks; remote_commit other
mkdir -p "$FLEET_STATE/.pull-lock"
echo "$pull_dead" > "$FLEET_STATE/.pull-lock/pid"
out=$(pull_run)
[ "$(git -C "$DROVER_REPO" rev-parse HEAD)" = "$remote_tip" ] && [ ! -d "$FLEET_STATE/.pull-lock" ] \
  && [[ "$out" = *'PULL cleared stale pull lock'* ]] \
  && ok 'pull: dead owner lock is reclaimed immediately' || bad "dead pull lock: $out"
remote_commit next
mkdir "$FLEET_STATE/.pull-lock"
touch -t 200001010000 "$FLEET_STATE/.pull-lock"
out=$(pull_run)
[ "$(git -C "$DROVER_REPO" rev-parse HEAD)" = "$remote_tip" ] && [[ "$out" = *'PULL cleared stale pull lock'* ]] \
  && ok 'pull: aged ownerless lock is reclaimed' || bad "ownerless pull lock: $out"
remote_commit live
old=$(git -C "$DROVER_REPO" rev-parse HEAD)
mkdir "$FLEET_STATE/.pull-lock"; echo "$$" > "$FLEET_STATE/.pull-lock/pid"
touch -t 200001010000 "$FLEET_STATE/.pull-lock"
out=$(pull_run)
[ "$(git -C "$DROVER_REPO" rev-parse HEAD)" = "$old" ] && [ "$(cat "$FLEET_STATE/.pull-lock/pid")" = "$$" ] \
  && [[ "$out" = *'PULL skipped: pull lock held'* ]] \
  && ok 'pull: even an aged live pull owner is kept with a skip log' || bad "live pull lock: $out"
rm -f "$FLEET_STATE/.pull-lock/pid"; rmdir "$FLEET_STATE/.pull-lock"
mkdir "$FLEET_STATE/.pull-lock"
out=$(pull_run)
[ -d "$FLEET_STATE/.pull-lock" ] && [[ "$out" = *'PULL skipped: pull lock held'* ]] \
  && ok 'pull: a fresh ownerless lock is kept with a skip log' || bad "fresh pull lock: $out"
rmdir "$FLEET_STATE/.pull-lock"

# Reclamation also runs without autoland, including the observer configuration.
mkdir "$FLEET_STATE/.push-lock"; echo "$pull_dead" > "$FLEET_STATE/.push-lock/pid"
: > "$FLEET_STATE/observer"
out=$(PATH="$T/pull-bin:$PATH" DROVER_AUTOLAND=0 "$BIN/fleet-watch" pull)
[ "$(git -C "$DROVER_REPO" rev-parse HEAD)" = "$remote_tip" ] && [ ! -d "$FLEET_STATE/.push-lock" ] \
  && [[ "$out" = *'PULL cleared stale push lock'* ]] \
  && ok 'pull: dead push owner is reclaimed with autoland off/observer configured' || bad "dead push lock: $out"
remote_commit pushlive
old=$(git -C "$DROVER_REPO" rev-parse HEAD)
mkdir "$FLEET_STATE/.push-lock"; echo "$$" > "$FLEET_STATE/.push-lock/pid"
touch -t 200001010000 "$FLEET_STATE/.push-lock"
out=$(pull_run)
[ "$(git -C "$DROVER_REPO" rev-parse HEAD)" = "$old" ] && [ "$(cat "$FLEET_STATE/.push-lock/pid")" = "$$" ] \
  && [[ "$out" = *'PULL skipped: push lock held'* ]] \
  && ok 'pull: live push owner is kept and the skip is logged' || bad "live push lock: $out"
rm -f "$FLEET_STATE/.push-lock/pid"
touch -t 200001010000 "$FLEET_STATE/.push-lock"
out=$(pull_run)
[ "$(git -C "$DROVER_REPO" rev-parse HEAD)" = "$remote_tip" ] && [ ! -d "$FLEET_STATE/.push-lock" ] \
  && [[ "$out" = *'PULL cleared stale push lock'* ]] \
  && ok 'pull: aged ownerless push lock is reclaimed' || bad "ownerless push lock: $out"
mkdir "$FLEET_STATE/.push-lock"
out=$(pull_run)
[ -d "$FLEET_STATE/.push-lock" ] && [[ "$out" = *'PULL skipped: push lock held'* ]] \
  && ok 'pull: fresh ownerless push lock is kept and logged' || bad "fresh push lock: $out"
rmdir "$FLEET_STATE/.push-lock"
