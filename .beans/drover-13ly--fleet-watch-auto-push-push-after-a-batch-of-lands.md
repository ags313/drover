---
# drover-13ly
title: 'fleet-watch auto-push: push after a batch of lands, not after every land'
status: in-progress
type: feature
priority: normal
created_at: 2026-10-12T19:41:45Z
updated_at: 2026-10-12T21:47:29Z
---

Today `auto_push` in `bin/fleet-watch` pushes as soon as local main is ahead of origin, so every landed bean is one push and one CI run. panel2 made 42 pushes on 2026-10-12. The user asked for a push after a batch has accumulated.

Add two settings in `bin/drover-env`, documented in README. Defaults keep today's behaviour.

- `DROVER_PUSH_MIN_AHEAD` (default 1): `auto_push` returns early while `git rev-list --count upstream..HEAD` is below this value.
- `DROVER_PUSH_MAX_WAIT_MIN` (default 0 = off): when the oldest unpushed commit on main is older than this many minutes, push even below the minimum, so one bean never waits overnight. Use the commit time of the first commit in `upstream..HEAD`.

Rules:
- `fleet-push` (manual) ignores both settings.
- The INVENTORY WARN cap (`state/inventory-warn`) stays as it is.
- A cumulative RED still pauses landing as today; the settings only delay the start of the verify+push.

Tests (`eval/eval-checkers.sh`): a copy of fleet-watch beside a stub verify; main 2 ahead with `DROVER_PUSH_MIN_AHEAD=3` -> no push; 3 ahead -> push; 1 ahead and the commit older than `DROVER_PUSH_MAX_WAIT_MIN` -> push.

Acceptance:
- [ ] `DROVER_PUSH_MIN_AHEAD=5` on panel2: five lands make one push
- [x] `DROVER_PUSH_MAX_WAIT_MIN=60`: a single land is pushed within 60 minutes
- [x] defaults unchanged: eval cases for the old behaviour still pass
- [x] README documents both settings next to `DROVER_AUTOLAND`

## Returned to todo by fleet-ghost-reap (2026-10-12)

This bean sat in-progress with no seat, task, review or owner, so dispatch could not see it. Someone started it before: **check what is already on main and on any `fleet/*-drover-13ly` branch before writing code**, finish what is missing, and verify every checklist item.



Lead 2026-10-12: implementation reviewed (codex: CHANGES only for the unverified live item). The panel2 live check (DROVER_PUSH_MIN_AHEAD=5: five lands make one push) is the lead's step after landing, not a coder task. Bean approved for landing; the coder is not re-dispatched.
