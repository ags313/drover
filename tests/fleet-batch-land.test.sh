#!/usr/bin/env bash
# Tests for fleet-batch-land. Real git, real worktrees, a bare repo as origin.
# The gate is a script that fails when the stack contains a file named BAD — a deterministic stand-in
# for "this branch breaks the build". Every scenario states its known-bad and known-good side.
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
BL="$ROOT/bin/fleet-batch-land"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
unset GIT_DIR GIT_WORK_TREE
PASS=0; FAILN=0
ok()   { PASS=$((PASS+1)); echo "  ok   $*"; }
fail() { FAILN=$((FAILN+1)); echo "  FAIL $*"; }
eq()   { [ "$2" = "$3" ] && ok "$1" || fail "$1 (want '$3', got '$2')"; }
has()  { case "$2" in *"$3"*) ok "$1" ;; *) fail "$1 (no '$3' in: $(printf '%s' "$2" | tail -5 | tr '\n' '|'))" ;; esac; }
hasnt(){ case "$2" in *"$3"*) fail "$1 (unexpected '$3')" ;; *) ok "$1" ;; esac; }

new_world() {   # fresh origin + clone; sets O (origin), C (clone), S (state), W (env root)
  W=$(mktemp -d "$T/w.XXXX"); O=$W/origin.git; C=$W/repo; S=$W/state
  git init -q --bare "$O"; git --git-dir="$O" symbolic-ref HEAD refs/heads/main; git init -q -b main "$C"
  git -C "$C" remote add origin "$O"
  echo base > "$C/base.txt"; printf 'line1\nline2\nline3\n' > "$C/shared.txt"
  git -C "$C" add -A; git -C "$C" commit -qm base; git -C "$C" push -q origin main
  mkdir -p "$S/ready" "$S/approved"; touch "$S/batch-land-enabled"
  # one log line per push that actually reaches the remote (a --dry-run never gets here)
  printf '#!/bin/sh\nwhile read o n ref; do [ "$ref" = refs/heads/main ] && echo push >> "%s/pushes.log"; done\nexit 0\n' "$W" > "$O/hooks/pre-receive"; chmod +x "$O/hooks/pre-receive"
  printf '#!/bin/sh\necho gate >> "%s/gates.log"\n[ -f BAD ] && { echo "BAD file present: build broken"; exit 1; }\nexit "${FAKE_GATE_RC:-0}"\n' "$W" > "$W/gate.sh"; chmod +x "$W/gate.sh"
  printf '#!/bin/sh\necho "$@" >> "%s/notify.log"\n' "$W" > "$W/notify.sh"; chmod +x "$W/notify.sh"
  : > "$W/pushes.log"; : > "$W/gates.log"; : > "$W/notify.log"
}
seat() {   # seat <agent> <bean> <file> <content> [base-ref]  -> branch fleet/<agent>-<bean> with one commit
  local a=$1 b=$2 f=$3 content=$4 base=${5:-origin/main} br=fleet/$1-$2
  git -C "$C" branch -q -f "$br" "$base"
  local wt=$W/seat-$b; rm -rf "$wt"; git -C "$C" worktree add -q "$wt" "$br"
  printf '%s\n' "$content" > "$wt/$f"; git -C "$wt" add -A; git -C "$wt" commit -qm "feat($b): $f"
  git -C "$C" worktree remove --force "$wt"; git -C "$C" push -q origin "$br"
}
bl() { BL_REPO=$C BL_STATE=$S BL_WT_ROOT=$W/lander BL_LEDGER=$W/ledger BL_REPORTS=$W/reports \
  BL_REQUIRE_APPROVED=0 BL_REQUIRE_REPORT=0 BL_GATE_CMD="$W/gate.sh" BL_NOTIFY_CMD=$W/notify.sh BL_BASELINE_CMD='[ ! -f BADBASE ]' BL_LINK_DIRS='node_modules backend/node_modules' DROVER_NO_TESTDB_IF_SET='PREPUSH_BUILD_FIXTURES PREPUSH_DB_FIXTURES' DROVER_ENV_FAIL_RE='fixture (manifest|aliases)|separate build|(invalid|expired).*lease' "$@"; }
ready() { BL_BRANCH_OF=fleet/$1-$2 bl "$BL" ready "$1" "$2" >/dev/null; }
run() { bl "$BL" run "$@" 2>&1; }
count() { local c; c=$(grep -c . "$1" 2>/dev/null); echo "${c:-0}"; }
on_origin() {   # on_origin <seat-branch> -> yes if every non-merge commit of the branch is on origin/main as a cherry-pick
  local br=$1 c n=0 hit=0
  git -C "$C" fetch -q origin
  for c in $(git -C "$C" rev-list --no-merges origin/main.."$br" 2>/dev/null; true); do n=$((n+1)); done
  # patch-equivalent commits are reported '-' by git cherry
  [ "$(git -C "$C" cherry origin/main "$br" | grep -c '^+')" = 0 ] && echo yes || echo no
}

echo "T1 two READY branches land as ONE push, ONE gate run, ancestry proven"
new_world
seat a b1 one.txt one; seat b b2 two.txt two
ready a b1; ready b b2
out=$(run)
eq "T1 exactly one push reached origin" "$(count "$W/pushes.log")" 1
eq "T1 exactly one gate run" "$(count "$W/gates.log")" 1
eq "T1 b1 landed" "$(on_origin fleet/a-b1)" yes
eq "T1 b2 landed" "$(on_origin fleet/b-b2)" yes
has "T1 PROOF line b1" "$out" "PROOF b1"
has "T1 PROOF says YES" "$out" "ancestor-of origin/main: YES"
hasnt "T1 no NO proofs" "$out" "ancestor-of origin/main: NO"
eq "T1 ready records cleared" "$(ls "$S/ready" | wc -l | tr -d ' ')" 0
eq "T1 landed record written" "$([ -s "$S/landed/b1" ] && echo y)" y
# independent ancestry check, not the script's own output
sha=$(git -C "$C" log origin/main --format=%H --grep="feat(b1)" | head -1)
git -C "$C" merge-base --is-ancestor "$sha" origin/main && ok "T1 independent ancestry of b1" || fail "T1 independent ancestry"

