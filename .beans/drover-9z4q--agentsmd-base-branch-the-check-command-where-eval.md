---
# drover-9z4q
title: 'AGENTS.md: base branch, the check command, where eval cases go, and the bean rules'
status: todo
type: task
priority: low
tags:
    - session-analysis
created_at: 2026-10-24T22:07:26Z
updated_at: 2026-10-24T22:07:26Z
---

Session analysis 2026-10-24 (window 2026-10-23 12:22Z – 2026-10-24 19:35Z).

drover has no AGENTS.md, CLAUDE.md or .agents/. Each coder and reviewer finds the base branch, the check and the test layout again, and nothing tells a coder that it can verify live data from another repo itself.

Facts:
- Base branch: `nixos-multiproject`. Local `main` is a stale side branch: `git rev-list --count main..nixos-multiproject` = 86, the reverse = 0. In 12 of 12 reviews the first command was `git diff main...HEAD`, which gave 267 to 467 KB of output.
- Coders spent ≈24 commands over 7 runs to find how to lint (`rg shellcheck .github …`, `ls /nix/store/*shellcheck*`) and to work around nix-shell failing on `~/.cache/nix` in the sandbox (`error: creating symlink "/home/ags/.cache/nix/flake-registry.json.tmp-…"`; fix used: `XDG_CACHE_HOME=/tmp/<bean>-cache`, bob runs 12 and 16).
- Two runs (12 and 18) found again that a caller's `GIT_CONFIG_COUNT`/`GIT_CONFIG_PARAMETERS` rewrites scratch-repo remotes, and both fixed the same setup line in `eval/eval-checkers.sh` (now l.55-56). That caused rebase conflict 1 of run 12.
- drover-0msp acceptance item 1 said "on bob main today `fleet-completed-audit` reports 0 …" and named no command. The coder asked at 12:45:45Z (run 12 seq 28). The answer came at 13:28:23Z (seq 31): "validate it yourself; the data is readable from your sandbox", with `DROVER_PROJECT=bob PATH=$PWD/bin:$PATH bin/fleet-completed-audit`, which the coder then ran in one command.
- README.md:256 is the only place that names the check command.
- bob starts its claude agents with `--setting-sources ""`, so they load no CLAUDE.md; the coder and reviewer messages name only the files in bob's `rules`. Codex reads AGENTS.md by itself. Do not add a CLAUDE.md.

Impact: MEASURED: the question hold took 2,558 s of run 12 and one operator answer (1 of 7 beans); ESTIMATED ≈0 net bean-s in that batch, because the same operator absence held 4 other runs. ESTIMATED: ≤1 coder turn per session for the lookups. Claude agents see the file only after the operator sets `rules = ["AGENTS.md"]`.

Requirement: add `AGENTS.md` at the repo root, at most 60 lines, short plain sentences. It states:
- The base branch is `nixos-multiproject`. Local `main` is not the base. Read a change with `git diff nixos-multiproject...HEAD`.
- The check: `nix-shell --run 'bash eval/eval-checkers.sh'`; `bob check` runs it. Reviewers cannot run the checks; bob runs them and repeats them at the land.
- New eval cases: follow the note at the top of `eval/eval-checkers.sh`.
- The python scripts in `bin/` (list the 10 names). `bin/drover-env` is sourced by the other scripts, not run.
- Tests that make scratch repos rely on the hermetic git setup at the top of `eval/eval-checkers.sh` (no `GIT_CONFIG_COUNT`/`GIT_CONFIG_PARAMETERS`, `GIT_CONFIG_GLOBAL=/dev/null`). Do not add a second copy of it.
- If nix-shell cannot write `~/.cache/nix` in a sandbox, run it with `XDG_CACHE_HOME="$(mktemp -d)"`.
- Bean rules: an acceptance item that needs another repo or live state names the exact command and its env, or says "operator verifies". An acceptance item names the command to run and the result to expect, not "shellcheck clean".
- For an acceptance item about another repo or live state: other checkouts are readable from the agent shell. Run the drover tool against it yourself (for example `DROVER_PROJECT=bob PATH=$PWD/bin:$PATH bin/fleet-completed-audit`) and paste the output into the bean. Ask only if it cannot run.
- README.md:256: add one sentence that points to AGENTS.md.
- Run `nix-shell` from the repo root (it reads `shell.nix` there); use the `XDG_CACHE_HOME` workaround above if it fails on `~/.cache/nix` in your shell.
- Out of scope: bob's drover config (`rules = ["AGENTS.md"]` is an operator step after this lands).

## Acceptance

- [ ] AGENTS.md exists at the repo root and has at most 60 lines
- [ ] every check command in it runs as written from the repo root in `nix-shell`, and the eval command passes
- [ ] it names `nixos-multiproject` as the base and lists the same python scripts as `for f in $(git ls-files bin); do head -1 "$f" | grep -q python && echo "$f"; done`
- [ ] it has the bean rules and the live-state rule above
- [ ] no other file changes, except the README.md pointer
