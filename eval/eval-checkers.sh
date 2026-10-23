#!/usr/bin/env bash
# eval-checkers — known-good and known-bad cases for the deterministic checkers, on a scratch repo.
#
# Every instrument ships with a case it must fire on AND a case it must stay quiet on (docs/LESSONS.md):
#   fleet-landed-check   completed bean with no landed code -> UNPROVEN (also under a non-ASCII file name);
#                        landed by commit / by named SHA / `Landed: none` -> quiet
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
#   non-ASCII bean names a bean file named with ó/é in a repo with core.quotepath=true -> dispatched on the first pass
#                        (also when the caller already sets core.quotepath=true, repeated, in GIT_CONFIG_COUNT)
#   seat model pin       fleet up: FLEET_MODEL_<seat>/DROVER_SEAT_MODELS -> --model for opencode/claude/agy, beating the
#                        kind pin (two opencode seats, two models); codex/cursor -> no --model; DROVER_YOLO=0 -> the
#                        pins still apply, the bypass flags do not
#   manual seats         DROVER_MANUAL_SEATS: refill gives a free manual seat no bean (fix rounds still flow); off the
#                        list -> dispatched; fleet status TITLE says manual:; fleet assign to it -> dispatched;
#                        route-land keeps an ownerless conflict flagged rather than hand it to a manual seat
#   seat routing         tag seat:<name>: the bean is queued for that seat only (manual seat busy -> stays queued,
#                        automatic seats skip it; free -> dispatched, task file on it); off-roster seat -> logged, not
#                        queued; fleet status says manual: waiting <bean>; an unrouted entry for it -> dropped at pop;
#                        retag/untag/off-roster retag while queued -> re-routed (or removed) by the next top-up
#   fleet-prep           leftover work -> parked on wip/, clean bean branch at origin/main; on its bean branch -> left
#                        alone; an existing bean branch -> resumed; unpushed bean -> cut from local main; shared
#                        checkout -> refused; fleet assign runs it before the brief
#   branch-landed        squash-landed branch -> exit 0 by subject; a new bean commit -> exit 1, AGE, its subject (wip:
#                        and no-bean commits ignored; --all counts both; a one-parent "Merge ..." commit counts);
#                        fleet landable says MERGE landed and
#                        fleet-land-bean refuses that branch; an unlanded branch stays clean
# No network, no keys. Exit 1 on the first wrong answer.
set -uo pipefail
BIN="$(cd "$(dirname "$0")/../bin" && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
# Hermetic git: a user's global config (commit.gpgsign with a key this shell cannot reach, hooks, templates)
# made every scratch commit fail and every case after it wrong.
# Inherited command-scope config can rewrite scratch remotes too.
unset GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS
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
# bean-bad3: bean-bad1 under a non-ASCII file name. git quoted it ("...dow\303\263dca.md"), the .md test failed
# and the bean was never audited.
printf -- '---\ntitle: bean-bad3\nstatus: completed\n---\n' > .beans/bean-bad3--dowódca.md; git add -A; git commit -qm 'chore(beans): close bean-bad3'
git push -q origin main; git fetch -q origin

out=$("$BIN"/fleet-landed-check --hours 24); rc=$?
for b in bean-bad1 bean-bad2 bean-bad3; do grep -q "^UNPROVEN $b:" <<<"$out" && ok "landed-check fires on $b" || bad "landed-check missed $b"; done
for b in bean-good1 bean-good2 bean-good3 bean-todo; do grep -q "$b" <<<"$out" && bad "landed-check flagged $b" || ok "landed-check quiet on $b"; done
[ "$rc" = 1 ] && ok "landed-check exit 1 on violations" || bad "landed-check exit $rc"

# --- no-report release: ownership follows the released task --------------------------------------
mkdir -p "$T/release-bin" "$T/release/tasks" "$T/release/state/owner"
cp "$BIN"/drover-env "$T/release-bin/"
# Expose only the existing reap step in the scratch copy; dispatch remains the production path.
sed '/^if .* = once /i\
if [ "${1:-}" = eval-reap ]; then reap_tasks; exit 0; fi' "$BIN/fleet-watch" > "$T/release-bin/fleet-watch"
chmod +x "$T/release-bin/fleet-watch"
cat > "$T/release-bin/fleet" <<'STUB'
#!/usr/bin/env bash
case $1 in
  status) printf 'NAME KIND STATE\nx-next-coder claude idle\nx-old-coder opencode idle\n' ;;
  assign) printf '%s %s\n' "$2" "$3" >> "$RELEASE_DISPATCHES" ;;
