---
# drover-ecuo
title: 'fleet-watch: dispatch a bean tagged seat:<name> to that manual seat'
status: completed
type: feature
priority: normal
created_at: 2026-10-14T22:32:03Z
updated_at: 2026-10-14T23:07:31Z
---

Facts (bob, panel2, 2026-10-14): a `DROVER_MANUAL_SEATS` seat (`panel2-qwen-coder`, `bob-qwen-coder`: opencode on a local ollama model) gets work only from the lead's `fleet assign`. Every ready bean is queued and handed to an automatic coder within one tick, so the lead has to hold a bean out of the queue (status `draft`), watch for its blockers to land, flip it and assign by hand. On bob the lead holds five size-S steps this way (tag `qwen`).

Goal: a bean that names a seat is dispatched to that seat by the watcher, and to no other seat, as soon as it is ready and the seat is idle.

## Design

1. Tag `seat:<seat-name>` on the bean (beans `--tag`). `top_up_queue` (bin/fleet-watch:551) keeps such a bean out of the FIFO queue when the seat is not in the roster, and otherwise queues it with the seat name as a routing note.
2. `refill` (bin/fleet-watch:636): a queued bean with a `seat:` tag goes only to that seat, when it is idle; another idle coder skips it and takes the next queued bean. A manual seat with a tagged bean waiting counts as a dispatch target for that bean only; it stays out of the general refill.
3. Dispatch writes the ledger and the task file as the automatic path does (bin/fleet:750-756), so fleet-track, the reaper and the follow-up rounds work unchanged.
4. Reviews, follow-ups and landing: unchanged (the review goes to a reviewer on a different harness, as now).
5. `fleet status`: a manual seat with a tagged bean waiting shows `manual: waiting <bean>` in the title column; `fleet assign` by hand keeps working.

Out of scope: choosing beans for the seat by size or heuristics; that stays a lead decision expressed by the tag.

## Acceptance

- [x] a ready bean tagged `seat:X` is dispatched to seat X on the first tick X is idle, and never to another seat
- [x] a ready bean without the tag is never dispatched to a manual seat
- [x] a tag naming a seat not in the roster is logged once per top-up and the bean is left out of the queue
- [x] ledger and task file match the automatic path; `fleet-track` shows the bean on the seat
- [x] shellcheck clean; the eval or test that covers `refill` is extended
