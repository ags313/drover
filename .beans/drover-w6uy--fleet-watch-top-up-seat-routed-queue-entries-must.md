---
# drover-w6uy
title: 'fleet-watch top_up: seat-routed queue entries must not starve the plain queue'
status: todo
type: bug
priority: high
created_at: 2026-10-16T03:25:56Z
updated_at: 2026-10-16T03:25:56Z
---

Facts (bob, 2026-10-16 03:50 to 04:30): bob-4s70 (tag `seat:bob-qwen27-coder`) sat in the queue while that seat was busy with another bean. `top_up_queue` (bin/fleet-watch) sets `only_routed=1` whenever the queue directory is non-empty, so plain beans enter 'only an empty queue': for 40 minutes six ready plain beans (G1 G4, L1 A4, A5, A6, …) were never enqueued and four automatic coders idled behind `queue empty but for seat-routed beans — nothing for bob-codex-coder`, every tick. The lead removed the tag by hand to unblock the fleet.

Rule: a queue that holds only seat-routed entries counts as empty for plain beans. Routed entries wait for their seat; they never gate the plain top-up. Keep the existing rule that a plain bean enters only when no plain entry is queued (that is what 'empty queue' meant).

## Steps

1. `only_routed`: compute it from the queue entries WITHOUT a routing note (plain entries), not from the directory being non-empty.
2. Refill: unchanged (plain coders skip routed entries already).
3. eval/eval-checkers.sh: a case with one routed entry waiting and a ready plain bean: the plain bean is enqueued and dispatched to an idle automatic coder.

## Acceptance

- [ ] with a routed entry waiting for a busy manual seat, ready plain beans are still enqueued every tick
- [ ] no change when the queue holds plain entries; eval green; shellcheck clean
