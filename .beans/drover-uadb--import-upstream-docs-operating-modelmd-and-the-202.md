---
# drover-uadb
title: 'Import upstream docs: OPERATING-MODEL.md and the 2026-10-12/13 LESSONS sections'
status: todo
type: task
priority: normal
created_at: 2026-10-13T21:08:07Z
updated_at: 2026-10-13T21:08:07Z
---

Import the documentation from upstream (remote `origin` = andrebrov/drover, commits e6d9d54, 2c92453, 8479c6b): `docs/OPERATING-MODEL.md` (new) and the four new `docs/LESSONS.md` sections ("Batch lander ...", "Assignment, queue and daemon rules (2026-10-12 retro)", "Cadence rules (2026-10-13)", "Landing is guaranteed by three machines ...").

Scope: documentation only. No scripts, no config keys, no launchd files from those commits (fleet-refill, fleet-feed, fleet-batch, fleet-batch-land, fleet-done gate, fleet-preflight, fleet-cred-check are not adopted: this fork runs fleet-watch under systemd and lands per bean).

How:
- `git diff <merge-base> origin/main -- docs/LESSONS.md` applies on top of our LESSONS.md (it auto-merges in a dry run); `docs/OPERATING-MODEL.md` is new.
- Add one line at the top of OPERATING-MODEL.md: which parts this fork does not run (batch lander, refill daemon, publish mode), with a pointer to fleet-watch.
- Link OPERATING-MODEL.md from README's docs list.
- Commit message is ours: no co-author trailers from upstream.

Acceptance:
- [ ] both files present, README links the new doc
- [ ] the fork note at the top of OPERATING-MODEL.md names what we do not run