echo "T2 third branch breaks the gate: dropped + reported, first two still land in ONE push"
new_world
seat a b1 one.txt one; seat b b2 two.txt two; seat c b3 BAD broken
ready a b1; ready b b2; ready c b3
out=$(run)
eq "T2 one push" "$(count "$W/pushes.log")" 1
eq "T2 b1 landed" "$(on_origin fleet/a-b1)" yes
eq "T2 b2 landed" "$(on_origin fleet/b-b2)" yes
eq "T2 b3 NOT on origin" "$(git -C "$C" ls-tree -r --name-only origin/main | grep -c '^BAD$')" 0
has "T2 b3 reported dropped" "$out" "DROPPED b3"
has "T2 failure text kept for the seat" "$(cat "$S/dropped/b3")" "BAD file present"
has "T2 seat notified with CHANGES" "$(cat "$W/notify.log")" "c b3 CHANGES"
eq "T2 b3 not READY any more" "$([ -f "$S/ready/b3" ] && echo y || echo n)" n
eq "T2 bisect+confirm cost at most 4 gate runs" "$([ "$(count "$W/gates.log")" -le 4 ] && echo y)" y

echo "T3 the FIRST branch is the bad one: the other two still land"
new_world
seat a b1 BAD broken; seat b b2 two.txt two; seat c b3 three.txt three
ready a b1; ready b b2; ready c b3
out=$(run)
eq "T3 one push" "$(count "$W/pushes.log")" 1
has "T3 b1 dropped" "$out" "DROPPED b1"
eq "T3 b2 landed" "$(on_origin fleet/b-b2)" yes
eq "T3 b3 landed" "$(on_origin fleet/c-b3)" yes

echo "T4 content conflict: second branch dropped with the file named, first lands"
new_world
seat a b1 shared.txt "$(printf 'line1\nCHANGED-A\nline3')"; seat b b2 shared.txt "$(printf 'line1\nCHANGED-B\nline3')"
ready a b1; ready b b2
out=$(run)
eq "T4 b1 landed" "$(on_origin fleet/a-b1)" yes
has "T4 b2 dropped for conflict" "$out" "content conflict in shared.txt"
eq "T4 one push" "$(count "$W/pushes.log")" 1

echo "T5 branch moved after READY: dropped, not landed"
new_world
seat a b1 one.txt one; ready a b1
git -C "$C" worktree add -q "$W/m" fleet/a-b1; echo more > "$W/m/more.txt"; git -C "$W/m" add -A; git -C "$W/m" commit -qm extra; git -C "$C" worktree remove --force "$W/m"
out=$(run)
has "T5 stale tip dropped" "$out" "branch tip moved since READY"
eq "T5 no push" "$(count "$W/pushes.log")" 0

echo "T6 env failure (test DB missing) drops NOBODY and pushes nothing"
new_world
seat a b1 one.txt one; seat b b2 two.txt two; ready a b1; ready b b2
printf '#!/bin/sh\necho "[pre-push] database URLs missing; run eval test-db-up"\nexit 1\n' > "$W/gate.sh"
out=$(run); rc=$?
has "T6 reported as ENV-FAIL" "$out" "ENV-FAIL"
eq "T6 no push" "$(count "$W/pushes.log")" 0
eq "T6 READY records kept" "$(ls "$S/ready" | wc -l | tr -d ' ')" 2
eq "T6 nobody dropped" "$(ls "$S/dropped" 2>/dev/null | wc -l | tr -d ' ')" 0

echo "T7 origin moves during the gate: re-stack and land on the new tip"
new_world
seat a b1 one.txt one; ready a b1
git clone -q -b main "$O" "$W/other"; (cd "$W/other" && echo x > interloper.txt && git add -A && git commit -qm interloper)
printf '#!/bin/sh\necho gate >> "%s/gates.log"\nif [ ! -f "%s/raced" ]; then touch "%s/raced"; git -C "%s/other" push -q origin HEAD:main; fi\nexit 0\n' "$W" "$W" "$W" "$W" > "$W/gate.sh"
out=$(run)
has "T7 saw the race" "$out" "push raced"
git -C "$C" fetch -q origin
eq "T7 interloper kept" "$(git -C "$C" ls-tree -r --name-only origin/main | grep -c '^interloper.txt$')" 1
eq "T7 b1 landed on top" "$(on_origin fleet/a-b1)" yes

echo "T8 a stale branch cannot delete work that landed after it forked"
new_world
seat a b1 one.txt one                      # b1 forks from the current main (no keep.txt)
(cd "$C" && git checkout -q main && echo precious > keep.txt && git add -A && git commit -qm "landed later" && git push -q origin main)
ready a b1; out=$(run)
git -C "$C" fetch -q origin
eq "T8 keep.txt survives" "$(git -C "$C" show origin/main:keep.txt 2>/dev/null)" precious
eq "T8 b1 landed" "$(on_origin fleet/a-b1)" yes

