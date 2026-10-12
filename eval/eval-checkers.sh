#!/usr/bin/env bash
# eval-checkers — known-good and known-bad cases for the deterministic checkers, on a scratch repo.
#
# Every instrument ships with a case it must fire on AND a case it must stay quiet on (docs/LESSONS.md):
#   fleet-landed-check   completed bean with no landed code -> UNPROVEN; landed by commit / by named SHA /
#                        `Landed: none` -> quiet
#   fleet-review-check   a CLI banner with no review -> EMPTY; a grounded review, or a seat report whose name
#                        merely contains "reviewer" -> quiet
#   fleet-claim reap     a claim on a bean missing from main: under 24h kept, older released
#   fleet-slot           re-entry under FLEET_SLOT_HELD does not wait; a held general slot blocks a second run
#   route-land           fleet-land-bean's own conflict flag -> routed to a live coder, owner recorded; an env-failure
#                        flag, or a hand-off that cannot be written -> kept
#   fleet-budget         two cursor seats -> a `cursor 2` row; the grok row stays as it was
#   fleet rules          a fresh install would write cursor -> fires; right after install -> quiet
#   top-up               empty board (beans prints null) -> no stderr, nothing queued; one ready bean -> queued
#   bean ids             seats sharing the bean prefix (x-grok-coder, x-lead) -> not bean ids; a cited missing bean -> refused
#   fleet-land-bean      a branch whose merge of main resolves its conflicting commit -> LANDED as a squash;
#                        a branch whose net diff conflicts -> flagged, main unchanged
#   BLOCKED park         a seat answering BLOCKED -> one dispatch over two passes, not one per pass; unpark, a bean
#                        content edit, or an actionable unblock -> dispatched again; HUMAN or same-reason-twice, an
#                        mtime/updated_at-only rewrite, or a ghost-reap pass over a parked in-progress bean -> stays parked
#   gate seeding         verify-main and land-bean gates see a real node_modules (not a symlink); a failed copy
#                        falls back to a symlink
#   push lock            a dead owner's lock is gone after a green push, a red push, and a pass with nothing to
#                        push (the approved bean then lands); a live owner's lock is kept and nothing is pushed
#   push batching        defaults: 1 ahead -> push; DROVER_PUSH_MIN_AHEAD=3: 2 ahead -> no push, 3 -> push; 1 ahead
#                        older than DROVER_PUSH_MAX_WAIT_MIN -> push, a fresh one -> no push; MIN_AHEAD=5: five real
#                        fleet-land-bean lands with an auto-push pass after each -> exactly one verify+push
# No network, no keys. Exit 1 on the first wrong answer.
set -uo pipefail
BIN="$(cd "$(dirname "$0")/../bin" && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
# Hermetic git: a user's global config (commit.gpgsign with a key this shell cannot reach, hooks, templates)
# made every scratch commit fail and every case after it wrong.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export DROVER_CONFIG=/dev/null DROVER_HOME="$T/home" DROVER_REPO="$T/repo" FLEET_STATE="$T/home/state"
export FLEET_REPORTS="$T/home/reports" FLEET_TASKS="$T/home/tasks"
mkdir -p "$FLEET_STATE" "$FLEET_REPORTS" "$FLEET_TASKS"
fail=0
ok(){ echo "ok    $*"; }
bad(){ echo "FAIL  $*"; fail=1; }

# --- scratch repo with an origin -----------------------------------------------------------------------------
git init -q --bare "$T/origin.git"
git init -q -b main "$DROVER_REPO"; cd "$DROVER_REPO" || exit 1
git config user.email eval@example.invalid; git config user.name eval
mkdir -p .beans src
bean(){ printf -- '---\ntitle: %s\nstatus: %s\n---\n%s\n' "$1" "$2" "${3:-}" > ".beans/$1--t.md"; }
echo 1 > src/a.txt; git add -A; git commit -qm init
git remote add origin "$T/origin.git"; git push -q origin main
# bean-good1: completed in the same commit that changes code and names it
echo 2 > src/a.txt; bean bean-good1 completed; git add -A; git commit -qm 'fix: thing (bean-good1)'
# bean-good2: completed, body names a SHA that is on main
sha=$(git rev-parse --short HEAD); bean bean-good2 completed "Landed in $sha."; git add -A; git commit -qm 'chore(beans): close'
# bean-good3: completed with no code, declared
bean bean-good3 completed 'Landed: none — a decision record'; git add -A; git commit -qm 'chore(beans): decide'
# bean-bad1: completed, names nothing, only a bean-file commit mentions it
bean bean-bad1 completed; git add -A; git commit -qm 'chore(beans): close bean-bad1'
# bean-bad2: completed, names a SHA that exists but is not on main
git checkout -qb side; echo x > src/b.txt; git add -A; git commit -qm side; side=$(git rev-parse --short HEAD)
git checkout -q main; bean bean-bad2 completed "Landed in $side."; git add -A; git commit -qm 'chore(beans): close'
# bean-todo: not completed -> never checked
bean bean-todo todo; git add -A; git commit -qm 'chore(beans): file'
git push -q origin main; git fetch -q origin