esac
STUB
chmod +x "$T/release-bin/fleet"
release_env(){ FLEET_TASKS="$T/release/tasks" FLEET_STATE="$T/release/state" FLEET_QUEUE="$T/release/queue" \
  FLEET_INBOX="$T/release/inbox" FLEET_REPORTS="$T/release/reports" RELEASE_DISPATCHES="$T/release/dispatches" \
  "$T/release-bin/fleet-watch" "$@" >/dev/null; }
printf '%s\tbean-todo\t-\t-\n' "$(( $(date +%s) - 5400 ))" > "$T/release/tasks/x-old-coder"
echo x-old-coder > "$T/release/state/owner/bean-todo"
release_env eval-reap
[ ! -f "$T/release/tasks/x-old-coder" ] && [ ! -f "$T/release/state/owner/bean-todo" ] \
  && ok 'no-report release removes the released seat owner at 90 minutes' || bad 'no-report release retained task or owner'
release_env dispatch
[ "$(cat "$T/release/dispatches" 2>/dev/null)" = 'bean-todo x-next-coder' ] \
  && ok 'next dispatch hands the released bean to another idle coder' || bad 'released bean did not reach next coder'
printf '%s\tbean-todo\t-\t-\n' "$(( $(date +%s) - 5400 ))" > "$T/release/tasks/x-old-coder"
echo x-next-coder > "$T/release/state/owner/bean-todo"
release_env eval-reap
[ ! -f "$T/release/tasks/x-old-coder" ] && [ "$(cat "$T/release/state/owner/bean-todo")" = x-next-coder ] \
  && ok 'no-report release preserves a different seat owner' || bad 'no-report release removed another seat owner'

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
# Milliseconds, not $SECONDS: that counter ticks on wall-clock second boundaries, so a 0.2 s call that
# straddles one reads as "1 s" and the push case went red on a quiet machine (2026-10-21).
now_ms(){ if [ -n "${EPOCHREALTIME:-}" ]; then local t=${EPOCHREALTIME/./}; echo $((t / 1000)); else python3 -c 'import time; print(int(time.time() * 1000))'; fi; }
"$BIN"/fleet-slot run -- sleep 3 & holder=$!; sleep 1
s=$(now_ms); "$BIN"/fleet-slot run -- true 2>/dev/null; waited=$(( $(now_ms) - s )); wait $holder
[ "$waited" -ge 1000 ] && ok "second general run waited for the slot (${waited}ms)" || bad "second general run did not wait (${waited}ms)"
"$BIN"/fleet-slot run -- sleep 3 & holder=$!; sleep 1
s=$(now_ms); "$BIN"/fleet-slot run --push -- true; waited=$(( $(now_ms) - s )); wait $holder
# The holder has ~2 s left: a push that waited for it reads >= 2000 ms, a free push slot well under that.
[ "$waited" -lt 1500 ] && ok "a push does not wait behind a general run (${waited}ms)" || bad "push waited ${waited}ms behind a general run"

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
[ ! -e "$PK" ] && grep -q 'bean-ll' <<<"$(git log --format=%s main)" && ok 'a dead lock with nothing to push no longer blocks a land' \
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

