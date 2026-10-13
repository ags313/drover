---
# drover-ptct
title: 'Port fleet-prep from upstream: park leftover work, resume or cut the bean branch before a brief'
status: todo
type: task
priority: normal
created_at: 2026-10-13T21:08:07Z
updated_at: 2026-10-13T21:14:07Z
---

Port `bin/fleet-prep` from upstream (remote `origin` = andrebrov/drover, commit e6d9d54 "Port 2026-10-12 fleet changes"), and its hook in `fleet assign` (the `bin/fleet` hunk of that commit). Nothing else from that commit.

What it does: before a seat is briefed, its worktree goes on `fleet/<seat>-<bean>`:
- leftover work is parked on `wip/<seat>-<time>` with a commit (nothing discarded)
- an existing `fleet/<seat>-<bean>` branch is resumed, never reset
- else the branch is cut from the upstream main branch, so the bean file exists and the tree is clean
- the shared checkout is refused
Measured need here: on 2026-10-13 `fleet assign forum-ixrd codex-coder` printed "worktree has uncommitted tracked changes — staying on ..." and the seat kept a dirty tree.

Adapt to this fork:
- `origin main` -> `$DROVER_REMOTE $DROVER_MAIN_BRANCH` / `$DROVER_UPSTREAM`; worktree default `$DROVER_WORKTREES/fleet-$seat` (check the per-project layout in `bin/drover-env` line 98 and how `cmd_assign` finds the worktree).
- Keep the current `fleet assign` behaviour for a seat already on the bean's branch (mid-work: never park).
- Commit messages are ours: no co-author trailers from upstream.

Tests: an eval case in `eval/` next to the existing ones: a worktree with an untracked and a modified file gets parked on a wip branch and ends on the bean branch at the upstream main tip; a worktree already on the bean branch is left alone; the shared checkout is refused.

Acceptance:
- [x] `fleet assign` on a seat with leftover work parks it and briefs on a clean bean branch
- [x] `fleet-prep` by hand recovers a seat that reported BLOCKED on a dirty tree
- [x] eval case green; README one paragraph