out=$("$BIN"/fleet-landed-check --hours 24); rc=$?
for b in bean-bad1 bean-bad2; do grep -q "^UNPROVEN $b:" <<<"$out" && ok "landed-check fires on $b" || bad "landed-check missed $b"; done
for b in bean-good1 bean-good2 bean-good3 bean-todo; do grep -q "$b" <<<"$out" && bad "landed-check flagged $b" || ok "landed-check quiet on $b"; done
[ "$rc" = 1 ] && ok "landed-check exit 1 on violations" || bad "landed-check exit $rc"

# --- review-check --------------------------------------------------------------------------------------------
printf 'Reading additional input from stdin...\nOpenAI Codex v0.50.0\n--------\nworkdir: /x\n' > "$FLEET_REPORTS/s-bean-x-review.out"
{ echo 'VERDICT: CHANGES'; echo 'src/a.ts:12 reads the status before the write commits; a failed write records success.'
  echo 'src/b.ts:40 swallows the error and returns an empty list, which the caller renders as "no data".'
  echo 'Fix both, add a test where the dependency throws.'; } > "$FLEET_REPORTS/s-bean-y-review.md"
echo 'short note' > "$FLEET_REPORTS/codex-reviewer-self-serve.md"
# fleet-review-check leaves a short file alone for its first 15 minutes (a review still being written), so the
# fixtures are 20 minutes old, inside a 60-minute window. With fresh files and --minutes 5 the banner-only case
# could never fire.
python3 -c 'import os, sys, time; t = time.time() - 1200; [os.utime(f, (t, t)) for f in sys.argv[1:]]' \
  "$FLEET_REPORTS"/s-bean-x-review.out "$FLEET_REPORTS"/s-bean-y-review.md "$FLEET_REPORTS"/codex-reviewer-self-serve.md
out=$("$BIN"/fleet-review-check --minutes 60)
grep -q '^EMPTY s-bean-x-review.out' <<<"$out" && ok 'review-check fires on a banner-only review' || bad 'review-check missed banner-only review'
grep -q 's-bean-y-review' <<<"$out" && bad 'review-check flagged a grounded review' || ok 'review-check quiet on a grounded review'
grep -q 'self-serve' <<<"$out" && bad 'review-check flagged a reviewer seat report' || ok 'review-check quiet on a seat report named *-reviewer-*'

# --- fleet-claim reap: young-branch-bean ---------------------------------------------------------------------
now=$(date -u +%FT%TZ); old=$(date -u -d '2 days ago' +%FT%TZ 2>/dev/null || date -u -v-2d +%FT%TZ)
printf 'c1\tbean-new1\tsrc/young.txt\t%s\nc2\tbean-gone\tsrc/old.txt\t%s\n' "$now" "$old" > "$DROVER_HOME/claims.tsv"
out=$("$BIN"/fleet-claim reap)
grep -q 'released src/old.txt' <<<"$out" && ok 'claim reap releases an old claim on a missing bean' || bad 'claim reap kept an old missing-bean claim'
grep -q 'src/young.txt' "$DROVER_HOME/claims.tsv" && ok 'claim reap keeps a young claim on a branch-only bean' || bad 'claim reap dropped a young claim'

# --- fleet-slot ----------------------------------------------------------------------------------------------
export FLEET_HEAVY_SLOTS=2   # one general slot (slot-2)
FLEET_SLOT_HELD=x "$BIN"/fleet-slot run -- true && ok 'slot re-entry runs directly' || bad 'slot re-entry failed'
"$BIN"/fleet-slot run -- sleep 3 & holder=$!; sleep 1
s=$SECONDS; "$BIN"/fleet-slot run -- true 2>/dev/null; waited=$((SECONDS-s)); wait $holder
[ "$waited" -ge 1 ] && ok "second general run waited for the slot (${waited}s)" || bad 'second general run did not wait'
"$BIN"/fleet-slot run -- sleep 3 & holder=$!; sleep 1
s=$SECONDS; "$BIN"/fleet-slot run --push -- true; waited=$((SECONDS-s)); wait $holder
[ "$waited" -lt 1 ] && ok 'a push does not wait behind a general run' || bad "push waited ${waited}s behind a general run"