# --- non-ASCII bean file names: git's core.quotepath=true printed ".beans/x--dow\303\263dca.md", the name match
# in refill failed and the bean was skipped as "not on main" every tick (forum-1avw, panel2-wrl3). The repo sets
# quotepath=true itself, so the case fires whatever the host config says. Same stub coder as the park case.
git init -q -b main "$T/ub"
( cd "$T/ub" && git config user.email e@x.invalid && git config user.name e && git config core.quotepath true && beans init >/dev/null \
  && beans create 'auto groups' -t task -s todo >/dev/null && for f in .beans/*--*.md; do mv "$f" "${f%%--*}--auto-groups-dowódca-béret.md"; done \
  && git add -A && git commit -qm bean )
uid=$(ls "$T/ub/.beans" | sed -n 's/--.*//p' | head -1)
upass(){ ( cd "$T/ub" && env -u DROVER_PROJECT DROVER_REPO="$T/ub" FLEET_QUEUE="$T/uq" FLEET_INBOX="$T/uin" FLEET_TASKS="$T/utasks" \
  FLEET_STATE="$T/uw/state" DISPATCHES="$T/udispatches" "$T/dbin/fleet-watch" dispatch >/dev/null 2>"$T/u.err" ); }
upass
[ "$(cat "$T/udispatches" 2>/dev/null)" = "$uid" ] && ok 'a bean file named with ó/é is dispatched on the first pass' \
  || bad "non-ASCII bean: dispatches='$(cat "$T/udispatches" 2>/dev/null)' $(grep -E 'SKIP|QUEUE' "$T/uw/watch.log" 2>/dev/null | tail -2 | tr '\n' ' ') err: $(head -c 300 "$T/u.err")"
# The caller's environment already lists core.quotepath=true twice (git takes the last; keys are case-insensitive)
# plus an unrelated user.name. drover-env, sourced twice, must leave quotepath false, the name matcher working,
# user.name kept, and exactly one entry added. Overwriting only the first match left the second true (review).
out=$(cd "$T/ub" && env GIT_CONFIG_COUNT=3 GIT_CONFIG_KEY_0=core.quotepath GIT_CONFIG_VALUE_0=true GIT_CONFIG_KEY_1=user.name \
  GIT_CONFIG_VALUE_1=caller GIT_CONFIG_KEY_2=Core.QuotePath GIT_CONFIG_VALUE_2=true \
  bash -c '. "$0"; . "$0"; printf "%s %s %s " "$(git config --get core.quotepath)" "$(git config --get user.name)" "$GIT_CONFIG_COUNT"
  git ls-files .beans | grep -m1 "^.beans/$1--"' "$BIN/drover-env" "$uid" 2>/dev/null)
[ "$out" = "false caller 4 .beans/$uid--auto-groups-dowódca-béret.md" ] && ok 'inherited repeated core.quotepath=true entries: still false, name matches, caller entry kept' \
  || bad "inherited quotepath entries: '$out'"

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
printf '%s\n' "$rl_reason" > "$FLEET_STATE/needs-land/bean-mn"
python3 -c 'import os, sys, time; t = time.time() - 300; os.utime(sys.argv[1], (t, t))' "$FLEET_STATE/needs-land/bean-mn"
DROVER_MANUAL_SEATS=claude-coder FLEET_BRIEFS="$T/home/briefs" "$T/wbin/fleet-watch" route-land >/dev/null 2>&1
[ -e "$FLEET_STATE/needs-land/bean-mn" ] && ! grep -q '^bean-mn	' "$FLEET_STATE/followups/claude-coder" 2>/dev/null \
  && ok 'route-land never hands an ownerless conflict to a manual seat' || bad 'route-land routed a conflict to a manual seat'
rm -f "$FLEET_STATE/needs-land/bean-mn"

# --- fleet-prep: a seat's worktree goes on fleet/<seat>-<bean> before the brief ---------------------------------
# Seat worktrees of $DROVER_REPO (origin/main is the upstream). Leftover work -> parked on wip/, ends clean on the
# bean branch at the origin/main tip; a seat already on its bean branch is untouched; an existing bean branch is
# resumed, not reset; a bean not pushed yet is cut from local main; the shared checkout is refused. Then the same
# through `fleet assign` (stub herdr reports the seat's cwd).
cd "$DROVER_REPO" || exit 1
git checkout -q main; git push -q origin main; git fetch -q origin
pwt(){ git worktree add -q -b "$2" "$T/pw/$1" "${3:-main}"; }
pst(){ printf '%s %s %s' "$(git -C "$1" branch --show-current)" "$(git -C "$1" rev-parse --short HEAD)" "$(git -C "$1" status --porcelain | wc -l | tr -d ' ')"; }
up=$(git rev-parse --short origin/main)
pwt s1 fleet/s1-old; echo dirt >> "$T/pw/s1/src/a.txt"; echo new > "$T/pw/s1/src/untracked.txt"
out=$("$BIN"/fleet-prep s1 x-ab12 "$T/pw/s1" 2>&1); rc=$?
wip=$(git for-each-ref --format='%(refname:short)' 'refs/heads/wip/s1-*' | head -1)
[ "$rc" = 0 ] && [ "$(pst "$T/pw/s1")" = "fleet/s1-x-ab12 $up 0" ] && [ -n "$wip" ] \
  && [ "$(git show "$wip:src/untracked.txt" 2>/dev/null)" = new ] && git show "$wip:src/a.txt" | grep -qx dirt \
  && ok 'fleet-prep parks a modified + an untracked file on wip/ and ends clean on the bean branch at origin/main' \
  || bad "fleet-prep park (rc=$rc): state='$(pst "$T/pw/s1")' want 'fleet/s1-x-ab12 $up 0' wip='$wip' out: $out"
echo mid >> "$T/pw/s1/src/a.txt"; before=$(git for-each-ref 'refs/heads/wip/' | wc -l)
out=$("$BIN"/fleet-prep s1 x-ab12 "$T/pw/s1" 2>&1); rc=$?
[ "$rc" = 0 ] && [ "$(pst "$T/pw/s1")" = "fleet/s1-x-ab12 $up 1" ] && [ "$(git for-each-ref 'refs/heads/wip/' | wc -l)" = "$before" ] \
  && ok 'fleet-prep leaves a seat already on its bean branch alone (dirty tree kept, nothing parked)' || bad "mid-work seat (rc=$rc): $(pst "$T/pw/s1") out: $out"
git -C "$T/pw/s1" checkout -q -- src/a.txt
pwt s2 fleet/s2-x-ab12; echo work > "$T/pw/s2/src/s2.txt"; git -C "$T/pw/s2" add -A; git -C "$T/pw/s2" commit -qm 'feat: s2 work (x-ab12)'
mine=$(git -C "$T/pw/s2" rev-parse --short HEAD); git -C "$T/pw/s2" switch -q -c fleet/s2-other
out=$("$BIN"/fleet-prep s2 x-ab12 "$T/pw/s2" 2>&1); rc=$?
[ "$rc" = 0 ] && [ "$(pst "$T/pw/s2")" = "fleet/s2-x-ab12 $mine 0" ] && ok 'fleet-prep resumes an existing bean branch, never resets it' \
  || bad "resume (rc=$rc): $(pst "$T/pw/s2") want fleet/s2-x-ab12 $mine 0; out: $out"
bean x-lc01 todo; git add -A; git commit -qm 'chore(beans): x-lc01 (not pushed)'
out=$("$BIN"/fleet-prep s2 x-lc01 "$T/pw/s2" 2>&1); rc=$?
[ "$rc" = 0 ] && [ "$(pst "$T/pw/s2")" = "fleet/s2-x-lc01 $(git rev-parse --short main) 0" ] && ok 'fleet-prep cuts a bean not pushed yet from local main' \
  || bad "local-main bean (rc=$rc): $(pst "$T/pw/s2") out: $out"
head=$(git rev-parse HEAD); echo shared >> src/a.txt
out=$("$BIN"/fleet-prep s1 x-ab12 "$DROVER_REPO" 2>&1); rc=$?
[ "$rc" = 2 ] && grep -q 'shared checkout' <<<"$out" && [ "$(git branch --show-current) $(git rev-parse HEAD)" = "main $head" ] \
  && [ -z "$(git for-each-ref 'refs/heads/wip/s1-*' --contains "$head")" ] && ok 'fleet-prep refuses the shared checkout' || bad "shared checkout (rc=$rc): $out"
git checkout -q -- src/a.txt
pwt s3 fleet/s3-old; echo left > "$T/pw/s3/src/left.txt"; : > "$T/herdr.log"
out=$(hf env HERDR_CWD="$T/pw/s3" FLEET_ROOT="$DROVER_REPO" FLEET='s3-coder:claude' FLEET_BRIEFS="$T/home/briefs" "$BIN"/fleet assign x-ab12 s3-coder 2>&1); rc=$?
[ "$rc" = 0 ] && [ "$(pst "$T/pw/s3")" = "fleet/s3-coder-x-ab12 $up 0" ] && [ -n "$(git for-each-ref 'refs/heads/wip/s3-coder-*')" ] \
  && grep -q '^agent prompt s3-coder New bean: .* x-ab12' "$T/herdr.log" && ok 'fleet assign parks leftover work and briefs on a clean bean branch' \
  || bad "assign + prep (rc=$rc): $(pst "$T/pw/s3") out: $out"

# --- fleet-branch-landed: a branch's commits on main BY SUBJECT (a squash or rebase changes SHA and patch) ----------
# bean-bl01: two commits, squash-landed on main as one commit with the first subject and the second listed in its body
# (fleet-land-bean's squash format) plus an extra file, so neither SHA nor patch matches. Landed. Then a new bean
# commit (2 h old), a wip: commit and a commit naming no bean: only the bean commit is unlanded, with its AGE.
cd "$DROVER_REPO" || exit 1
git checkout -q main
git checkout -qb fleet/c1-bean-bl01; echo a > src/bl.txt; git add src/bl.txt; git commit -qm 'feat: bl (bean-bl01)'
echo b >> src/bl.txt; git commit -qam 'feat: bl part 2 (bean-bl01)'; p2=$(git rev-parse --short HEAD)
git checkout -q main; git merge -q --squash fleet/c1-bean-bl01 >/dev/null; echo extra > src/bl-extra.txt; git add -A
git commit -qm 'feat: bl (bean-bl01)' -m "Squash of fleet/c1-bean-bl01.

- $p2 feat: bl part 2 (bean-bl01)"
out=$("$BIN"/fleet-branch-landed --base main fleet/c1-bean-bl01); rc=$?
[ "$rc" = 0 ] && [ -z "$out" ] && ok 'branch-landed: a squash-landed branch is landed by subject (exit 0, no output)' || bad "squash-landed (rc=$rc): $out"
git checkout -q fleet/c1-bean-bl01
echo c >> src/bl.txt; GIT_COMMITTER_DATE="$(date -d '2 hours ago' -R 2>/dev/null || date -v-2H -R)" git commit -qam 'fix: bl again (bean-bl01)'
echo w > src/wip.txt; git add src/wip.txt; git commit -qm 'wip: leftover (bean-bl01)'
echo n > src/noise.txt; git add src/noise.txt; git commit -qm 'chore: names no bean'
git checkout -q main
out=$("$BIN"/fleet-branch-landed --base main fleet/c1-bean-bl01); rc=$?
age=$(sed -n '1s/^AGE //p' <<<"$out")
[ "$rc" = 1 ] && [ "$(sed -n '2,$p' <<<"$out")" = 'fix: bl again (bean-bl01)' ] && [ "${age:-0}" -ge 119 ] && [ "${age:-0}" -le 122 ] \
  && ok 'branch-landed: one new bean commit -> exit 1, AGE of the oldest, its subject; wip: and no-bean commits ignored' \
  || bad "unlanded (rc=$rc): $(tr '\n' '|' <<<"$out")"
out=$("$BIN"/fleet-branch-landed --base main --all fleet/c1-bean-bl01); rc=$?
[ "$rc" = 1 ] && [ "$(sed -n '2,$p' <<<"$out" | tr '\n' '|')" = 'chore: names no bean|wip: leftover (bean-bl01)|fix: bl again (bean-bl01)|' ] \
  && ok 'branch-landed --all: every non-merge commit counts (no-bean and wip: too)' || bad "--all (rc=$rc): $(tr '\n' '|' <<<"$out")"
# an ordinary one-parent commit whose subject starts "Merge " is work, not a merge commit (review of drover-104i)
git checkout -qb fleet/c1-bean-mg01 main; echo m > src/mg.txt; git add src/mg.txt
GIT_COMMITTER_DATE="$(date -d '1 hour ago' -R 2>/dev/null || date -v-1H -R)" git commit -qm 'Merge feature components (bean-mg01)'; git checkout -q main
out=$("$BIN"/fleet-branch-landed --base main fleet/c1-bean-mg01); rc=$?; age=$(sed -n '1s/^AGE //p' <<<"$out")
out2=$("$BIN"/fleet-branch-landed --base main --all fleet/c1-bean-mg01); rc2=$?
[ "$rc" = 1 ] && [ "$rc2" = 1 ] && [ "$(sed -n '2,$p' <<<"$out")" = 'Merge feature components (bean-mg01)' ] && [ "$out2" = "$out" ] \
  && [ "${age:-0}" -ge 59 ] && [ "${age:-0}" -le 62 ] && ok 'branch-landed: a one-parent "Merge ..." commit is unlanded work (default and --all)' \
  || bad "Merge-subject commit (rc=$rc/$rc2): $(tr '\n' '|' <<<"$out") / $(tr '\n' '|' <<<"$out2")"
: > "$FLEET_STATE/approved/bean-mg01"; head=$(git rev-parse HEAD); out=$("$BIN"/fleet-land-bean bean-mg01 2>&1); rc=$?
[ "$rc" = 0 ] && grep -q '^LANDED bean-mg01' <<<"$out" && [ "$(git log -1 --format=%s)" = 'Merge feature components (bean-mg01)' ] && [ ! -e "$FLEET_STATE/needs-land/bean-mg01" ] \
  && ok 'fleet-land-bean lands a "Merge ..." subject commit, no by-subject refusal' || bad "land Merge-subject (rc=$rc): $out"
git push -q origin main; git fetch -q origin
out=$("$BIN"/fleet-branch-landed fleet/c1-bean-bl01); rc=$?
[ "$rc" = 1 ] && [ "$(sed -n '2p' <<<"$out")" = 'fix: bl again (bean-bl01)' ] && ok 'branch-landed: default base is DROVER_UPSTREAM' || bad "default base (rc=$rc): $out"
"$BIN"/fleet-branch-landed --base nosuchref fleet/c1-bean-bl01 >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && ok 'branch-landed: unknown ref -> exit 2' || bad "unknown ref rc=$rc"
# fleet landable + fleet-land-bean: bean-sl01 is squash-landed under its subject (another patch); bean-nl01 is not landed
git checkout -qb fleet/c1-bean-sl01; echo s > src/sl.txt; git add src/sl.txt; git commit -qm 'feat: sl (bean-sl01)'; git checkout -q main
git checkout -qb fleet/c1-bean-nl01; echo n > src/nl.txt; git add src/nl.txt; git commit -qm 'feat: nl (bean-nl01)'; git checkout -q main
echo s2 > src/sl.txt; echo more > src/sl-more.txt; git add -A; git commit -qm 'feat: sl (bean-sl01)'
mkdir -p "$FLEET_STATE/approved"; : > "$FLEET_STATE/approved/bean-sl01"; : > "$FLEET_STATE/approved/bean-nl01"
out=$(FLEET_ROOT="$DROVER_REPO" "$BIN"/fleet landable 2>&1)
awk '$1=="bean-sl01" && $5=="landed" && /by subject/ {f=1} END{exit !f}' <<<"$out" && awk '$1=="bean-nl01" && $5=="clean" {f=1} END{exit !f}' <<<"$out" \
  && ok 'fleet landable: MERGE landed for the by-subject landed branch, clean for the other' || bad "landable: $out"
head=$(git rev-parse HEAD); out=$("$BIN"/fleet-land-bean bean-sl01 2>&1); rc=$?
[ "$rc" = 1 ] && grep -q '^SKIP bean-sl01 — already on main by subject' <<<"$out" && [ "$(git rev-parse HEAD)" = "$head" ] \
  && [ -f "$FLEET_STATE/needs-land/bean-sl01" ] && ok 'fleet-land-bean refuses a branch already on main by subject (flagged, main unchanged)' \
  || bad "land-bean by subject (rc=$rc): $out"
rm -f "$FLEET_STATE/needs-land/bean-sl01" "$FLEET_STATE/approved/bean-nl01"

# --- clear_dialogs: codex's folder-trust prompt is answered; a changed layout or bare chrome is left alone ----
# A copy of fleet-watch beside a stub `fleet`: status lists the seats, read prints $SCREENS/<seat>, keys logs.
mkdir -p "$T/kbin" "$T/screens"; cp "$BIN"/fleet-watch "$BIN"/drover-env "$T/kbin/"
cat > "$T/kbin/fleet" <<'STUB'
#!/usr/bin/env bash
case $1 in
  status) printf 'NAME KIND STATE\n'; for f in "$SCREENS"/*; do printf '%s x idle\n' "${f##*/}"; done ;;
  read) cat "$SCREENS/$2" ;;
  keys) shift; echo "$*" >> "$KEYS" ;;
