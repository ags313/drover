---
# drover-81v4
title: fleet-watch top-up crashes on an empty board (beans --ready prints null)
status: todo
type: bug
priority: normal
created_at: 2026-10-12T09:29:38Z
updated_at: 2026-10-12T11:02:44Z
---

On a board with no ready bean, `beans list --json --ready` prints `null`, not `[]`. The top-up filter in bin/fleet-watch (top_up, the python3 block after `added=$(... beans list --json --ready ...)`) does `bs=json.load(sys.stdin)` inside try/except, then `bs=[b for b in bs if ...]` outside it. With `null` that raises `TypeError: 'NoneType' object is not iterable` on every tick. Seen on the new panel2 project (2026-10-12, ~/.local/share/drover/projects/panel2/logs/fleet-watch.err).

Fix: treat `null` as an empty list, e.g. `bs=json.load(sys.stdin) or []`, and keep the except path. Check the other python3 blocks that read beans JSON (fleet-observe, fleet-ghost-reap, fleet-landed-check, fleet-spec-feed) for the same pattern.

- [x] top_up handles `null` without a traceback
- [x] same guard in every other beans-JSON reader that can see an empty board
- [x] eval check or unit test: empty board, one tick, no stderr output