# --- integration branch and remote ---------------------------------------------------------------------------
up=$(DROVER_MAIN_BRANCH=trunk DROVER_REMOTE=fork bash -c '. "$0"; printf %s "$DROVER_UPSTREAM"' "$BIN/drover-env")
[ "$up" = fork/trunk ] && ok 'DROVER_MAIN_BRANCH/DROVER_REMOTE set the upstream' || bad "upstream is '$up', want fork/trunk"
def=$(bash -c '. "$0"; printf %s "$DROVER_UPSTREAM"' "$BIN/drover-env")
[ "$def" = origin/main ] && ok 'upstream defaults to origin/main' || bad "default upstream is '$def'"

# --- route_land_conflicts: the reason fleet-land-bean writes is the reason fleet-watch routes ----------------
# The real fleet-land-bean flags bean-rl (its only commit conflicts with main); a copy of fleet-watch beside a
# stub `fleet` (one live coder) runs one routing pass. bean-env's reason is an env failure -> stays flagged.
cd "$DROVER_REPO" || exit 1
echo 1 > src/r.txt; git add -A; git commit -qm 'r'
git checkout -qb fleet/c1-bean-rl; echo B > src/r.txt; git add -A; git commit -qm 'feat: r (bean-rl)'
git checkout -q main; echo M > src/r.txt; git add -A; git commit -qm 'main moves r'
"$BIN"/fleet-land-bean bean-rl >/dev/null 2>&1
rl_reason=$(cat "$FLEET_STATE/needs-land/bean-rl" 2>/dev/null)
echo 'typecheck failed on cherry-pick — manual land' > "$FLEET_STATE/needs-land/bean-env"
python3 -c 'import os, sys, time; t = time.time() - 300; [os.utime(f, (t, t)) for f in sys.argv[1:]]' \
  "$FLEET_STATE/needs-land/bean-rl" "$FLEET_STATE/needs-land/bean-env" 2>/dev/null
mkdir -p "$T/wbin"; cp "$BIN"/fleet-watch "$BIN"/drover-env "$T/wbin/"
printf '#!/usr/bin/env bash\n[ "$1" = status ] && printf "NAME KIND STATE\\nclaude-coder claude idle\\n"\n' > "$T/wbin/fleet"; chmod +x "$T/wbin/fleet"
FLEET_BRIEFS="$T/home/briefs" "$T/wbin/fleet-watch" route-land >/dev/null 2>&1
grep -q '^bean-rl	' "$FLEET_STATE/followups/claude-coder" 2>/dev/null && [ ! -e "$FLEET_STATE/needs-land/bean-rl" ] \
  && [ "$(cat "$FLEET_STATE/owner/bean-rl" 2>/dev/null)" = claude-coder ] \
  && ok "route-land hands fleet-land-bean's conflict flag to a live coder" \
  || bad "route-land bean-rl: reason='$rl_reason' still-flagged=$([ -e "$FLEET_STATE/needs-land/bean-rl" ] && echo yes || echo no) owner='$(cat "$FLEET_STATE/owner/bean-rl" 2>/dev/null)' followup=$(grep -c '^bean-rl	' "$FLEET_STATE/followups/claude-coder" 2>/dev/null)"
[ -e "$FLEET_STATE/needs-land/bean-env" ] && ok 'route-land keeps an env-failure flag' || bad 'route-land routed an env failure'
# bean-ro: the same real reason, but the brief cannot be written -> nothing recorded, so the flag stays
printf '%s\n' "$rl_reason" > "$FLEET_STATE/needs-land/bean-ro"
python3 -c 'import os, sys, time; t = time.time() - 300; os.utime(sys.argv[1], (t, t))' "$FLEET_STATE/needs-land/bean-ro"
chmod 555 "$T/home/briefs"
FLEET_BRIEFS="$T/home/briefs" "$T/wbin/fleet-watch" route-land >/dev/null 2>&1
chmod 755 "$T/home/briefs"
[ -e "$FLEET_STATE/needs-land/bean-ro" ] && [ ! -e "$FLEET_STATE/owner/bean-ro" ] && ! grep -q '^bean-ro	' "$FLEET_STATE/followups/claude-coder" \
  && ok 'route-land keeps the flag when the hand-off cannot be written' || bad 'route-land cleared a flag it could not hand off'
