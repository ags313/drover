---
# drover-0msp
title: 'fleet-completed-audit: a bean landed by subject is not ''code not landed'''
status: todo
type: bug
priority: normal
created_at: 2026-10-15T13:53:08Z
updated_at: 2026-10-15T13:53:08Z
---

Facts (bob, 2026-10-15 14:41): `INTEGRITY WARN: 6 bean(s) 'completed' on main but code NOT landed`, then `fleet-completed-audit` listed 10 (bob-14wf, 3guc, 4wrk, 54zy, cvld, iqj5, kbwd, pnpm, t172, ynpj). Every one of them is on main: for example branch commit f71e430 `test(cli): centralize fake HTTP request handling` is main's 7ec092a with the same subject and content, 934b355 `feat(tui): add runs view with 2s polling` is 4df1dbb, c06a86c `feat(core): test-util init_bare_origin …` is 6e73030. The audit uses `git cherry` (patch-id) only (bin/fleet-completed-audit:28). fleet-land-bean's cherry-pick folds the bean status change into the landed commit and rewrites context, so the patch-id differs from the branch commit on most lands; the warning then fires for healthy beans and grows with every land. Two more sources of noise: a superseded duplicate branch of another seat for the same bean (qwen's), and a lead's squash land whose commit body does not list the subjects.

Rule: a bean counts as landed when `fleet-branch-landed --all <branch>` exits 0 (by subject, the rule fleet landable and fleet-land-bean already use), for ANY of its branches; only when every branch of the bean has an unlanded code subject is it 'falsely completed'. Keep patch-id as a fast first check. The squash path (fleet-land-bean's whole-branch squash) lists the squashed subjects in the commit body, so the by-subject rule sees them.

## Acceptance

- [ ] on bob main today `fleet-completed-audit` reports 0 for the ten beans above
- [ ] a bean whose code was reverted from main is still reported (eval case)
- [ ] shellcheck clean; eval/eval-checkers.sh covers the three cases
