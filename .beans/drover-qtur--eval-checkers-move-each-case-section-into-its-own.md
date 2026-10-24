---
# drover-qtur
title: 'eval-checkers: move each case section into its own file under eval/cases, no behaviour change'
status: todo
type: task
priority: normal
tags:
    - session-analysis
created_at: 2026-10-24T22:07:26Z
updated_at: 2026-10-24T22:07:26Z
---

Session analysis 2026-10-24 (window 2026-10-23 12:22Z – 2026-10-24 19:35Z).

Every bean appends its cases at the end of one 1,127-line file, so parallel beans collide there. This bean is a pure move: the same cases, in the same order, in the same shell.

Facts:
- All 7 drover lands of 2026-10-23 changed `eval/eval-checkers.sh` (41abd9d, 00d14ad, a3bf4ce, 6806e31, 76d2cea, f6e2efd, 823c5fc; +15 to +184 lines each, `git show --numstat`). It grew from 686 lines (`41abd9d^`) to 1,127.
- Both rebase conflicts of these 7 lands were in this file: bob run 12 (drover-0msp), events seq 39 (13:37:31Z) and seq 58 (13:53:17Z), "rebase conflict in eval/eval-checkers.sh". Conflict 2: drover-a34p renamed the dialog section next to the block 0msp appended. A split prevents this kind. Conflict 1: two runs fixed the same GIT_CONFIG setup line. A split does not prevent that kind.
- Layout today: l.1-63 header list, hermetic git, env, `ok`/`bad`; l.64 blank; l.65-1125 hold 24 sections, each starting with a `# --- <title> ---` line; l.1126 blank; l.1127 the verdict line.
- Later sections use state and functions of earlier ones. Examples: `bean()` from the scratch-repo section (l.70) is used again at l.239 and l.675; `rl_reason` (route_land, l.179) is used at l.641 (seat model pin); `hf()` (l.479) is used at l.685 (fleet-prep); the BLOCKED-park and seat-model-pin cases reuse the top-up board `$T/eb` (l.227). The order must stay.
- The scratch-repo section does `cd "$DROVER_REPO"`, and `bash eval/eval-checkers.sh` gives a relative `$0`. A cases path made from `$0` after that `cd` does not resolve.
- Users of the path: README.md:256, README.md:343, docs/LESSONS.md:1070, and bob's drover `test = nix-shell --run 'bash eval/eval-checkers.sh'`.

Impact: MEASURED: conflict 2 held run 12 for 8,689 s (bob still holds a run on its second conflict and returns only the first to the coder). Conflict 1 cost ≈261 s (74 s coder + 187 s slot wait). ESTIMATED: a first conflict costs 2 to 5 min of critical path plus one re-review (≈$0.3). The rate goes up with the number of coder slots (2 to 3 are proposed for drover).

Requirement:
- Move each `# --- ` section without changes into `eval/cases/NNN-<slug>.sh`, in the current order. NNN = 010, 020, …, 240 (three digits, so name order = current order; the gaps leave space for a new file between two). The slug comes from the section title, e.g. `010-scratch-repo.sh`, `040-fleet-claim-reap.sh`, `240-remote-pulls.sh`. Each file starts with `# shellcheck shell=bash`, then the section's own lines, unchanged.
- `eval/eval-checkers.sh` keeps l.1-63. It gets the absolute cases dir next to `BIN`, before any case runs (for example `CASES="$(cd "$(dirname "$0")/cases" && pwd)"`). It sources every `"$CASES"/[0-9][0-9][0-9]-*.sh` in name order, in the same shell (`.`, not `bash`), and then keeps the verdict line. If it finds no case file, it prints a `FAIL` line and exits 1. Same path, same command, same output and exit codes.
- Add one line below the header list: "Cases live in eval/cases/NNN-<area>.sh, sourced in name order. A new case goes at the end of its area's file, or in a new file with a free NNN; describe it at the top of that file, not in this list." Leave the header list as it is.
- Change no case line and no other file: `eval/eval-seat-state.sh`, `eval/eval-cursor-plugin.sh`, `eval/dialogs/`, `eval/panes/`, `bin/` stay as they are.
- Run `nix-shell` from the repo root (it reads `shell.nix` there). If `nix-shell` fails on `~/.cache/nix` in your shell (`error: creating symlink …flake-registry.json.tmp-…`), run it as `XDG_CACHE_HOME="$(mktemp -d)" nix-shell --run '…'`.

Chosen: one file for each existing section (24 files), not grouped into larger areas, because a 1:1 move needs no grouping decision and is easy to review; owner may change.
Not chosen: `eval/eval-checkers.sh merge=union` in `.gitattributes`, because a union merge of two edits to the same lines gives a broken script and no conflict.

## Acceptance

- [ ] `nix-shell --run 'bash eval/eval-checkers.sh'` passes on the branch: exit 0, last line `all checker cases pass`
- [ ] same results: before the first edit, from the repo root, run `nix-shell --run 'bash eval/eval-checkers.sh' | grep -E '^(ok|FAIL) ' | sed -E 's/\([0-9]+ms\)/(Nms)/' > "${TMPDIR:-/tmp}/eval-base.txt"`; after the move, the same into `"${TMPDIR:-/tmp}/eval-split.txt"`; `diff` of the two files is empty (same `ok` lines in the same order)
- [ ] pure move: `git show "$(git merge-base HEAD nixos-multiproject)":eval/eval-checkers.sh | sed -n '65,1125p'` against `for f in eval/cases/*.sh; do sed '1{/^# shellcheck shell=bash$/d}' "$f"; done` gives an empty `diff -B` (files listed in name order; if the base is no longer 1,127 lines, use its own section range)
- [ ] it works from another directory: in `nix-shell`, `cd / && bash <repo>/eval/eval-checkers.sh` passes
- [ ] a failure in a case file still fails the suite: a temporary wrong expectation in one case file prints its `FAIL` line and exits 1 (local check, do not commit)
- [ ] `shellcheck -S warning eval/eval-checkers.sh eval/cases/*.sh` reports no codes other than SC2010, SC1007, SC1010 (as on the base) and the split's own SC2154 (`rl_reason`), SC2034 (`BIN`) and SC1090 (the `.` line). Add no shellcheck directive to a case file; the lint bean cleans these up
- [ ] the bean gets a `## Validation evidence` section with the "same results" and "pure move" commands and their empty diff output (reviewers cannot run commands)
