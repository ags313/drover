---
# drover-t59r
title: 'fleet rules: install the fleet-peers skill for cursor'
status: todo
type: bug
priority: normal
created_at: 2026-10-11T23:14:23Z
updated_at: 2026-10-11T23:14:23Z
---

`fleet rules` / sync_skills installs pull-based fleet-peers manifests only for HOSTS="claude codex grok opencode" (bin/fleet:72; message at bin/fleet:814). Cursor is a supported harness (agent_args, fleet-yolo, fleet-yolo-config, cmd_usage list at bin/fleet:806) but cursor seats never get the skill. Check agy too.

- [ ] Add cursor (and agy if it has a skills location) to HOSTS with the right manifest path for cursor-agent
- [ ] Update the help text (bin/fleet:23, :122, :196) and cmd_rules message
- [ ] `fleet rules` installs a cursor manifest; a cursor seat can load fleet-peers