esac
exit 0
STUB
chmod +x "$T/kbin/fleet"
printf '  Trust this folder? Codex can read, edit, and run files here, ...\n\n› 1. Trust and continue\n  2. Quit\n\n  enter continue · esc quit\n' > "$T/screens/cx-on1"
printf '  1. Trust and continue\n› 2. Quit\n\n  enter continue · esc quit\n' > "$T/screens/cx-on2"
printf ' ❯ No, exit\n   Yes, I trust this folder\n\n Enter to confirm · Esc to exit\n' > "$T/screens/cl-trust"
printf '  Working (12s)\n\n  enter continue · esc quit\n' > "$T/screens/cx-chrome"
SCREENS="$T/screens" KEYS="$T/keys" FLEET_STATE="$T/kw/state" "$T/kbin/fleet-watch" dialogs >/dev/null 2>&1
grep -qx 'cx-on1 Enter' "$T/keys" && grep -q 'dialog: trusted own worktree on cx-on1 (codex)$' "$T/kw/watch.log" \
  && ok 'clear_dialogs: codex folder-trust with the cursor on "1. Trust and continue" gets Enter, logged (codex)' \
  || bad "codex trust: keys=$(tr '\n' '|' < "$T/keys" 2>/dev/null) log=$(tr '\n' '|' < "$T/kw/watch.log" 2>/dev/null)"
