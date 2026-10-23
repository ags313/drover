---
# drover-p8ct
title: 'fleet-watch: a release clears the owner marker of the bean it requeues'
status: completed
type: task
priority: low
created_at: 2026-10-21T08:57:46Z
updated_at: 2026-10-23T12:51:13Z
---

Seen on panel2, 2026-10-21: panel2-e8o5 carried `seat:panel2-qwen27-coder`; the seat could not reach its model and reported nothing. Every 90 min `release_stale` dropped the task file and re-dispatched the bean to the same seat (the route). The lead removed the seat tag at 08:59Z. The release at 09:30Z (`RELEASED panel2-qwen27-coder — 91m on panel2-e8o5 with no report; work requeued`) removed only `tasks/panel2-qwen27-coder`; `state/owner/panel2-e8o5` still named the seat, so every other coder logged `SKIP panel2-e8o5 for <seat> — owned by panel2-qwen27-coder; one bean, one coder` for 30 minutes, until the STALE-OWNER pass (marker age >= 30 min and an empty branch) would have cleared it. The lead deleted the marker by hand.

Rule: when the no-report release (`bin/fleet-watch`, the `work requeued` branch of `release_stale`) requeues a bean, and `state/owner/<bean>` names the released seat, remove the marker in the same step. The bean then goes to the next free coder on the next tick. The other release branches (completed/scrapped, re-routed, already reported) keep their behaviour; `owner_blocks` keeps protecting a bean whose owner is mid-task.

## Acceptance

- [x] test: a coder held a bean for 90 min with no report, the owner marker names that coder; after the release the marker is gone and the next tick dispatches the bean to another idle coder
- [x] test: a release where the marker names a different seat leaves the marker alone
- [x] `test/` suite green

## Summary of Changes

Committed 6891858: no-report requeue in fleet-watch reap_tasks now removes state/owner/<bean> only when it names the released seat. Other release branches and owner_blocks are unchanged.
Regression tests verify release at 90 minutes clears the matching owner, the next dispatch reaches another idle coder, and a different seat's owner marker survives. All acceptance items are checked in .beans/drover-p8ct--fleet-watch-a-release-clears-the-owner-marker-of-t.md.
Rebase onto nixos-multiproject reported already up to date; ancestry verified. Git emitted read-only packed-refs.lock errors during rebase/commit, but the commit succeeded and the working tree is clean.
The repository has eval/ rather than test/; used its required eval/eval-checkers.sh suite. Direct suite passed; bob check passed on the last commit. Nothing pushed.
