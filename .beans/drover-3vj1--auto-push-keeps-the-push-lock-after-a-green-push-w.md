---
# drover-3vj1
title: auto_push keeps the push lock after a green push when it took the lock over
status: todo
type: bug
priority: normal
created_at: 2026-10-12T13:04:29Z
updated_at: 2026-10-12T13:04:29Z
---

panel2 watcher log (~/.local/share/drover/projects/panel2/logs/fleet-watch.out), 2026-10-12:

    13:50:58 AUTO-PUSH: took over stale push lock (owner 3331409 gone, age 415s)
    13:51:40 AUTO-PUSH: 2 commit(s) -> origin (full-suite green)
    14:03:38 AUTO-PUSH: took over stale push lock (owner 3423551 gone, age 760s)

The lock taken over at 13:50:58 was still there at 14:03:38 (age 760 s = created 13:50:58), although the push at 13:51:40 succeeded. auto_land skips every tick while state/.push-lock exists (bin/fleet-watch, auto_land guard), so three approved beans waited 12 minutes for nothing. The same happened at 13:19:30 (age 208 s) and 13:50:58 (age 415 s).

Expected: a green or failed push removes the lock it holds, including a lock it took over. Check the takeover path in auto_push: the owner pid written into the lock is probably the subshell that exits before the push finishes, or the cleanup trap runs in a different process than the one that holds the lock.

- [ ] after a green push the lock is gone within one tick
- [ ] after a failed push the lock is gone within one tick
- [ ] eval check: simulate a takeover and a green push; assert no lock remains
