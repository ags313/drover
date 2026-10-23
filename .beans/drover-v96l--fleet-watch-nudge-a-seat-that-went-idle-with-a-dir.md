---
# drover-v96l
title: 'fleet-watch: nudge a seat that went idle with a dirty worktree and no announcement'
status: completed
type: feature
priority: normal
created_at: 2026-10-16T05:56:24Z
updated_at: 2026-10-23T12:49:06Z
---

Facts (panel2, 2026-10-16): the opencode seat `panel2-qwen27-coder` (qwen3.8:27b on a remote ollama) twice ended its turn after editing package.json and package-lock.json without committing, reporting or announcing (panel2-bxfk at 02:05, panel2-q1eo at 06:06); the seat sat 'done' for 50 minutes each time until the lead sent a one-line finish instruction, after which it completed and the bean landed. The watcher only acts on announcements, so a silent stop is invisible to it.

Rule: a seat that is idle for N minutes (default 5) while its worktree has uncommitted tracked changes or commits not on its bean's base, with no DONE/BLOCKED/PARTIAL announcement for its task, gets one nudge: 'finish <bean>: run the gate, commit, report, announce with fleet-done'. One nudge per task; a second silent stop flags the bean for the lead (`needs lead: silent seat`). Log `NUDGE <seat> <bean>`.

## Acceptance

- [x] eval case: idle seat, dirty worktree, no announcement for 5 min → one NUDGE line and a prompt sent; after a second silent stop the bean is flagged, no further nudges
- [x] a seat that announced is never nudged; shellcheck clean

## Summary of Changes

Addressed both required review findings in commit 036fe5f.

silent_seats now checks the task checksum before announcement suppression. A changed task clears the old announced marker and idle timer, while preserving the per-bean nudge limit. Added regression coverage proving a drained DONE suppresses the same task, but a new dispatch timestamp for the same bean with a dirty worktree receives exactly one nudge after five idle minutes.

Updated both default help branches to sed -n '2,31p', with an eval confirming enqueue and queue are included.

ShellCheck passes: shellcheck -x -P bin bin/fleet-watch. bob check passed on final commit 036fe5f: nix-shell --run 'bash eval/eval-checkers.sh', including all new regressions. Both bean acceptance items remain checked; worktree clean; no push.

The optional reviewer-specific wording adjustment is unchanged; this revision addresses the two required findings.
