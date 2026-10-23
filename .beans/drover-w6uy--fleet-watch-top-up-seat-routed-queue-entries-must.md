---
# drover-w6uy
title: 'fleet-watch top_up: seat-routed queue entries must not starve the plain queue'
status: completed
type: bug
priority: high
created_at: 2026-10-16T03:25:56Z
updated_at: 2026-10-23T13:45:48Z
---

Facts (bob, 2026-10-16 03:50 to 04:30): bob-4s70 (tag `seat:bob-qwen27-coder`) sat in the queue while that seat was busy with another bean. `top_up_queue` (bin/fleet-watch) sets `only_routed=1` whenever the queue directory is non-empty, so plain beans enter 'only an empty queue': for 40 minutes six ready plain beans (G1 G4, L1 A4, A5, A6, …) were never enqueued and four automatic coders idled behind `queue empty but for seat-routed beans — nothing for bob-codex-coder`, every tick. The lead removed the tag by hand to unblock the fleet.

Rule: a queue that holds only seat-routed entries counts as empty for plain beans. Routed entries wait for their seat; they never gate the plain top-up. Keep the existing rule that a plain bean enters only when no plain entry is queued (that is what 'empty queue' meant).

## Steps

1. `only_routed`: compute it from the queue entries WITHOUT a routing note (plain entries), not from the directory being non-empty.
2. Refill: unchanged (plain coders skip routed entries already).
3. eval/eval-checkers.sh: a case with one routed entry waiting and a ready plain bean: the plain bean is enqueued and dispatched to an idle automatic coder.

## Acceptance

- [x] with a routed entry waiting for a busy manual seat, ready plain beans are still enqueued every tick
- [x] no change when the queue holds plain entries; eval green; shellcheck clean

Validation: `nix-shell --run 'bash eval/eval-checkers.sh'` passes, including routed-only top-up, plain-entry gating, and dispatch on successive ticks while the manual seat stays busy. `shellcheck -x -P bin bin/fleet-watch` passes; eval script warning diagnostics are unchanged from the baseline.

## Summary of Changes

Rebased onto nixos-multiproject and committed e3fa865 (fix(fleet-watch): allow plain top-up behind seat-routed entries). top_up_queue now gates plain admissions only on queue files without routing notes; routed-only queues admit plain work while the manual seat remains busy. Refill is unchanged. Added regression coverage for routed-only admission, dispatch to an idle automatic coder, successive-tick top-up, and preserving the existing plain-entry gate. Updated the old fixture to complete its plain bean before freeing its seat. Both bean acceptance items are checked and committed. Worktree is clean; nothing pushed.

Validation: bob check passed on the final commit e3fa865: nix-shell --run 'bash eval/eval-checkers.sh'. shellcheck -x -P bin bin/fleet-watch passes. The eval script has no additional warning diagnostics compared with its existing baseline.
