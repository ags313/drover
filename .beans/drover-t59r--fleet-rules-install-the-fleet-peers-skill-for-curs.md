---
# drover-t59r
title: 'fleet rules: install the fleet-peers skill for cursor'
status: completed
type: bug
priority: normal
created_at: 2026-10-11T23:14:23Z
updated_at: 2026-10-12T19:38:42Z
---

`fleet rules` / sync_skills installs pull-based fleet-peers manifests only for HOSTS="claude codex grok opencode" (bin/fleet:72; message at bin/fleet:814). Cursor is a supported harness (agent_args, fleet-yolo, fleet-yolo-config, cmd_usage list at bin/fleet:806) but cursor seats never get the skill. Check agy too.

- [x] Add cursor (and agy if it has a skills location) to HOSTS with the right manifest path for cursor-agent
- [x] Update the help text (bin/fleet:23, :122, :196) and cmd_rules message
- [x] `fleet rules` installs a cursor manifest; a cursor seat can load fleet-peers

Cursor loads it only when launched with `--plugin-dir <FLEET_SKILLS>/cursor`, on an authenticated profile (authless sets enableUserLocalPlugins=false), with the team admin setting allowUserLocalPluginImports not false (cursor-agent 2026.10.01 bundle). Live proof: `eval/eval-cursor-plugin.sh` (paired with/without arms). Nothing in drover passes `--plugin-dir` to a seat yet, for any harness.
