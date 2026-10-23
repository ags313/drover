---
# drover-2kiu
title: 'fleet-watch and fleet-push: pull origin main into local main from time to time'
status: completed
type: feature
priority: normal
tags:
    - watcher
created_at: 2026-10-21T19:57:25Z
updated_at: 2026-10-23T13:41:32Z
---

Owner request (2026-10-21): "drover should be able to pull from time to time".

Problem: nothing in drover fetches. Local main moves only by landings. Commits pushed from elsewhere (the owner's laptop, GitHub merges, dependabot) stay unseen until the lead pulls by hand. Then `fleet-push` is rejected as non-fast-forward, `fleet-completed-audit` ("completed only when the code is on origin/main") reads a stale `origin/main`, and seats merge a main that is behind. Today (bob) the lead merged by hand: `git pull --no-rebase origin main`, then pushed.

Rule:

1. Every `DROVER_PULL_MIN` minutes (default 15; 0 = off) the watcher runs `git fetch -q $DROVER_REMOTE` in `DROVER_REPO`.
2. Local main behind `origin/main` and not ahead, checkout clean: `git merge --ff-only`, log `PULL main <old>..<new> (<n> commits)`.
3. Diverged (local landings not pushed, origin moved): `git merge --no-edit origin/main`; keep it only when it applies with no conflict, log `PULL merged origin/main <sha> into main`. The next `fleet-push` gate verifies the merged tree as it does today.
4. Conflict: main stays as it is; log `PULL CONFLICT origin/main <sha> — lead merges by hand` once per remote tip; one inbox note for the lead.
5. Dirty checkout (tracked changes): skip with one log line; bean-file-only changes count as clean (commit them first, as the lead does: `chore(beans): sync board state`).
6. `fleet-push` fetches first. When main is behind, it stops with `fleet-push: main is behind origin/main — run fleet pull` instead of a rejected push. `fleet pull` runs steps 2 to 4 once, by hand.

Seats do not change: `fleet sync` moves their worktrees after a pull, as now.

## Acceptance

- [x] `eval/eval-checkers.sh` cases: behind → ff; diverged clean → merge commit; conflict → main untouched and one log line; dirty checkout → skipped; `DROVER_PULL_MIN=0` → no fetch
- [x] `fleet-push` on a behind main stops with the message, no push attempt
- [x] README: the `DROVER_PULL_MIN` knob and `fleet pull`
- [x] the drover gate (`fleet-push` checker suite) is green

## Review follow-up

Fetches in both fleet-pull and fleet-push now disable terminal credential prompts and enforce a
60-second process-group deadline (DROVER_FETCH_TIMEOUT_SEC). Pull and push locks with dead owners
are reclaimed immediately; ownerless locks expire after 30 minutes. Live owners are preserved,
and a held lock logs why the pull skipped. Regression cases cover timeouts and descendant cleanup,
retry after timeout, and dead/live/ownerless lock handling with autoland off and observer configured.

## Summary of Changes

Fixed all three review robustness gaps in commit 9651c5e.

1. Shared drover_fetch now bounds both fleet-pull and fleet-push fetches to 60 seconds by default (DROVER_FETCH_TIMEOUT_SEC), disables terminal credential prompts, and kills the whole fetch process group on timeout. The bounded foreground pull cannot hang the watcher indefinitely.
2. Pull locks now record their owner PID. Dead owners are reclaimed immediately; ownerless locks expire after the existing 30-minute push-lock grace. Live owners are preserved regardless of lock age. Contention logs a skip.
3. fleet-pull checks push-lock ownership itself, so dead/aged-ownerless push locks are reclaimed even with autoland disabled or observer mode configured. A held push lock logs a skip.

Added regressions for both fetch timeouts, disabled prompts, descendant termination, successful retry after timeout, and dead/live/fresh-ownerless/aged-ownerless pull and push locks. Updated README and the bean's follow-up notes; all acceptance boxes remain checked. Kept the optional dirty-checkout logging at one line per due pass.

bob check passed on the final commit: nix-shell --run 'bash eval/eval-checkers.sh'. Worktree is clean. No project branch was pushed.