grep -qx 'cl-trust Down Enter' "$T/keys" && grep -q 'dialog: trusted own worktree on cl-trust$' "$T/kw/watch.log" \
  && ok 'clear_dialogs: the Claude folder-trust case is unchanged (Down Enter)' || bad "claude trust: keys=$(tr '\n' '|' < "$T/keys" 2>/dev/null)"
[ "$(wc -l < "$T/keys")" = 2 ] && ok 'clear_dialogs: cursor on "2. Quit" and bare "enter continue" chrome get no keys' \
  || bad "dialog keys sent to the wrong seats: $(tr '\n' '|' < "$T/keys")"

# Silent seat recovery: real tracked changes, persistent state, bounded prompt stub.
mkdir -p "$T/sbin" "$T/silent/tasks" "$T/silent/inbox"
cp "$BIN"/fleet-watch "$BIN"/drover-env "$T/sbin/"
git clone -q "$T/origin.git" "$T/silent-wt" 2>/dev/null
git -C "$T/silent-wt" checkout -qb main origin/main
git -C "$T/silent-wt" checkout -qb fleet/test-coder
printf 'dirty\n' >> "$T/silent-wt/src/a.txt"
cat > "$T/sbin/fleet" <<'STUB'
#!/usr/bin/env bash
printf 'NAME KIND STATE\ntest-coder opencode %s\nother-coder opencode MISSING\n' "$(cat "$SILENT_ROOT/status")"
exit 1 # Real fleet status returns nonzero if another roster seat is missing.
STUB
cat > "$T/sbin/herdr" <<'STUB'
#!/usr/bin/env bash
case $2 in
  get) jq -n --arg cwd "$SILENT_ROOT/../silent-wt" '{result:{agent:{cwd:$cwd}}}' ;;
  prompt) printf '%s\n' "$*" >> "$SILENT_ROOT/prompts" ;;