echo "T9 tick: waits below K and below N minutes, lands at K, lands when the oldest is old enough, silent when disabled"
new_world
seat a b1 one.txt one; seat b b2 two.txt two; seat c b3 three.txt three
ready a b1; ready b b2
rm -f "$S/batch-land-enabled"
out=$(BL_K=3 BL_AGE_MIN=60 bl "$BL" tick 2>&1); eq "T9 disabled marker: silent" "$out" ""
touch "$S/batch-land-enabled"
out=$(BL_K=3 BL_AGE_MIN=60 bl "$BL" tick 2>&1); has "T9 2 READY, young: waiting" "$out" "waiting"; eq "T9 no push yet" "$(count "$W/pushes.log")" 0
ready c b3
out=$(BL_K=3 BL_AGE_MIN=60 bl "$BL" tick 2>&1); has "T9 K reached: landing" "$out" "landing"; eq "T9 one push for three" "$(count "$W/pushes.log")" 1
seat a b4 four.txt four; ready a b4
out=$(BL_K=3 BL_AGE_MIN=0 bl "$BL" tick 2>&1); has "T9 age reached: landing a single branch" "$out" "landing"; eq "T9 second push" "$(count "$W/pushes.log")" 2

echo "T10 ready refuses an unreviewed, unpushed or unverified branch"
new_world
seat a b1 one.txt one
o=$(BL_REPO=$C BL_STATE=$S BL_REPORTS=$W/reports BL_REQUIRE_APPROVED=1 BL_REQUIRE_REPORT=0 "$BL" ready a b1 2>&1); rc=$?
eq "T10 no APPROVE -> refused" "$([ $rc -ne 0 ] && echo y)" y; has "T10 says why" "$o" "no reviewer APPROVE"
touch "$S/approved/b1"; mkdir -p "$W/reports"
o=$(BL_REPO=$C BL_STATE=$S BL_REPORTS=$W/reports BL_REQUIRE_APPROVED=1 BL_REQUIRE_REPORT=1 "$BL" ready a b1 2>&1); rc=$?
eq "T10 no report -> refused" "$([ $rc -ne 0 ] && echo y)" y; has "T10 says why" "$o" "REBASED: YES"
printf 'REBASED: YES\nVERIFIED: BUILD 0 TESTS 3/3\n' > "$W/reports/a-b1.md"
o=$(BL_REPO=$C BL_STATE=$S BL_REPORTS=$W/reports BL_REQUIRE_APPROVED=1 BL_REQUIRE_REPORT=1 "$BL" ready a b1 2>&1); rc=$?
eq "T10 approved+verified+pushed -> READY" "$rc" 0; has "T10 READY printed" "$o" "READY b1"
git -C "$C" branch -q -f fleet/a-b9 origin/main
o=$(BL_REPO=$C BL_STATE=$S BL_REPORTS=$W/reports BL_REQUIRE_APPROVED=0 BL_REQUIRE_REPORT=0 "$BL" ready a b9 2>&1); rc=$?
eq "T10 unpushed branch -> refused" "$([ $rc -ne 0 ] && echo y)" y

echo "T11 a change already on the target is skipped, not re-landed"
new_world
seat a b1 one.txt one
git -C "$C" worktree add -q "$W/p" -b tmp origin/main; (cd "$W/p" && echo one > one.txt && git add -A && git commit -qm same && git push -q origin HEAD:main); git -C "$C" worktree remove --force "$W/p"
BL_BRANCH_OF=fleet/a-b1 bl "$BL" ready a b1 >/dev/null 2>&1; rc=$?
eq "T11 nothing ahead -> not READY" "$([ $rc -ne 0 ] && echo y)" y

echo "T12 a push that did not reach origin is NOT reported as landed (the proof can say NO)"
new_world
seat a b1 one.txt one; ready a b1
out=$(BL_PUSH_CMD=true run); rc=$?
has "T12 proof says NO" "$out" "ancestor-of origin/main: NO"
has "T12 loud failure" "$out" "PROOF FAILED"
hasnt "T12 never prints LANDED" "$out" "LANDED b1"

echo "T13 the gate sees the installed toolchain: git clean must not remove the node_modules links"
new_world
mkdir -p "$C/node_modules" "$C/backend/node_modules"; touch "$C/node_modules/marker" "$C/backend/node_modules/marker"
seat a b1 one.txt one; seat b b2 two.txt two; ready a b1; ready b b2
printf '#!/bin/sh\necho gate >> "%s/gates.log"\n[ -e node_modules/marker ] && [ -e backend/node_modules/marker ] || { echo "toolchain missing in gate worktree"; exit 1; }\nexit 0\n' "$W" > "$W/gate.sh"
out=$(run)
hasnt "T13 nothing dropped for a missing toolchain" "$out" "DROPPED"
eq "T13 both landed" "$(on_origin fleet/a-b1)$(on_origin fleet/b-b2)" yesyes

echo "T14 a gate killed by a signal is an ENV failure, not the branch's fault (measured 2026-10-12: SIGTERM mid-jest)"
new_world
seat a b1 one.txt one; ready a b1
printf '#!/bin/sh\necho gate >> "%s/gates.log"\nkill -TERM $$\n' "$W" > "$W/gate.sh"
out=$(run)
has "T14 reported as ENV-FAIL" "$out" "ENV-FAIL"
hasnt "T14 branch not dropped" "$out" "DROPPED"
eq "T14 READY record kept" "$([ -f "$S/ready/b1" ] && echo y)" y
eq "T14 no push" "$(count "$W/pushes.log")" 0

echo "T15 the gate worktree is CLEAN even with the dependency links in it (a dirty tree has no pre-push cache key, so the real push would re-run the whole gate)"
new_world
mkdir -p "$C/node_modules" "$C/backend/node_modules"; touch "$C/node_modules/marker" "$C/backend/node_modules/marker"
echo x > "$C/backend/keep.txt"; git -C "$C" add backend/keep.txt >/dev/null; git -C "$C" commit -qm "backend dir"; git -C "$C" push -q origin main
seat a b1 one.txt one; ready a b1
printf '#!/bin/sh\necho gate >> "%s/gates.log"\ns=$(git status --porcelain)\n[ -z "$s" ] || { echo "DIRTY: $s"; exit 1; }\nexit 0\n' "$W" > "$W/gate.sh"
out=$(run)
hasnt "T15 gate saw a clean tree" "$out" "DROPPED"
eq "T15 landed" "$(on_origin fleet/a-b1)" yes

