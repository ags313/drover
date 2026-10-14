---
# drover-104i
title: 'Port fleet-branch-landed from upstream: by-subject landed check in fleet landable'
status: completed
type: task
priority: normal
created_at: 2026-10-13T21:08:07Z
updated_at: 2026-10-14T01:33:32Z
---

Port `bin/fleet-branch-landed` from upstream (remote `origin` = andrebrov/drover, commit 8479c6b "Port landing enforcement"), and use it in `fleet landable` (`bin/fleet` `cmd_landable`). Nothing else from that commit.

What it does: prints the bean-named, non-merge commits of a branch that are NOT on the main branch by subject (`git log origin/main -F --grep=<subject>`), never by SHA: a rebase or a squash changes the SHA, so an ancestor check reports landed work as missing. Exit 0 = all landed, exit 1 = unlanded, first line `AGE <minutes>` of the oldest unlanded commit.

Measured need here: on 2026-10-13 `fleet landable` listed forum-ixrd and forum-8xn7 as approved and landable from a second seat's branch although both beans were on main (squash-landed under the same subject). The lead had to read the log to see it.

Adapt to this fork:
- `origin/main` -> `$DROVER_UPSTREAM`; honour `DROVER_BEAN_RE` as the fork defines it.
- `cmd_landable`: a row whose branch has no unlanded bean commit by subject shows STATE `landed` (or MERGE `landed`) and fleet-land-bean refuses it with "already on main by subject". Keep the existing columns.
- Commit messages are ours: no co-author trailers from upstream.

Tests: an eval case in `eval/`: a branch whose commit was squash-landed under the same subject reports landed; a branch with one new bean commit reports it with AGE; a `wip:` commit is ignored.

Acceptance:
- [x] `fleet-branch-landed <branch>` exit codes and output as documented
- [x] `fleet landable` marks a by-subject landed branch and fleet-land-bean refuses it
- [x] eval case green; README one paragraph
