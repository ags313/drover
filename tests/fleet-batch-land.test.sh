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
  BL_REQUIRE_APPROVED=0 BL_REQUIRE_REPORT=0 BL_GATE_CMD="$W/gate.sh" BL_NOTIFY_CMD=$W/notify.sh BL_BASELINE_CMD='[ ! -f BADBASE ]' BL_LINK_DIRS='node_modules backend/node_modules' DROVER_ENV_FAIL_RE='fixture (manifest|aliases)|separate build|(invalid|expired).*lease' "$@"; }
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
eq "T20 no two gates overlapped" "$(count "$W/overlap.log")" 0
eq "T20 exactly one push" "$(count "$W/pushes.log")" 1
eq "T20 the others said they were locked out" "$(cat "$W"/c*.out | grep -c 'holds the lock')" 5
new_world
seat a b1 one.txt one; ready a b1
printf '#!/bin/sh\necho $$ > "%s/gate.pid"\nsleep 3\nexit 0\n' "$W" > "$W/gate.sh"
( run >"$W/k.out" 2>&1 ) & sleep 2
lpid=$(pgrep -f "fleet-batch-land run" | head -1); [ -n "$lpid" ] && pkill -9 -f "fleet-batch-land run" ; wait 2>/dev/null
sleep 4
out=$(run); has "T20 lock released by the kill; next run lands" "$out" "LANDED b1"

echo "T21 (#5) SIGTERM kills the gate's whole process group before the lock is released"
new_world
seat a b1 one.txt one; ready a b1
SLP=7$RANDOM$RANDOM
printf '#!/bin/sh\n( sleep %s ) &\necho $$ > "%s/gate.pid"\nsleep %s\n' "$SLP" "$W" "$SLP" > "$W/gate.sh"
( run >"$W/t.out" 2>&1 ) &
for i in $(seq 1 40); do [ -s "$W/gate.pid" ] && break; sleep 0.5; done          # wait until the gate is really running
gp=$(cat "$W/gate.pid" 2>/dev/null)
lander=$(cat "$W"/lander/logs/run-*/pid 2>/dev/null | head -1)      # the lander writes its own pid next to its logs
kill -TERM "$lander"; sleep 3
eq "T21 gate process is dead" "$(kill -0 "$gp" 2>/dev/null && echo alive || echo dead)" dead
eq "T21 no stray grandchild left" "$(pgrep -f "sleep $SLP" | wc -l | tr -d ' ')" 0
eq "T21 nothing pushed" "$(count "$W/pushes.log")" 0
eq "T21 READY kept" "$([ -f "$S/ready/b1" ] && echo y)" y
pkill -f "sleep $SLP" 2>/dev/null; true

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

echo
echo "fleet-batch-land: $PASS passed, $FAILN failed"
[ "$FAILN" -eq 0 ]