esac
STUB
chmod +x "$T/sbin/fleet" "$T/sbin/herdr"
printf '1\tbean-silent\n' > "$T/silent/tasks/test-coder"
echo done > "$T/silent/status"
spass(){ PATH="$T/sbin:$PATH" SILENT_ROOT="$T/silent" FLEET_TASKS="$T/silent/tasks" FLEET_STATE="$T/silent/state" FLEET_INBOX="$T/silent/inbox" "$T/sbin/fleet-watch" silent >/dev/null; }
sdir="$T/silent/state/silent/bean-silent"
spass
[ ! -f "$T/silent/prompts" ] && ok 'silent: fresh idle seat is not nudged' || bad 'silent: premature nudge'
echo $(( $(date +%s)-300 )) > "$sdir/idle"
spass; spass
[ "$(wc -l < "$T/silent/prompts")" = 1 ] && grep -q 'finish bean-silent: run the gate, commit, report, announce with fleet-done' "$T/silent/prompts" \
  && [ "$(grep -c 'NUDGE test-coder bean-silent$' "$T/silent/watch.log")" = 1 ] \
  && ok 'silent: five minutes idle with tracked changes sends exactly one nudge' || bad 'silent: missing or repeated prompt'
echo working > "$T/silent/status"; spass
echo done > "$T/silent/status"; spass
echo $(( $(date +%s)-300 )) > "$sdir/idle"
echo $(( $(date +%s)-300 )) > "$sdir/nudged"
spass; spass
[ "$(wc -l < "$T/silent/prompts")" = 1 ] && [ "$(grep -c 'needs lead: silent seat' "$T/silent/state/blocked")" = 1 ] \
  && ok 'silent: second stop flags the bean once without another nudge' || bad 'silent: second-stop escalation'
