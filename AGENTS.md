# AGENTS.md

## Base branch
- The base branch is `nixos-multiproject`. Local `main` is a stale side branch, not the base.
- Read a change with `git diff nixos-multiproject...HEAD`.

## Check
- Run from the repo root: `nix-shell --run 'bash eval/eval-checkers.sh'`. `nix-shell` reads `shell.nix` there.
- `bob check` runs the same command.
- Reviewers cannot run the checks. bob runs them and repeats them at the land.
- If nix-shell cannot write `~/.cache/nix` in a sandbox, run it with `XDG_CACHE_HOME="$(mktemp -d)"`.

## Eval cases
- Add new cases by following the note at the top of `eval/eval-checkers.sh`.
- Every checker needs a case that must fire and a case that must stay quiet.
- Tests that make scratch repos rely on the hermetic git setup at the top of `eval/eval-checkers.sh`.
  It unsets `GIT_CONFIG_COUNT` and `GIT_CONFIG_PARAMETERS` and sets `GIT_CONFIG_GLOBAL=/dev/null`.
  Do not add a second copy of it.

## Scripts in bin/
- These are python scripts: `fleet-ghost-reap`, `fleet-judge`, `fleet-landed-check`, `fleet-observe`,
  `fleet-review-check`, `fleet-slot`, `fleet-spec-feed`, `fleet-stale-worktree`, `fleet-yolo`,
  `fleet-yolo-config`.
- The other scripts are shell.
- `bin/drover-env` is sourced by the other scripts. Do not run it.

## Bean rules
- An acceptance item that needs another repo or live state names the exact command and its env.
  Or it says "operator verifies".
- An acceptance item names the command to run and the result to expect. Not "shellcheck clean".

## Live state and other repos
- Other checkouts are readable from the agent shell.
- Run the drover tool against them yourself. Example:
  `DROVER_PROJECT=bob PATH=$PWD/bin:$PATH bin/fleet-completed-audit`
- Paste the output into the bean.
- Ask only if the command cannot run.
