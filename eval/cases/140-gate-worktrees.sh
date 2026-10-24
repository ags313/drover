# shellcheck shell=bash
# --- gate worktrees get a copy of DROVER_CLONE_DIRS, not a symlink -------------------------------------------
# Turbopack refuses a node_modules symlink that leaves the project root. Both gates run a command that fails
# on a symlink. A failing copy falls back to a symlink with no partial tree left behind.
cd "$DROVER_REPO" || exit 1
mkdir -p node_modules/pkg; echo 'module.exports = 1' > node_modules/pkg/index.js
real_nm='test -d node_modules && test ! -L node_modules && test -f node_modules/pkg/index.js'
out=$(DROVER_BUILD="$real_nm" DROVER_TEST_ALL='' "$BIN"/fleet-verify-main 2>&1)
grep -q '^verify: GREEN' <<<"$out" && ok 'verify-main gate worktree holds a real node_modules' || bad "verify-main: $(tail -3 <<<"$out" | tr '\n' ' ')"
git checkout -qb fleet/c1-bean-nm; echo nm > src/nm.txt; git add src/nm.txt; git commit -qm 'feat: nm (bean-nm)'; git checkout -q main
out=$(DROVER_TYPECHECK="$real_nm" "$BIN"/fleet-land-bean bean-nm 2>&1)
grep -q '^LANDED bean-nm' <<<"$out" && ok 'land-bean gate worktree holds a real node_modules' || bad "land-bean: $(tail -2 <<<"$out" | tr '\n' ' ')"
mkdir -p "$T/seed"; out=$(bash -c '. "$0"; drover_clone(){ mkdir -p "$2/partial"; return 1; }; drover_seed_dir "$1" "$2/nm"' \
  "$BIN/drover-env" "$DROVER_REPO/node_modules" "$T/seed" 2>&1)
[ -L "$T/seed/nm" ] && [ "$(readlink "$T/seed/nm")" = "$DROVER_REPO/node_modules" ] && [ ! -e "$DROVER_REPO/node_modules/partial" ] \
  && ok 'seed falls back to a symlink when the copy fails' || bad "seed fallback: $(ls -la "$T/seed" | tail -n +2 | tr '\n' ' ') $out"
rm -rf node_modules