# Announcements suppress even an overdue idle seat; keep each verdict in the inbox.
for verdict in DONE BLOCKED PARTIAL; do
  rm -f "$sdir/announced" "$sdir/nudged" "$sdir/flagged"
  printf '2\ttest-coder\tbean-silent\t%s\tsummary\treport\n' "$verdict" > "$T/silent/inbox/a.msg"
  spass
  [ -f "$sdir/announced" ] && [ "$(wc -l < "$T/silent/prompts")" = 1 ] \
    && ok "silent: $verdict announcement prevents nudge" || bad "silent: nudged after $verdict"
done
# A clean worktree with bean commits still needs recovery; untracked-only does not.
rm -f "$T/silent/inbox/a.msg" "$sdir/announced" "$sdir/nudged" "$sdir/flagged"
git -C "$T/silent-wt" -c user.name=eval -c user.email=eval@example.invalid commit -qam 'bean-silent work'
spass
[ "$(wc -l < "$T/silent/prompts")" = 2 ] && ok 'silent: clean tree with commits ahead is nudged' || bad 'silent: missed unreported commits'

# Clean at the base (including untracked-only scratch) is never unfinished work.
git -C "$T/silent-wt" branch -f main HEAD
rm -f "$sdir/nudged" "$sdir/flagged"
echo scratch > "$T/silent-wt/untracked"
spass
[ "$(wc -l < "$T/silent/prompts")" = 2 ] && ok 'silent: untracked-only tree at base is not nudged' || bad 'silent: nudged a clean tracked tree'
echo dirty >> "$T/silent-wt/src/a.txt"
echo working > "$T/silent/status"; spass
echo done > "$T/silent/status"; spass
[ "$(wc -l < "$T/silent/prompts")" = 2 ] && ok 'silent: working resets the continuous idle window' || bad 'silent: task age mistaken for idle age'

