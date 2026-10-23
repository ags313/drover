---
# drover-0msp
title: 'fleet-completed-audit: a bean landed by subject is not ''code not landed'''
status: completed
type: bug
priority: normal
created_at: 2026-10-15T13:53:08Z
updated_at: 2026-10-23T16:20:36Z
---

Facts (bob, 2026-10-15 14:41): `INTEGRITY WARN: 6 bean(s) 'completed' on main but code NOT landed`, then `fleet-completed-audit` listed 10 (bob-14wf, 3guc, 4wrk, 54zy, cvld, iqj5, kbwd, pnpm, t172, ynpj). Every one of them is on main: for example branch commit f71e430 `test(cli): centralize fake HTTP request handling` is main's 7ec092a with the same subject and content, 934b355 `feat(tui): add runs view with 2s polling` is 4df1dbb, c06a86c `feat(core): test-util init_bare_origin …` is 6e73030. The audit uses `git cherry` (patch-id) only (bin/fleet-completed-audit:28). fleet-land-bean's cherry-pick folds the bean status change into the landed commit and rewrites context, so the patch-id differs from the branch commit on most lands; the warning then fires for healthy beans and grows with every land. Two more sources of noise: a superseded duplicate branch of another seat for the same bean (qwen's), and a lead's squash land whose commit body does not list the subjects.

Rule: a bean counts as landed when `fleet-branch-landed --all <branch>` exits 0 (by subject, the rule fleet landable and fleet-land-bean already use), for ANY of its branches; only when every branch of the bean has an unlanded code subject is it 'falsely completed'. Keep patch-id as a fast first check. The squash path (fleet-land-bean's whole-branch squash) lists the squashed subjects in the commit body, so the by-subject rule sees them.

## Acceptance

- [x] on bob main today `fleet-completed-audit` reports 0 for the ten beans above
- [x] a bean whose code was reverted from main is still reported (eval case)
- [x] shellcheck clean; eval/eval-checkers.sh covers the three cases


## Validation evidence (2026-10-23)

Validated against bob `origin/main` at `63232265d29acdece6ff179c58f080dc54f291bb`.
The sandbox can read bob but cannot write its live audit cache, so both commands
used `FLEET_STATE=/tmp/drover-0msp-bob-audit`:

```sh
DROVER_PROJECT=bob FLEET_STATE=/tmp/drover-0msp-bob-audit PATH=$PWD/bin:$PATH bin/fleet-completed-audit
DROVER_PROJECT=bob FLEET_STATE=/tmp/drover-0msp-bob-audit bin/fleet-completed-audit --count
```

```text
falsely-completed (completed on main, code not landed): 11
bob-04ro :: fleet/bob-agy2-coder-bob-04ro
bob-13rd :: fleet/bob-cursor-coder-bob-13rd
bob-1bx0 :: fleet/bob-codex-coder-bob-1bx0
bob-1idk :: fleet/bob-codex-coder-bob-1idk
bob-3mhi :: fleet/bob-agy-coder-bob-3mhi
bob-5nuw :: fleet/bob-agy-coder-bob-5nuw
bob-b3vg :: fleet/bob-cursor-coder-bob-b3vg
bob-cezz :: fleet/bob-codex-coder-bob-cezz
bob-cn3r :: fleet/bob-cursor-coder-bob-cn3r
bob-mc1w :: fleet/bob-qwen27-coder-bob-mc1w
bob-oorp :: fleet/bob-cursor-coder-bob-oorp
11
```

None of bob-14wf, bob-3guc, bob-4wrk, bob-54zy, bob-cvld, bob-iqj5,
bob-kbwd, bob-pnpm, bob-t172, or bob-ynpj appears: **0 of the ten reported**.
The remaining eleven are different beans; the cached total matches the audit.

Both changed commands pass `shellcheck -x -P bin`. The eval covers rewritten
patch IDs with identical subjects, superseded duplicate branches, subjects in
squash bodies, patch-equivalent lands, bean-only follow-ups, actual reverted
code, cache counts, and restoring reverted code.


## Review follow-up: reverted ancestors belong to their bean

Reproduced the cross-bean revert regression in eval: main contains another
bean's commit, a new bean branch inherits it, main reverts that ancestor, and
then lands the new branch's own commit. Before the fix, both explicit-branch
and default-HEAD `fleet-branch-landed --all` failed and completed-audit flagged
the unrelated bean. These checks now pass. Reverted ancestors are injected
only when their subject names the bean in the resolved branch ref; `--all`
still considers every non-merge commit introduced by the branch. The ca03
fixture names its own bean and remains flagged when its own code is reverted.

Repeated the bob audit before and after this fix, against the same
`63232265d29acdece6ff179c58f080dc54f291bb` origin/main. Both outputs contain
exactly the same eleven bean/branch rows above, with matching cached counts
of 11. None of those eleven disappears when unrelated reverted ancestors are
excluded, so this regression did not cause those remaining reports in this
snapshot. The original ten regression beans still produce zero reports.
Used temporary state directories `/tmp/drover-0msp-review-before` and
`/tmp/drover-0msp-review-after` for the read-only bob checkout.

## Summary of Changes

Rebased the branch onto current nixos-multiproject and resolved eval/eval-checkers.sh. Preserved the complete completed-audit regression section alongside upstream's renamed dialog-test section and new checker cases. Rebased commits are c84f1f7, ecb4e69, and final commit 38e0162. The own-bean-only reverted-ancestor fix remains intact; all acceptance items remain checked.

Ran nix-shell --run 'bash eval/eval-checkers.sh': all checker cases pass. Then ran bob check on final commit 38e0162: passed. Worktree clean. Nothing pushed.
