---
# drover-2vo6
title: 'fleet-land-bean: land a branch that merged main as a whole'
status: completed
type: bug
priority: normal
created_at: 2026-10-12T00:25:10Z
updated_at: 2026-10-12T19:40:54Z
---

fleet-land-bean cherry-picks the branch's non-merge commits onto main. When the coder already merged main into the branch and resolved conflicts in that merge commit, the original commit no longer applies on its own, so the land is flagged "content conflict on <sha>" although `git merge-tree main <branch>` is clean. Seen 2026-10-12 on forum-8fqi and forum-alvr (fleet landable: MERGE clean, flagged content conflict).

- [x] When the cherry-pick conflicts but merge-tree of the whole branch is clean, land the branch's net diff (squash or merge) through the same scratch worktree and gates
- [x] eval-checkers case: a branch whose first commit conflicts but whose merge of main resolves it lands