echo "T16 (#2) the lander never resets or cleans a worktree it does not own"
new_world
seat a b1 one.txt one; ready a b1
mkdir -p "$W/lander"; git -C "$C" worktree add -q "$W/seatwt" -b seatwork origin/main; echo precious > "$W/seatwt/untracked.txt"; echo edited >> "$W/seatwt/base.txt"
ln -s "$W/seatwt" "$W/lander/wt"
out=$(run); rc=$?
has "T16 symlinked worktree refused" "$out" "not owned"
eq "T16 seat's untracked file intact" "$(cat "$W/seatwt/untracked.txt" 2>/dev/null)" precious
eq "T16 seat's tracked edit intact" "$(grep -c edited "$W/seatwt/base.txt")" 1
eq "T16 nothing pushed" "$(count "$W/pushes.log")" 0
rm "$W/lander/wt"; git -C "$C" worktree add -q --detach "$W/lander/wt" origin/main; echo keep > "$W/lander/wt/untracked2.txt"   # a real worktree, but never marked as the lander's
out=$(run)
has "T16 unmarked worktree refused" "$out" "not owned"
eq "T16 unmarked worktree untouched" "$(cat "$W/lander/wt/untracked2.txt" 2>/dev/null)" keep

echo "T17 (#6) run refuses without the enable marker, and re-checks it right before the push"
new_world
seat a b1 one.txt one; ready a b1
rm -f "$S/batch-land-enabled"
out=$(run); has "T17 disabled run says so" "$out" "not enabled"; eq "T17 no push without the marker" "$(count "$W/pushes.log")" 0
out=$(run --dry); has "T17 --dry still allowed without the marker" "$out" "DRY"
touch "$S/batch-land-enabled"
printf '#!/bin/sh\necho gate >> "%s/gates.log"\nrm -f "%s/batch-land-enabled"\nexit 0\n' "$W" "$S" > "$W/gate.sh"
out=$(run); has "T17 marker removed mid-run: not pushing" "$out" "marker removed"
eq "T17 no push after the marker went away" "$(count "$W/pushes.log")" 0
eq "T17 READY kept" "$([ -f "$S/ready/b1" ] && echo y)" y

echo "T18 (#3) a failed cherry-pick (stale index.lock) is an env failure, never 'already on target'"
new_world
seat a b1 one.txt one; ready a b1; run >/dev/null
seat b b2 two.txt two; ready b b2
touch "$(git -C "$W/lander/wt" rev-parse --git-path index.lock)"
out=$(run)
has "T18 reported as ENV-FAIL" "$out" "ENV-FAIL"
hasnt "T18 never pretends it landed" "$out" "LANDED b2"
eq "T18 b2 still READY" "$([ -f "$S/ready/b2" ] && echo y)" y
eq "T18 b2 has no landed record" "$([ -e "$S/landed/b2" ] && echo y || echo n)" n
eq "T18 only the first push happened" "$(count "$W/pushes.log")" 1

echo "T19 (#9) a failed ancestry proof leaves NO landed record and keeps READY"
new_world
seat a b1 one.txt one; ready a b1
old=$(git -C "$O" rev-parse main)
out=$(BL_PUSH_CMD="git push \$BL_REMOTE HEAD:\$BL_TARGET && git --git-dir=$O update-ref refs/heads/main $old" run); rc=$?
has "T19 proof says NO" "$out" "ancestor-of origin/main: NO"
eq "T19 no landed record" "$([ -e "$S/landed/b1" ] && echo y || echo n)" n
eq "T19 READY kept for the retry" "$([ -f "$S/ready/b1" ] && echo y)" y
hasnt "T19 never prints LANDED" "$out" "LANDED b1"
eq "T19 no LANDED in the ledger" "$(grep -c LANDED "$W/ledger" 2>/dev/null)" 0

echo "T20 (#4) concurrent landers never overlap; a dead stale lock does not block; a SIGKILLed lander releases the lock"
new_world
seat a b1 one.txt one; ready a b1
mkdir -p "$S/batch-land.lock"; echo 999999 > "$S/batch-land.lock/pid"      # legacy stale lock of a dead pid
printf '#!/bin/sh\nif ! mkdir "%s/busy" 2>/dev/null; then echo OVERLAP >> "%s/overlap.log"; exit 1; fi\nsleep 2\necho gate >> "%s/gates.log"\nrmdir "%s/busy"\nexit 0\n' "$W" "$W" "$W" "$W" > "$W/gate.sh"
: > "$W/overlap.log"
for i in 1 2 3 4 5 6; do ( run >"$W/c$i.out" 2>&1 ) & done; wait
# a live production lander on the same machine must survive this suite: the decoy's command line matches the old global pkill pattern
bash -c 'sleep 9137 & echo $! > "$0"; wait' "$T/decoy.sleep" fleet-batch-land run &
DECOY=$!
eq "T20 no two gates overlapped" "$(count "$W/overlap.log")" 0
eq "T20 exactly one push" "$(count "$W/pushes.log")" 1
eq "T20 the others said they were locked out" "$(cat "$W"/c*.out | grep -c 'holds the lock')" 5
new_world
seat a b1 one.txt one; ready a b1
printf '#!/bin/sh\necho $$ > "%s/gate.pid"\nsleep 3\nexit 0\n' "$W" > "$W/gate.sh"
( run >"$W/k.out" 2>&1 ) & KP=$!; sleep 2
lpid=$(cat "$W"/lander/logs/run-*/pid 2>/dev/null | head -1); [ -n "$lpid" ] && kill -9 "$lpid"; wait "$KP" 2>/dev/null
sleep 4
out=$(run); has "T20 lock released by the kill; next run lands" "$out" "LANDED b1"

