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
#   completed-audit     rewritten patch / superseded duplicate seat / squash subjects -> quiet; reverted code -> flagged
#   branch-landed        squash-landed branch -> exit 0 by subject; a new bean commit -> exit 1, AGE, its subject (wip:
#                        and no-bean commits ignored; --all counts both; a one-parent "Merge ..." commit counts);
#                        fleet landable says MERGE landed and
#                        fleet-land-bean refuses that branch; an unlanded branch stays clean
# Cases live in eval/cases/NNN-<area>.sh, sourced in name order. A new case goes at the end of its area's file, or in a new file with a free NNN; describe it at the top of that file, not in this list.
# No network, no keys. Exit 1 on the first wrong answer.
set -uo pipefail
# shellcheck disable=SC2034  # used by the case files sourced below
BIN="$(cd "$(dirname "$0")/../bin" && pwd)"
CASES="$(cd "$(dirname "$0")/cases" && pwd)"
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

shopt -s nullglob
cases=("$CASES"/[0-9][0-9][0-9]-*.sh)
[ "${#cases[@]}" -gt 0 ] || { echo "FAIL  no case files in $CASES"; exit 1; }
# shellcheck disable=SC1090  # the case files; lint.sh checks each one on its own
for c in "${cases[@]}"; do . "$c"; done

[ "$fail" = 0 ] && echo 'all checker cases pass' || { echo 'checker cases FAILED'; exit 1; }
