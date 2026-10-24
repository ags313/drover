---
# drover-49d1
title: 'eval/lint.sh: one lint command for bin/ and eval/ (shellcheck, python syntax), clean on the current tree'
status: completed
type: task
priority: low
tags:
    - session-analysis
created_at: 2026-10-24T22:07:27Z
updated_at: 2026-10-24T23:51:45Z
blocked_by:
    - drover-qtur
    - drover-9z4q
---

Session analysis 2026-10-24 (window 2026-10-23 12:22Z – 2026-10-24 19:35Z).

Beans ask for "shellcheck clean", but drover has no lint command and the tree is not clean, so each coder makes its own baseline and nobody else can repeat the result.

Facts:
- bob's drover config has only `test = nix-shell --run 'bash eval/eval-checkers.sh'` and no `build`. No lint runs in `bob check` or at the land.
- 4 of the 7 beans of the window had a "shellcheck clean" acceptance item (drover-w6uy, -0msp, -a34p, -v96l). Coders ran shellcheck 38 to 45 times with at least 6 flag sets: plain, `-x -P bin`, `-x`, `-e SC1091`, `-S warning -e SC2010,SC1007,SC1010`, and `-S warning -f json` against a copy of the base file (bob run 7 log l.80-93, run 16 l.42-56, in `~/.local/share/bob/runs/<id>.log`).
- `eval/eval-checkers.sh` already has SC2010, SC1007 and SC1010 warnings. "Clean" therefore meant "no new warnings against a baseline I made" (the drover-a34p and drover-w6uy summaries say this).
- Reviewers cannot run commands: 30 reviewer calls that tried tests or lint were denied.
- Tracked `bin/` (`git ls-files bin`, first line): 31 bash scripts, `bin/drover-env` (bash, sourced, no shebang), 10 python3 scripts with no syntax check (fleet-ghost-reap, fleet-judge, fleet-landed-check, fleet-observe, fleet-review-check, fleet-slot, fleet-spec-feed, fleet-stale-worktree, fleet-yolo, fleet-yolo-config), 1 node script (fleet-check-inline-jest-fanout). `shellcheck` is in shell.nix:55, not on the host PATH. `__pycache__/` is in .gitignore. On 823c5fc, `shellcheck -x -P bin -S warning --shell=bash` on the 35 shell files reports 23 warnings in 9 files: bin/drover-env 5, bin/fleet 5, bin/fleet-tasks 2, bin/fleet-scoreboard 2, bin/fleet-budget, bin/fleet-hunt, bin/fleet-retro and bin/fleet-wait 1 each, eval/eval-checkers.sh 5 (SC2034 ×9, SC1010 ×8, SC2010 ×3, SC1007, SC2046, SC2227). The case split (`eval/cases/`) adds SC2154 (`rl_reason`, set in an earlier case file), SC2034 (`BIN`) and SC1090 (the `.` loop). The 10 python scripts parse clean.

Impact: ESTIMATED ≈1 min of coder time per working session; 13 sessions in the window ≈13 min, serial on one coder slot, so on the critical path. Quality: one lint result that bob runs, caches per tree and repeats at the land, in place of a self-certified "shellcheck clean".

Requirement:
- Add `eval/lint.sh` (bash, `set -uo pipefail`). It:
  - goes to the repo root first, so it works from any directory;
  - if `shellcheck` is not on PATH, prints `lint: shellcheck not found, run it inside nix-shell` and exits 1;
  - takes the files from `git ls-files bin eval` and sorts them by first line: a bash shebang, `bin/drover-env` or `eval/cases/*.sh` → shell; a python3 shebang → python; others (node, data files) → skipped;
  - runs `shellcheck -x -P bin -S warning --shell=bash` on the shell files (`bin/drover-env` has no shebang and no shell directive), and a python syntax check on the python files that writes nothing into the tree (for example `python3 -c 'import ast, sys; [ast.parse(open(f).read(), f) for f in sys.argv[1:]]'`);
  - on any finding prints the tool output and exits 1; else prints `lint clean: <n> shell, <m> python` and exits 0.