eq "T20 (d) the suite kills only its own lander: the decoy lives" "$(kill -0 "$DECOY" 2>/dev/null && echo alive || echo dead)" alive
kill "$DECOY" "$(cat "$T/decoy.sleep" 2>/dev/null)" 2>/dev/null
echo "T21 (#5) SIGTERM kills the gate's whole process group before the lock is released"
new_world
seat a b1 one.txt one; ready a b1
SLP=$((7000 + RANDOM % 2000))
printf '#!/bin/sh\n( sleep %s ) &\necho $! > "%s/gate.grandchild"\necho $$ > "%s/gate.pid"\nsleep %s\n' "$SLP" "$W" "$W" "$SLP" > "$W/gate.sh"
( run >"$W/t.out" 2>&1 ) &
for i in $(seq 1 40); do [ -s "$W/gate.pid" ] && break; sleep 0.5; done          # wait until the gate is really running
gp=$(cat "$W/gate.pid" 2>/dev/null)
lander=$(cat "$W"/lander/logs/run-*/pid 2>/dev/null | head -1)      # the lander writes its own pid next to its logs
kill -TERM "$lander"; sleep 3
eq "T21 gate process is dead" "$(kill -0 "$gp" 2>/dev/null && echo alive || echo dead)" dead
eq "T21 no stray grandchild left" "$(kill -0 "$(cat "$W/gate.grandchild")" 2>/dev/null && echo alive || echo dead)" dead
eq "T21 nothing pushed" "$(count "$W/pushes.log")" 0
eq "T21 READY kept" "$([ -f "$S/ready/b1" ] && echo y || { echo "n:$(cat "$W/t.out" | tr "\n" "|")"; })" y
kill "$(cat "$W/gate.grandchild" 2>/dev/null)" 2>/dev/null; true

echo "T22 (#7) fixture-manifest and lease errors are environment failures, not the branch's"
for msg in "global fixture aliases conflict with separate build manifest" "separate build fixture manifest required" "invalid/expired finite DB lease"; do
  new_world
  seat a b1 one.txt one; ready a b1
  printf '#!/bin/sh\necho "[pre-push] %s"\nexit 1\n' "$msg" > "$W/gate.sh"
  out=$(run)
  has "T22 '$msg' -> ENV-FAIL" "$out" "ENV-FAIL"; hasnt "T22 nobody dropped for it" "$out" "DROPPED"
done

echo "T23 (#8) a red baseline drops nobody"
new_world
echo broken > "$C/BADBASE"; git -C "$C" add BADBASE; git -C "$C" commit -qm "red main"; git -C "$C" push -q origin main; : > "$W/pushes.log"
seat a b1 one.txt one; seat b b2 two.txt two; ready a b1; ready b b2
printf '#!/bin/sh\necho gate >> "%s/gates.log"\n[ -f BADBASE ] && { echo "build broken by the baseline"; exit 1; }\nexit 0\n' "$W" > "$W/gate.sh"
out=$(run)
has "T23 baseline named" "$out" "BASELINE-RED"
hasnt "T23 nobody dropped" "$out" "DROPPED"
eq "T23 both still READY" "$(ls "$S/ready" | wc -l | tr -d ' ')" 2
eq "T23 no push" "$(count "$W/pushes.log")" 0
# control: with a green baseline a real culprit is still dropped
new_world
seat a b1 one.txt one; seat b b2 BAD broken; ready a b1; ready b b2
out=$(run); has "T23 control: green baseline, culprit dropped" "$out" "DROPPED b2"; eq "T23 control: good branch landed" "$(on_origin fleet/a-b1)" yes

echo "T24 (#10) ready registers only commits that name the approved bean"
new_world
seat a b1 one.txt one
wt=$W/shared; git -C "$C" worktree add -q "$wt" fleet/a-b1; echo other > "$wt/other.txt"; git -C "$wt" add -A; git -C "$wt" commit -qm "feat(zzzz): unrelated unapproved work"; git -C "$C" worktree remove --force "$wt"; git -C "$C" push -q origin fleet/a-b1
o=$(BL_BRANCH_OF=fleet/a-b1 bl "$BL" ready a b1 2>&1); rc=$?
eq "T24 mixed branch refused" "$([ $rc -ne 0 ] && echo y)" y; has "T24 names the offending commit" "$o" "unrelated unapproved work"
eq "T24 not READY" "$([ -f "$S/ready/b1" ] && echo y || echo n)" n
new_world
seat a b1 one.txt one
o=$(BL_BRANCH_OF=fleet/a-b1 bl "$BL" ready a b1 2>&1); has "T24 control: clean branch READY" "$o" "READY b1"

echo "T25 (e) a fresh install carries every lander tool the watcher invokes"
for tool in $(grep -o 'local/bin/fleet-batch-land' "$ROOT/bin/fleet-watch" | sort -u | sed 's#local/bin/##'); do
  eq "T25 install.sh copies $tool" "$(grep -c "cp \"\$ROOT/bin/$tool\"" "$ROOT/install.sh")" 1
  eq "T25 install.sh makes $tool executable" "$(grep -c "chmod +x.*\.local/bin/$tool" "$ROOT/install.sh")" 1
done

echo "T26 (b) batch mode honors land-paused, like the old landing paths do"
new_world
seat a b1 one.txt one; ready a b1
touch "$S/land-paused"
out=$(run); has "T26 run says it is paused" "$out" "land-paused"; eq "T26 no push while paused" "$(count "$W/pushes.log")" 0
eq "T26 READY kept while paused" "$([ -f "$S/ready/b1" ] && echo y)" y
out=$(BL_K=1 bl "$BL" tick 2>&1); eq "T26 tick lands nothing while paused" "$(count "$W/pushes.log")" 0
out=$(run --dry); has "T26 --dry still allowed while paused" "$out" "DRY"
rm -f "$S/land-paused"; out=$(run); has "T26 resumes when the pause is lifted" "$out" "LANDED b1"

