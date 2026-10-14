---
# drover-ahzk
title: 'fleet-watch: answer codex''s folder-trust prompt on a seat''s own worktree'
status: todo
type: bug
priority: normal
created_at: 2026-10-14T22:28:44Z
updated_at: 2026-10-14T22:28:44Z
---

Facts (bob project, first `fleet up`, 2026-10-14 23:25): both codex seats (`bob-codex-coder`, `bob-codex-reviewer`) stopped on codex's folder-trust prompt and stayed `blocked` for two ticks. The screen:

```
  Folder access
  /home/ags/.herdr/worktrees/bob/fleet-bob-codex-coder

  Note: You're in a subdirectory of a Git project. Trusting will apply to the repository root:
  /home/ags/vcs/ags313/bob

  Trust this folder? Codex can read, edit, and run files here, ...

› 1. Trust and continue
  2. Quit

  enter continue · esc quit
```

`clear_dialogs` (`bin/fleet-watch:160-178`) answers Claude's trust dialog (`"❯ No, exit"` … `"Yes, I trust this folder"`) and has no case for codex. Effect: the first review had no cross-harness reviewer (`no free cross-harness reviewer for bob-peji — queued for retry`), and the lead sent `fleet keys <seat> enter` by hand to both seats.

## Fix

1. Add one case to `clear_dialogs`: `*"Trust this folder?"*"› 1. Trust and continue"*"2. Quit"*` → `fleet keys "$a" Enter`, log `dialog: trusted own worktree on $a (codex)`. Match the exact option text with the cursor on option 1, as the Claude case does; any other layout is left alone.
2. Keep the rule in the comment above the Claude case: never match generic chrome such as `enter continue`.
3. `fleet read` keeps the last 8 lines (`clear_dialogs` reads 8); the two option lines and the hint line are inside that window, the question line is not. Match on the option lines only, or raise the read to 12 lines for this function.

## Acceptance

- [ ] a codex seat that starts on the folder-trust prompt is trusted by the next tick, with the log line above
- [ ] the Claude case and the other cases are unchanged
- [ ] shellcheck clean
