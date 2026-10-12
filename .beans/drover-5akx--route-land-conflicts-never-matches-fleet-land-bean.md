---
# drover-5akx
title: route_land_conflicts never matches fleet-land-bean's conflict flag
status: completed
type: bug
priority: normal
created_at: 2026-10-12T00:25:10Z
updated_at: 2026-10-12T12:45:43Z
---

bin/fleet-watch:788 routes a needs-land bean back to a coder only when the reason contains "content conflict in", but bin/fleet-land-bean:92 flags "content conflict on <sha> — manual land". So with DROVER_AUTOLAND=1 a conflicted approved bean sits flagged forever (integration_pick at :524 matches "content conflict" and works, but only runs under the WIP cap). Seen on the forum project 2026-10-12 (forum-7t7w, forum-8fqi, forum-alvr).

- [x] Match the text fleet-land-bean actually writes (e.g. *"content conflict"*), in one shared place so the two cannot drift again
- [x] eval-checkers case: a needs-land file with fleet-land-bean's exact reason is routed