echo "T27 (c) a landed bean consumes its approval (it must stop counting as outstanding WIP); an unproven one keeps it"
new_world
seat a b1 one.txt one; seat b b2 two.txt two; ready a b1; ready b b2
touch "$S/approved/b1" "$S/approved/b2"
out=$(run)
eq "T27 b1 approval consumed" "$([ -e "$S/approved/b1" ] && echo kept || echo gone)" gone
eq "T27 b2 approval consumed" "$([ -e "$S/approved/b2" ] && echo kept || echo gone)" gone
new_world
seat a b1 one.txt one; ready a b1; touch "$S/approved/b1"
out=$(BL_PUSH_CMD=true run)
eq "T27 push did not stick: approval kept" "$([ -e "$S/approved/b1" ] && echo kept || echo gone)" kept

echo "T28 (a) SIGKILL of the lander must not free the lock while its gate still runs: a second lander cannot start (no 4 s grace, no overlap)"
new_world
seat a b1 one.txt one; ready a b1
printf '#!/bin/sh\nif ! mkdir "%s/busy" 2>/dev/null; then echo OVERLAP >> "%s/overlap.log"; exit 1; fi\necho $$ > "%s/gate.pid"\nsleep 5\necho gate >> "%s/gates.log"\nrmdir "%s/busy"\nexit 0\n' "$W" "$W" "$W" "$W" "$W" > "$W/gate.sh"
: > "$W/overlap.log"
( run >"$W/k.out" 2>&1 ) & KP=$!
for i in $(seq 1 40); do [ -s "$W/gate.pid" ] && break; sleep 0.25; done
lpid=$(cat "$W"/lander/logs/run-*/pid 2>/dev/null | head -1); kill -9 "$lpid"; wait "$KP" 2>/dev/null
out=$(run); rc=$?                                   # immediately: the old gate (5 s) is still running
has "T28 second lander is refused while the old gate lives" "$out" "still running"
eq "T28 no overlapping gate" "$(count "$W/overlap.log")" 0
eq "T28 nothing was pushed by the second lander" "$(count "$W/pushes.log")" 0
for i in $(seq 1 40); do [ -d "$W/busy" ] || break; sleep 0.5; done
out=$(run); has "T28 once the old gate has ended, landing works" "$out" "LANDED b1"

echo "T29 (#2) the ownership marker dies with the worktree: replacing the worktree at the same path hands the lander no authority over its new occupant"
new_world
seat a b1 one.txt one; ready a b1; run >/dev/null
git -C "$C" worktree remove --force "$W/lander/wt"
git -C "$C" worktree add -q "$W/lander/wt" -b occupant origin/main
echo precious > "$W/lander/wt/untracked.txt"; echo edit >> "$W/lander/wt/base.txt"
seat b b2 two.txt two; ready b b2
out=$(run)
has "T29 refused as not owned" "$out" "not owned"
eq "T29 occupant's untracked file intact" "$(cat "$W/lander/wt/untracked.txt" 2>/dev/null)" precious
eq "T29 occupant's tracked edit intact" "$(grep -c '^edit$' "$W/lander/wt/base.txt")" 1
eq "T29 nothing pushed by the second run" "$(count "$W/pushes.log")" 1

echo "T30 (#1) the batch path injects no global test-database URL when a fixture manifest is supplied"
for var in PREPUSH_DB_FIXTURES PREPUSH_BUILD_FIXTURES; do
  new_world
  mkdir -p "$C/scripts"; printf '#!/bin/sh\necho up >> "%s/dbup.log"\necho "export MIGRATION_TEST_DATABASE_URL=postgres://x/y_test"\necho "export TEMPLATE_PARITY_DATABASE_URL=postgres://x/y_test"\n' "$W" > "$C/scripts/test-db-up.sh"; chmod +x "$C/scripts/test-db-up.sh"
  git -C "$C" add scripts; git -C "$C" commit -qm "db helper"; git -C "$C" push -q origin main
  : > "$W/dbup.log"
  seat a b1 one.txt one; ready a b1
  printf '#!/bin/sh\necho "db=${MIGRATION_TEST_DATABASE_URL:-unset}" >> "%s/gate-env.log"\nexit 0\n' "$W" > "$W/gate.sh"; : > "$W/gate-env.log"
  export "$var"=/nonexistent/manifest.json
  out=$(BL_TESTDB_UP=scripts/test-db-up.sh run); unset "$var"
  eq "T30 $var set: test-db-up not run" "$(count "$W/dbup.log")" 0
  eq "T30 $var set: gate sees no injected URL" "$(cat "$W/gate-env.log")" "db=unset"
done
new_world
mkdir -p "$C/scripts"; printf '#!/bin/sh\necho up >> "%s/dbup.log"\necho "export MIGRATION_TEST_DATABASE_URL=postgres://x/y_test"\necho "export TEMPLATE_PARITY_DATABASE_URL=postgres://x/y_test"\n' "$W" > "$C/scripts/test-db-up.sh"; chmod +x "$C/scripts/test-db-up.sh"
git -C "$C" add scripts; git -C "$C" commit -qm "db helper"; git -C "$C" push -q origin main; : > "$W/dbup.log"
seat a b1 one.txt one; ready a b1
printf '#!/bin/sh\necho "db=${MIGRATION_TEST_DATABASE_URL:-unset}" >> "%s/gate-env.log"\nexit 0\n' "$W" > "$W/gate.sh"; : > "$W/gate-env.log"
out=$(BL_TESTDB_UP=scripts/test-db-up.sh run)
eq "T30 control, no manifest: test-db-up runs once" "$(count "$W/dbup.log")" 1
eq "T30 control: gate sees the URL" "$(cat "$W/gate-env.log")" "db=postgres://x/y_test"

