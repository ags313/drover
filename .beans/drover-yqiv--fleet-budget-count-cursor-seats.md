---
# drover-yqiv
title: 'fleet-budget: count cursor seats'
status: completed
type: bug
priority: low
created_at: 2026-10-11T23:14:23Z
updated_at: 2026-10-12T19:36:47Z
---

bin/fleet-budget:151 counts seats per harness for opencode, codex, claude, grok, agy but not cursor, though the row filter at :84 accepts cursor. Cursor seats are missing from the per-harness budget table (:215 prints grok/agy subscription rows only).

- [x] Count cursor seats and print a cursor row
- [x] eval checkers pass (nix-shell --run 'bash eval/eval-checkers.sh')
