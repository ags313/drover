---
# drover-3lof
title: 'fleet-watch: a BLOCKED bean is re-dispatched every tick (forum-21u3 x54, drover-13ly x36)'
status: todo
type: bug
priority: high
created_at: 2026-10-12T20:33:31Z
updated_at: 2026-10-12T20:41:57Z
---

A coder verdict `BLOCKED` does not park the bean. fleet-watch appends the summary to `state/blocked` and logs "BLOCKED needs lead", but the bean stays `todo` on the board, so `top_up_queue` (`beans list --ready`) enqueues it again on the next tick and the same seat gets it again. Each pass costs a full seat run that ends in the same BLOCKED verdict.

Measured in the watch logs on 2026-10-12 (DISPATCH lines per bean): forum-21u3 54, drover-13ly 36, forum-z2d8 25, forum-xbe2 20, forum-2y8t 16, forum-vgfa 13, forum-6mz6 10. The coder reports say so themselves: "22nd dispatch, no change", "dispatch loop pass 35, nothing changed".

Fix, in fleet-watch:
- On `*:BLOCKED`, park the bean: write `state/parked/<bean>` with the summary (and keep the `state/blocked` line). `top_up_queue` skips every parked bean. `fleet-unblock` already digests the pile; it removes the marker when it re-queues a bean or when the lead sets the bean back to todo.
- The lead un-parks with `fleet-watch unpark <bean>` (removes the marker) or by editing the bean (a changed bean file mtime newer than the marker also lifts it).
- A bean that comes back BLOCKED twice with the same summary is never re-dispatched by top-up until un-parked.

Tests (`eval/eval-checkers.sh`): a stub seat that answers BLOCKED; two ticks -> one DISPATCH; after `unpark` -> a second DISPATCH. The old noop-held path keeps its cases.

Acceptance:
- [x] a BLOCKED bean is dispatched once, not every tick
- [x] `fleet-watch unpark <bean>` re-queues it
- [x] eval cases pass; existing cases unchanged
- [x] README: the parked state and the unpark verb under the BLOCKED section
