---
# drover-a34p
title: 'fleet-watch: answer Antigravity''s folder-trust prompt (agy seats)'
status: todo
type: bug
priority: normal
created_at: 2026-10-15T02:17:12Z
updated_at: 2026-10-15T02:17:12Z
---

Facts (bob, 2026-10-15 03:20): a new agy seat (bob-agy-coder) stopped on Antigravity CLI's trust prompt and stayed blocked; the lead pressed Enter by hand. The screen:

```
Accessing workspace:
/home/ags/.herdr/worktrees/bob/fleet-bob-agy-coder
Do you trust the contents of this project?
Antigravity CLI requires permission to read, edit, and execute files here.
> Yes, I trust this folder
  No, exit
  ↑/↓ Navigate · enter Confirm
```

`clear_dialogs` (bin/fleet-watch) answers the Claude layout (cursor on "No, exit", Down Enter, drover-ahzk) and the codex layout, not this one: the cursor sits on "Yes, I trust this folder" and the option lines differ.

## Fix

1. Add a case: `*"> Yes, I trust this folder"*"No, exit"*"Antigravity"*` (or the two option lines with the `>` marker on the first) -> `fleet keys "$a" Enter`, log `dialog: trusted own worktree on $a (agy)`. Match only with the cursor on the first option.
2. Extend the eval case list in `eval/eval-checkers.sh` with this screen.

## Acceptance

- [ ] an agy seat that starts on the trust prompt is trusted by the next tick with the log line above
- [ ] the Claude and codex cases are unchanged; eval green; shellcheck clean
