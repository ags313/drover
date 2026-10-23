---
# drover-bmkh
title: 'fleet-land-bean: landed commits carry no AI co-author trailers'
status: completed
type: bug
priority: normal
tags:
    - land
created_at: 2026-10-21T20:40:53Z
updated_at: 2026-10-23T13:56:19Z
---

Finding (bob, 2026-10-21): two landed commits on main carry `Co-authored-by: Cursor <cursoragent@cursor.com>` (0e9eb79, 7c93734). The cursor harness adds the trailer to its own commits; the land cherry-picks or squashes them with the message as it is. The projects' rule is no AI attribution in commits.

Rule: when `fleet-land-bean` writes the landed commit (squash or cherry-pick), it drops trailers whose author is a tool: `Co-authored-by:` lines matching `cursor|claude|codex|copilot|openai|anthropic|chatgpt|agy|opencode` (case-insensitive, on the name or the e-mail), and `Generated-by:`/`Signed-off-by:` lines for the same names. The rest of the message stays. `git interpret-trailers --if-exists replace` or a sed over the message file, whichever is simpler.

## Acceptance

- [x] a checker case in `eval/eval-checkers.sh`: a branch commit with a Cursor trailer lands without it; a human `Co-authored-by:` stays
- [x] the drover gate (`fleet-push` checker suite) is green

## Summary of Changes

Rebased onto nixos-multiproject. Committed 2cc6c3f: fleet-land-bean strips case-insensitive tool attribution from Co-authored-by, Generated-by, and Signed-off-by lines on cherry-pick and squash landing paths, preserving the remaining message. Checker coverage exercises all listed tool names in names and emails, multiple commits, human trailers, unchanged body text, cherry-pick provenance, and unchanged source commits. Both acceptance items are checked in the drover-bmkh bean. Worktree is clean. bob check passed on the final commit: nix-shell --run 'bash eval/eval-checkers.sh'. Nothing pushed. Git emitted a read-only packed-refs.lock warning during commit; the commit succeeded and its checks passed.