echo "T31 (#10) a bean named only in a commit BODY does not register the commit under that bean's approval"
new_world
seat a b1 one.txt one
wt=$W/shared; git -C "$C" worktree add -q "$wt" fleet/a-b1; echo two > "$wt/two.txt"; git -C "$wt" add -A
git -C "$wt" commit -qm "feat(b2): unapproved change" -m "Depends on b1 and follows its approach."; git -C "$C" worktree remove --force "$wt"; git -C "$C" push -q origin fleet/a-b1
o=$(BL_BRANCH_OF=fleet/a-b1 bl "$BL" ready a b1 2>&1); rc=$?
eq "T31 body-only mention refused" "$([ $rc -ne 0 ] && echo y)" y; has "T31 names the offending commit" "$o" "unapproved change"
new_world
seat a b1 one.txt one
mkdir -p "$W/bw"; git -C "$C" worktree add -q "$W/bw" fleet/a-b1; mkdir -p "$W/bw/.beans"; echo x > "$W/bw/.beans/b1--thing.md"; git -C "$W/bw" add -A; git -C "$W/bw" commit -qm "chore: record progress"; git -C "$C" worktree remove --force "$W/bw"; git -C "$C" push -q origin fleet/a-b1
o=$(BL_BRANCH_OF=fleet/a-b1 bl "$BL" ready a b1 2>&1); has "T31 control: a commit that only touches the bean's own file is that bean's" "$o" "READY b1"

echo "T32 (#9) a patch-equivalent second bean is recorded LANDED only if the fetched target really has its change"
new_world
seat a b1 one.txt same; seat b b2 one.txt same
ready a b1; ready b b2
out=$(BL_PUSH_CMD=true run)
eq "T32 push did not stick: b1 not recorded" "$([ -e "$S/landed/b1" ] && echo y || echo n)" n
eq "T32 push did not stick: b2 (skipped as equivalent) not recorded" "$([ -e "$S/landed/b2" ] && echo y || echo n)" n
eq "T32 both stay READY for the retry" "$(ls "$S/ready" | wc -l | tr -d ' ')" 2
hasnt "T32 never prints LANDED" "$out" "LANDED"
new_world
seat a b1 one.txt same; seat b b2 one.txt same
ready a b1; ready b b2
out=$(run)
eq "T32 control: one push" "$(count "$W/pushes.log")" 1
eq "T32 control: b1 landed" "$([ -s "$S/landed/b1" ] && echo y)" y
eq "T32 control: b2 landed, proven against the fetched target" "$([ -s "$S/landed/b2" ] && echo y)" y
has "T32 control: b2's proof says the target has it" "$(cat "$S/landed/b2")" "verified on origin/main"

echo "T33 (#7) fixture/lease refusals are classified from the receipts the validator writes, not only from printed text"
new_world
seat a b1 one.txt one; ready a b1
printf '#!/bin/sh\necho gate >> "%s/gates.log"\nmkdir -p "$BL_RECEIPT_DIR"; echo '"'"'{"code":"E_TARGET","message":"[redacted]"}'"'"' > "$BL_RECEIPT_DIR/failure.json"\necho "[pre-push] bounded lane gate refused (see retained job/JSON receipts; fixture values redacted)"\nexit 1\n' "$W" > "$W/gate.sh"
out=$(run)
has "T33 receipt-only refusal is ENV-FAIL" "$out" "ENV-FAIL"; hasnt "T33 nobody dropped for it" "$out" "DROPPED"
eq "T33 READY kept" "$([ -f "$S/ready/b1" ] && echo y)" y; eq "T33 no push" "$(count "$W/pushes.log")" 0
new_world
seat a b1 one.txt one; ready a b1
printf '#!/bin/sh\necho "[pre-push] bounded lane gate refused (see retained job/JSON receipts; fixture values redacted)"\nexit 1\n' > "$W/gate.sh"
out=$(run); has "T33 the validator's generic refusal line alone is ENV-FAIL too" "$out" "ENV-FAIL"; hasnt "T33 ...and drops nobody" "$out" "DROPPED"
new_world
seat a b1 BAD broken; ready a b1
out=$(run); has "T33 control: a real build failure is still the branch's" "$out" "DROPPED b1"

