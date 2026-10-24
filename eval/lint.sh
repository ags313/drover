#!/usr/bin/env bash
# lint — one lint command for bin/ and eval/: shellcheck on the shell files, a syntax check on the python ones.
#
# Shell: a bash shebang, bin/drover-env (sourced, no shebang) or eval/cases/*.sh (sourced by eval-checkers.sh).
# Python: a python3 shebang. Anything else (the node script, fixtures, data files) is skipped.
# Run it inside nix-shell, which carries shellcheck: nix-shell --run 'bash eval/lint.sh'
# Exit 0 and `lint clean: <n> shell, <m> python` when nothing is found; else the tool output and exit 1.
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
cd "$(git rev-parse --show-toplevel)" || exit 1

if ! command -v shellcheck >/dev/null 2>&1; then
  echo "lint: shellcheck not found, run it inside nix-shell"
  exit 1
fi

shell=() python=()
while IFS= read -r f; do
  [ -f "$f" ] || continue
  case "$f" in
    bin/drover-env | eval/cases/*.sh) shell+=("$f"); continue ;;
  esac
  IFS= read -r first <"$f" || first=
  case "$first" in
    '#!/usr/bin/env bash'* | '#!/bin/bash'* | '#!/usr/bin/bash'*) shell+=("$f") ;;
    '#!/usr/bin/env python3'* | '#!/usr/bin/python3'*) python+=("$f") ;;
  esac
done < <(git ls-files bin eval)

rc=0
if [ "${#shell[@]}" -gt 0 ] && ! shellcheck -x -P bin -S warning --shell=bash "${shell[@]}"; then
  rc=1
fi
# ast.parse compiles nothing to disk, so no __pycache__ lands in the tree.
if [ "${#python[@]}" -gt 0 ] &&
  ! python3 -c 'import ast, sys; [ast.parse(open(f).read(), f) for f in sys.argv[1:]]' "${python[@]}"; then
  rc=1
fi

if [ "$rc" -ne 0 ]; then
  exit 1
fi
echo "lint clean: ${#shell[@]} shell, ${#python[@]} python"