# --- fleet-budget: every harness the row filter accepts gets a row -------------------------------------------
# A copy of fleet-budget beside a stub `fleet` (DROVER_BIN is the script's own dir): two cursor seats, one grok.
mkdir -p "$T/bbin"; cp "$BIN"/fleet-budget "$BIN"/drover-env "$T/bbin/"
cat > "$T/bbin/fleet" <<'STUB'
#!/usr/bin/env bash
case $1 in
  status) printf 'NAME KIND STATE\ncursor-coder cursor idle\ncursor-reviewer cursor MISSING\ngrok-coder grok idle\n'; exit 1 ;;
  read) echo 'ready' ;;
esac
STUB
chmod +x "$T/bbin/fleet"
out=$("$T/bbin/fleet-budget" 2>/dev/null)
grep -qE '^cursor +2 +subscription$' <<<"$out" && ok 'budget counts cursor seats' || bad "budget cursor row: $(grep '^cursor' <<<"$out" || echo none)"
grep -qE '^grok +1 +subscription$' <<<"$out" && ok 'budget grok row unchanged' || bad "budget grok row: $(grep '^grok' <<<"$out" || echo none)"
# --- fleet rules: every harness with a plugin-dir loader gets a manifest -------------------------------------
export FLEET_SKILLS="$T/skills"
out=$("$BIN"/fleet rules --dry-run 2>/dev/null)   # captured: grep -q under pipefail SIGPIPEs fleet
grep -qx 'host=cursor' <<<"$out" && ok 'rules dry-run would install the cursor manifest' || bad 'rules dry-run skips cursor'
"$BIN"/fleet rules >/dev/null 2>&1
grep -q '"host": "cursor"' "$FLEET_SKILLS/cursor/plugin.json" 2>/dev/null && [ -f "$FLEET_SKILLS/cursor/skills/fleet-peers/SKILL.md" ] \
  && ok 'rules installs cursor/plugin.json with fleet-peers' || bad 'rules installed no cursor manifest'
out=$("$BIN"/fleet rules --dry-run 2>/dev/null)
grep -q '^host=' <<<"$out" && bad 'rules dry-run reports a diff right after install' || ok 'rules dry-run quiet after install'
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
# --- bean ids vs seat names sharing the bean prefix ----------------------------------------------------------
# Bean prefix x-, seats x-claude-coder, x-grok-coder, x-codex-reviewer, lead x-lead. A follow-up citing x-ab12
# (on main) names seats that \b alone still reads as x-grok and x-lead. Only x-ab12 is checked; an uncited
# missing bean is still refused. herdr is stubbed: check_beans runs before the prompt is sent.
cd "$DROVER_REPO" || exit 1
bean x-ab12 todo; git add -A; git commit -qm 'chore(beans): x-ab12'
mkdir -p "$T/stub"; printf '#!/bin/sh\necho "{}"\n' > "$T/stub/herdr"; chmod +x "$T/stub/herdr"
seats='x-claude-coder:claude x-grok-coder:grok x-codex-reviewer:codex'
txt='fleet-done x-grok-coder x-ab12 DONE "fixed" /r/x-codex-reviewer-review-x-ab12-by-x-grok-coder.md; ask x-lead'
ids=$(DROVER_BEAN_PREFIX=x- DROVER_ROSTER="$seats" DROVER_LEAD_SEATS=x-lead bash -c '. "$0"; drover_bean_ids "$1"' "$BIN/drover-env" "$txt")
[ "$ids" = x-ab12 ] && ok 'bean ids skip seat names that share the bean prefix' || bad "bean ids: $(printf '%s' "$ids" | tr '\n' ' ')"
run_followup(){ PATH="$T/stub:$PATH" DROVER_BEAN_PREFIX=x- FLEET="$seats" DROVER_LEAD_SEATS=x-lead "$BIN"/fleet followup x-grok-coder "$1" 2>&1; }
out=$(run_followup "$txt"); rc=$?
[ "$rc" = 0 ] && ok 'followup to a seat sharing the bean prefix dispatches' || bad "followup refused (rc=$rc): $out"
out=$(run_followup "fleet-done x-grok-coder x-zz99"); rc=$?
[ "$rc" = 2 ] && grep -q 'bean x-zz99 not on' <<<"$out" && ok 'followup still refuses a cited bean missing from main' || bad "missing bean not refused (rc=$rc): $out"
# --- fleet-land-bean: a branch that merged main and resolved the conflict there ------------------------------
# bean-sq: its first commit conflicts with main on src/x.txt; the branch's merge of main resolves it -> lands as
# one squash with the resolution. bean-cf: the branch's net diff still conflicts with main -> flagged, main kept.
cd "$DROVER_REPO" || exit 1
echo 1 > src/x.txt; git add -A; git commit -qm 'x'
git checkout -qb fleet/c1-bean-sq; echo A > src/x.txt; echo feat > src/feat.txt; git add -A; git commit -qm 'feat: thing (bean-sq)'
git checkout -q main; git checkout -qb fleet/c1-bean-cf; echo C > src/x.txt; git add -A; git commit -qm 'feat: other (bean-cf)'
git checkout -q main; echo M > src/x.txt; git add -A; git commit -qm 'main moves x'
git checkout -q fleet/c1-bean-sq; git merge -q main -m 'merge main' >/dev/null 2>&1; echo AM > src/x.txt; git add -A; git commit -qm 'merge main, resolve x'
git checkout -q main
out=$("$BIN"/fleet-land-bean bean-sq 2>&1)
grep -q '^LANDED bean-sq' <<<"$out" && [ "$(cat src/x.txt)" = AM ] && [ -f src/feat.txt ] \
  && ok 'land-bean lands a branch whose merge of main resolves its conflicting commit' || bad "land-bean on a resolved branch: $out"