echo "T34 (#8) the baseline covers the frontend build, and a test failure that names no file cannot yield a green baseline"
mk_fe_world() {
  new_world
  mkdir -p "$C/backend" "$C/frontend" "$W/stubbin"; echo '{}' > "$C/backend/package.json"; echo '{}' > "$C/frontend/package.json"
  [ -n "${1:-}" ] && : > "$C/frontend/BADFRONT"
  git -C "$C" add -A; git -C "$C" commit -qm "projects"; git -C "$C" push -q origin main
  printf '#!/bin/sh\n[ "$1" = run ] && [ -f BADFRONT ] && { echo "frontend build FAILED"; exit 1; }\nexit 0\n' > "$W/stubbin/npm"; chmod +x "$W/stubbin/npm"
  printf '#!/bin/sh\nexit 0\n' > "$W/stubbin/npx"; chmod +x "$W/stubbin/npx"
  printf '#!/bin/sh\necho gate >> "%s/gates.log"\nif [ -f frontend/BADFRONT ]; then echo "[pre-push] frontend build FAILED — push refused"; exit 1; fi\nexit 0\n' "$W" > "$W/gate.sh"
}
blx() { PATH="$W/stubbin:$PATH" BL_REPO=$C BL_STATE=$S BL_WT_ROOT=$W/lander BL_LEDGER=$W/ledger BL_REPORTS=$W/reports BL_REQUIRE_APPROVED=0 BL_REQUIRE_REPORT=0 BL_GATE_CMD="$W/gate.sh" BL_NOTIFY_CMD=$W/notify.sh BL_LINK_DIRS=none BL_BASELINE_CMD='for p in ${BL_BASELINE_PROJECTS:-backend frontend}; do [ -f "$p/package.json" ] || continue; ( cd "$p" && npm run build --silent ) || exit 1; done; for p in ${BL_BASELINE_PROJECTS:-backend frontend}; do [ -f "$p/package.json" ] && [ -n "$BL_FAILING_FILES" ] || continue; ( cd "$p" && NODE_OPTIONS=--experimental-vm-modules npx jest --runInBand --silent --passWithNoTests $BL_FAILING_FILES ) || exit 1; done' "$BL" "$@"; }
mk_fe_world red
seat a b1 one.txt one; seat b b2 two.txt two; BL_BRANCH_OF=fleet/a-b1 blx ready a b1 >/dev/null; BL_BRANCH_OF=fleet/b-b2 blx ready b b2 >/dev/null
out=$(blx run 2>&1)
has "T34 pre-existing frontend failure: baseline red" "$out" "BASELINE-RED"; hasnt "T34 innocent branches not dropped" "$out" "DROPPED"
eq "T34 both READY" "$(ls "$S/ready" | wc -l | tr -d ' ')" 2
mk_fe_world
seat a b1 BAD broken; BL_BRANCH_OF=fleet/a-b1 blx ready a b1 >/dev/null
printf '#!/bin/sh\nif [ -f BAD ]; then echo "backend tests FAILED"; exit 1; fi\nexit 0\n' > "$W/gate.sh"
out=$(blx run 2>&1)
has "T34 a test failure naming no file: cannot attribute, holds instead of dropping" "$out" "cannot attribute"; hasnt "T34 ...and drops nobody" "$out" "DROPPED"
mk_fe_world
seat a b1 BAD broken; BL_BRANCH_OF=fleet/a-b1 blx ready a b1 >/dev/null
printf '#!/bin/sh\nif [ -f BAD ]; then echo "FAIL src/x.test.ts"; echo "backend tests FAILED"; exit 1; fi\nexit 0\n' > "$W/gate.sh"
out=$(blx run 2>&1)
has "T34 control: a named failing file, green baseline: the branch is dropped" "$out" "DROPPED b1"

mk_fe_world
seat a b1 BAD broken; BL_BRANCH_OF=fleet/a-b1 blx ready a b1 >/dev/null
printf '#!/bin/sh\necho "$@" >> "%s/npx.log"\nexit 0\n' "$W" > "$W/stubbin/npx"; : > "$W/npx.log"
printf '#!/bin/sh\nif [ -f BAD ]; then mkdir -p "$BL_RECEIPT_DIR"; echo '"'"'{"testResults":[{"name":"/x/frontend/src/only-in-receipt.test.tsx","status":"failed"}]}'"'"' > "$BL_RECEIPT_DIR/jest.json"; echo "backend tests FAILED"; exit 1; fi\nexit 0\n' > "$W/gate.sh"
out=$(blx run 2>&1)
has "T34 a failure held only in a jest receipt reaches the baseline run" "$(cat "$W/npx.log")" "src/only-in-receipt.test.tsx"
has "T34 ...and the green baseline lets the branch be dropped" "$out" "DROPPED b1"

echo "T35 the lander SIGKILLed between forking the gate child and the child taking the group lock: the orphan must not start a gate on the successor's worktree"
new_world
seat a b1 one.txt one; ready a b1
printf '#!/bin/sh\necho started >> "%s/orphan-gate.log"\nsleep 1\nexit 0\n' "$W" > "$W/gate.sh"; : > "$W/orphan-gate.log"
( BL_TEST_CHILD_DELAY=3 run >"$W/k.out" 2>&1 ) & KP=$!
for i in $(seq 1 40); do ls "$W"/lander/logs/run-*/pid >/dev/null 2>&1 && break; sleep 0.1; done; sleep 1
lpid=$(cat "$W"/lander/logs/run-*/pid 2>/dev/null | head -1); kill -9 "$lpid"; wait "$KP" 2>/dev/null
sleep 4                                                   # the orphaned child wakes at 3 s
eq "T35 the orphan did not run the gate" "$(count "$W/orphan-gate.log")" 0

echo "T36 (N1) a lane-runner refusal that says a TEST failed is the branch's; a refusal about the fixtures is the environment's"
new_world
seat a b1 one.txt one; ready a b1
printf '#!/bin/sh\nmkdir -p "$BL_RECEIPT_DIR"; echo '"'"'{"code":"E","message":"Jest failure/incomplete result"}'"'"' > "$BL_RECEIPT_DIR/failure.json"\necho "[pre-push] bounded lane gate refused (see retained job/JSON receipts; fixture values redacted)"\nexit 1\n' > "$W/gate.sh"
out=$(run); has "T36 a jest-failure receipt drops the branch" "$out" "DROPPED b1"
new_world
seat a b1 one.txt one; ready a b1
printf '#!/bin/sh\necho "FAIL src/x.test.ts"\necho "[pre-push] bounded lane gate refused (see retained job/JSON receipts; fixture values redacted)"\nexit 1\n' > "$W/gate.sh"
out=$(run); has "T36 a refusal line next to a FAIL line is the branch's" "$out" "DROPPED b1"

echo "T37 (N2) the baseline replays only the project the gate named: an unrelated red frontend must not block a backend regression"
mk_fe_world red
seat a b1 BAD broken; BL_BRANCH_OF=fleet/a-b1 blx ready a b1 >/dev/null
printf '#!/bin/sh\nif [ -f BAD ]; then echo "backend build FAILED — push refused"; exit 1; fi\nexit 0\n' > "$W/gate.sh"
out=$(blx run 2>&1)
has "T37 backend regression is dropped although the frontend baseline is red" "$out" "DROPPED b1"; hasnt "T37 ...not BASELINE-RED" "$out" "BASELINE-RED"

echo
echo "fleet-batch-land: $PASS passed, $FAILN failed"
[ "$FAILN" -eq 0 ]
