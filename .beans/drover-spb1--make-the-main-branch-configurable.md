---
# drover-spb1
title: Make the main branch configurable
status: completed
type: feature
priority: high
created_at: 2026-10-11T23:14:23Z
updated_at: 2026-10-11T23:19:11Z
---

"main" is hard-coded as the landing branch: fleet-watch auto-heals $DROVER_REPO back to main (bin/fleet-watch:741, bin/fleet-heal-drift:17-22), fleet land / fleet-land-bean merge into main, check_beans resolves beans against main. A project whose integration branch is not main (e.g. drover's own nixos-multiproject) gets switched to main by the watcher.

- [x] DROVER_MAIN_BRANCH (default main) and DROVER_REMOTE (default origin) in drover-env + examples/config
- [x] Every hard-coded main ref in bin/ uses it (grep for main refs: heal, land, landable, sync, check_beans, verify-main, push)
- [x] README config table + RUNBOOK
- [x] eval checkers pass

## Summary of Changes

- drover-env: DROVER_MAIN_BRANCH (default main), DROVER_REMOTE (default origin), DROVER_UPSTREAM=$DROVER_REMOTE/$DROVER_MAIN_BRANCH.
- Every hard-coded main / origin/main / push|fetch origin in bin/ uses them: fleet (bean checks, prompts, assign fork, landable, sync), fleet-watch (queue, heal, auto-push, briefs), fleet-land-bean, fleet-push, fleet-verify-main, fleet-heal-drift (now sources drover-env), fleet-claim, fleet-completed-audit, fleet-mignum, standup/scoreboard/retro/sprint/tasks/unblock, and the Python scripts (fleet-observe, fleet-ghost-reap, fleet-landed-check, fleet-stale-worktree, fleet-spec-feed) via their drover-env loaders.
- README config table, examples/config, RUNBOOK note.
- eval/eval-checkers.sh: upstream follows the settings and defaults to origin/main; all checker cases pass.