git log -1 --format=%s | grep -q 'bean-sq' && ok 'land-bean squash commit names the bean' || bad "squash subject: $(git log -1 --format=%s)"
head=$(git rev-parse HEAD); out=$("$BIN"/fleet-land-bean bean-cf 2>&1)
grep -q '^SKIP bean-cf — content conflict' <<<"$out" && [ "$(git rev-parse HEAD)" = "$head" ] \
  && ok 'land-bean flags a branch whose net diff conflicts' || bad "land-bean on a conflicting branch: $out"
[ "$(git worktree list | grep -c .)" = 1 ] && ok 'land-bean leaves no scratch worktree' || bad "worktrees left: $(git worktree list)"
# --- gate worktrees get a copy of DROVER_CLONE_DIRS, not a symlink -------------------------------------------
# Turbopack refuses a node_modules symlink that leaves the project root. Both gates run a command that fails
# on a symlink. A failing copy falls back to a symlink with no partial tree left behind.
cd "$DROVER_REPO" || exit 1
mkdir -p node_modules/pkg; echo 'module.exports = 1' > node_modules/pkg/index.js
real_nm='test -d node_modules && test ! -L node_modules && test -f node_modules/pkg/index.js'
out=$(DROVER_BUILD="$real_nm" DROVER_TEST_ALL= "$BIN"/fleet-verify-main 2>&1)
grep -q '^verify: GREEN' <<<"$out" && ok 'verify-main gate worktree holds a real node_modules' || bad "verify-main: $(tail -3 <<<"$out" | tr '\n' ' ')"
git checkout -qb fleet/c1-bean-nm; echo nm > src/nm.txt; git add src/nm.txt; git commit -qm 'feat: nm (bean-nm)'; git checkout -q main
out=$(DROVER_TYPECHECK="$real_nm" "$BIN"/fleet-land-bean bean-nm 2>&1)
grep -q '^LANDED bean-nm' <<<"$out" && ok 'land-bean gate worktree holds a real node_modules' || bad "land-bean: $(tail -2 <<<"$out" | tr '\n' ' ')"
mkdir -p "$T/seed"; out=$(bash -c '. "$0"; drover_clone(){ mkdir -p "$2/partial"; return 1; }; drover_seed_dir "$1" "$2/nm"' \
  "$BIN/drover-env" "$DROVER_REPO/node_modules" "$T/seed" 2>&1)
[ -L "$T/seed/nm" ] && [ "$(readlink "$T/seed/nm")" = "$DROVER_REPO/node_modules" ] && [ ! -e "$DROVER_REPO/node_modules/partial" ] \
  && ok 'seed falls back to a symlink when the copy fails' || bad "seed fallback: $(ls -la "$T/seed" | tail -n +2 | tr '\n' ' ') $out"
rm -rf node_modules

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
[ ! -e "$PK" ] && git log --format=%s main | grep -q 'bean-ll' && ok 'a dead lock with nothing to push no longer blocks a land' \
  || bad "ahead-0 lock: lock=$([ -e "$PK" ] && echo kept || echo gone) landed=$(git log --format=%s main | grep -c bean-ll) $(grep -E 'push lock|AUTO-LAND' "$FLEET_STATE/../watch.log" 2>/dev/null | tail -2 | tr '\n' ' ')"
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

[ "$fail" = 0 ] && echo 'all checker cases pass' || { echo 'checker cases FAILED'; exit 1; }