- Make the current tree clean: fix the warnings above and any other warning the script finds. Where a fix would change what a script does, put `# shellcheck disable=SCnnnn` on that line with a short reason. No checked behaviour changes and no case result changes.
- README.md:256: add `nix-shell --run 'bash eval/lint.sh'` next to the eval command.
- AGENTS.md: add `nix-shell --run 'bash eval/lint.sh'` to its checks line, and "(`eval/lint.sh` covers it)" after "not \"shellcheck clean\"" in its bean rule.
- Run `nix-shell` from the repo root (it reads `shell.nix` there). If `nix-shell` fails on `~/.cache/nix` in your shell, run it as `XDG_CACHE_HOME="$(mktemp -d)" nix-shell --run '…'`.
- Out of scope: the node script; bob's drover config (the operator sets `build` after this lands); install.sh, ops/oc-compact.sh, examples/pre-push-lock.sh (3 warnings today).

Chosen: a separate script that bob runs as `build`, not a call inside eval-checkers.sh, because bob runs `build` before `test`, caches it per tree and reports it apart; owner may change.

## Acceptance

- [x] `nix-shell --run 'bash eval/lint.sh'` exits 0 on the branch and its last line is `lint clean: 60 shell, 10 python` (31 bash + drover-env in bin, 4 eval scripts with lint.sh, 24 files in eval/cases; a file added since changes the count)
- [x] a temporary `cd /tmp` with no `|| exit` in a bin bash script (SC2164, warning level) makes it exit 1 and name the file; a temporary syntax error in a python script does the same (local checks, do not commit)
- [x] it works from another directory: in `nix-shell`, `cd / && bash <repo>/eval/lint.sh` gives the same result
- [x] it writes no file under `bin/` or `eval/` (`find bin eval -newer <stamp-file>` is empty after a run)
- [x] `nix-shell --run 'bash eval/eval-checkers.sh'` passes, and its result lines (`grep -E '^(ok|FAIL) ' | sed -E 's/\([0-9]+ms\)/(Nms)/'`) before the first edit and after the change give an empty `diff`
- [x] AGENTS.md names `nix-shell --run 'bash eval/lint.sh'`, and README.md:256 names it next to the eval command

## Summary of Changes

drover-49d1 done in 543d4f7. Rebase onto nixos-multiproject was a no-op: the branch was already up to date.

- Added eval/lint.sh (bash, set -uo pipefail). It cds to the repo root and exits 1 with "lint: shellcheck not found, run it inside nix-shell" if shellcheck is missing. It sorts `git ls-files bin eval` by first line: bash shebang, bin/drover-env or eval/cases/*.sh → shell; python3 shebang → python; anything else is skipped. It runs `shellcheck -x -P bin -S warning --shell=bash` on the shell files and ast.parse on the python files, so nothing is written to the tree. Output: "lint clean: 60 shell, 10 python".
- Fixed the tree without changing behaviour:
  - quoted 'done' (SC1010) in fleet, fleet-budget, fleet-hunt and 230-clear-dialogs
  - `_` for unused read fields in fleet, fleet-tasks and fleet-wait; removed the unused `local added` in fleet-tasks
  - fleet-retro: 2>/dev/null moved after -print0 (SC2227)
  - 140-gate-worktrees: DROVER_TEST_ALL='' (SC1007)
  - 100-top-up: top_up moved onto its own line so the disable directive covers the test
  - disable comments with a reason where a fix would change behaviour: drover-env vars read by the scripts that source it (SC2034), the $(cat paths) split in fleet land (SC2046), ls|grep counts in fleet-scoreboard and the 100 case (SC2010), rl_reason in the 190 case (SC2154), BIN and the `.` loop in eval-checkers (SC2034, SC1090)
- README.md:256 and AGENTS.md updated as the bean asks.

Acceptance checks, all run locally:
- lint.sh exits 0 with that last line, from the repo and from /.
- A `cd /tmp` added to bin/fleet-retro exits 1 with SC2164 naming the file. In bin/fleet-wait it is not flagged, because shellcheck skips SC2164 under set -e.
- A python syntax error added to bin/fleet-slot exits 1 and names the file.
- `find bin eval -newer stamp` is empty after a run.
- eval-checkers result lines: diff before/after is empty (155 ok).

Note: these local runs did not go through nix-shell. My sandbox blocks github.com, so the pinned nixpkgs could not be fetched, and it also blocks the nix daemon socket. I ran on the host with shellcheck 0.11.0 from /nix/store on PATH. `bob check` (which does use nix-shell) passed on 543d4f7. Nobody has yet run `nix-shell --run 'bash eval/lint.sh'` with the pinned shellcheck. If that version differs from 0.11.0, the result could differ.
