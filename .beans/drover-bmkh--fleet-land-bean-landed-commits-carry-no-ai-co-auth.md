---
# drover-bmkh
title: 'fleet-land-bean: landed commits carry no AI co-author trailers'
status: todo
type: bug
priority: normal
tags:
    - land
created_at: 2026-10-21T20:40:53Z
updated_at: 2026-10-21T20:40:53Z
---

Finding (bob, 2026-10-21): two landed commits on main carry `Co-authored-by: Cursor <cursoragent@cursor.com>` (0e9eb79, 7c93734). The cursor harness adds the trailer to its own commits; the land cherry-picks or squashes them with the message as it is. The projects' rule is no AI attribution in commits.

Rule: when `fleet-land-bean` writes the landed commit (squash or cherry-pick), it drops trailers whose author is a tool: `Co-authored-by:` lines matching `cursor|claude|codex|copilot|openai|anthropic|chatgpt|agy|opencode` (case-insensitive, on the name or the e-mail), and `Generated-by:`/`Signed-off-by:` lines for the same names. The rest of the message stays. `git interpret-trailers --if-exists replace` or a sed over the message file, whichever is simpler.

## Acceptance

- [ ] a checker case in `eval/eval-checkers.sh`: a branch commit with a Cursor trailer lands without it; a human `Co-authored-by:` stays
- [ ] the drover gate (`fleet-push` checker suite) is green
