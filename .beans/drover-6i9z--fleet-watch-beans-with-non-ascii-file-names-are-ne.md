---
# drover-6i9z
title: 'fleet-watch: beans with non-ASCII file names are never queued (git quotepath)'
status: todo
type: bug
priority: normal
created_at: 2026-10-13T02:01:34Z
updated_at: 2026-10-13T02:08:22Z
---

fleet-watch top-up skips a bean whose file name holds a non-ASCII character ("not on main (commit the bean file first)"), although the file is committed on main. Seen 2026-10-13 for forum-1avw (`.beans/forum-1avw--auto-groups-dowódca-...md`) and panel2-wrl3 (`...béret...md`): both skipped on every tick for hours.

Cause: bin/fleet-watch top_up_queue (line ~703) runs `git ls-files .beans | grep -m1 "^.beans/$bean--"`. With git's default `core.quotepath=true`, a path with bytes above 0x80 is printed quoted (`".beans/forum-1avw--auto-groups-dow\303\263dca...md"`), so the anchored grep fails and `bf` is empty.

Fix: `git -c core.quotepath=false ls-files .beans` (or `ls-files -z` with a NUL-safe match) everywhere a path from git output is matched by name: top_up_queue, fleet-land-bean's board commit, fleet-harvest-beans, fleet-heal-drift. Eval case in eval/eval-checkers.sh: a bean file named with "ó" is queued by top-up.

Workaround applied on the lead's machine: `git config core.quotepath false` in the forum and panel2 checkouts.

Acceptance:
- [x] a bean with a non-ASCII file name is queued on the first tick (eval case)
- [x] no other `git ls-files`/`ls-tree` name match in bin/ depends on quotepath
