---
# drover-2kiu
title: 'fleet-watch and fleet-push: pull origin main into local main from time to time'
status: todo
type: feature
priority: normal
tags:
    - watcher
created_at: 2026-10-21T19:57:25Z
updated_at: 2026-10-21T19:57:25Z
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

- [ ] `eval/eval-checkers.sh` cases: behind → ff; diverged clean → merge commit; conflict → main untouched and one log line; dirty checkout → skipped; `DROVER_PULL_MIN=0` → no fetch
- [ ] `fleet-push` on a behind main stops with the message, no push attempt
- [ ] README: the `DROVER_PULL_MIN` knob and `fleet pull`
- [ ] the drover gate (`fleet-push` checker suite) is green