# An announcement belongs to a dispatch, not all future rounds of the bean.
printf '10\tbean-round\n' > "$T/silent/tasks/test-coder"
printf '11\ttest-coder\tbean-round\tDONE\tsummary\treport\n' > "$T/silent/inbox/a.msg"
spass
rdir="$T/silent/state/silent/bean-round"
rm -f "$T/silent/inbox/a.msg" # Simulate the inbox drain after recording the marker.
echo $(( $(date +%s)-300 )) > "$rdir/idle"
spass
[ -f "$rdir/announced" ] && [ "$(wc -l < "$T/silent/prompts")" = 2 ] \
  && ok 'silent: drained DONE still suppresses the same task' || bad 'silent: lost announcement on same task'
printf '12\tbean-round\n' > "$T/silent/tasks/test-coder"
spass
echo $(( $(date +%s)-300 )) > "$rdir/idle"
spass; spass
[ ! -f "$rdir/announced" ] && [ "$(wc -l < "$T/silent/prompts")" = 3 ] \
  && [ "$(grep -c 'NUDGE test-coder bean-round$' "$T/silent/watch.log")" = 1 ] \
  && ok 'silent: new task for an announced bean gets one nudge after five idle minutes' || bad 'silent: old DONE hid a later round'
help=$("$T/sbin/fleet-watch" --help)
printf '%s\n' "$help" | grep -q 'fleet-watch enqueue' && printf '%s\n' "$help" | grep -q 'fleet-watch queue ' \
  && ok 'watch help includes enqueue and queue' || bad 'watch help truncates usage'

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

[ "$fail" = 0 ] && echo 'all checker cases pass' || { echo 'checker cases FAILED'; exit 1; }
