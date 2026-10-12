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

[ "$fail" = 0 ] && echo 'all checker cases pass' || { echo 'checker cases FAILED'; exit 1; }
