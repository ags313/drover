# shellcheck shell=bash
# --- fleet-land-bean: a branch that merged main and resolved the conflict there ------------------------------
# bean-sq: its first commit conflicts with main on src/x.txt; the branch's merge of main resolves it -> lands as
# one squash with the resolution. bean-cf: the branch's net diff still conflicts with main -> flagged, main kept.
cd "$DROVER_REPO" || exit 1
echo 1 > src/x.txt; git add -A; git commit -qm 'x'
git checkout -qb fleet/c1-bean-sq; echo A > src/x.txt; echo feat > src/feat.txt; git add -A; git commit -qm 'feat: thing (bean-sq)'
git checkout -q main; git checkout -qb fleet/c1-bean-cf; echo C > src/x.txt; git add -A; git commit -qm 'feat: other (bean-cf)'
git checkout -q main; echo M > src/x.txt; git add -A; git commit -qm 'main moves x'
git checkout -q fleet/c1-bean-sq; git merge -q main -m 'merge main' >/dev/null 2>&1; echo AM > src/x.txt; git add -A; git commit -qm 'merge main, resolve x'
git checkout -q main
out=$("$BIN"/fleet-land-bean bean-sq 2>&1)
grep -q '^LANDED bean-sq' <<<"$out" && [ "$(cat src/x.txt)" = AM ] && [ -f src/feat.txt ] \
  && ok 'land-bean lands a branch whose merge of main resolves its conflicting commit' || bad "land-bean on a resolved branch: $out"
git log -1 --format=%s | grep -q 'bean-sq' && ok 'land-bean squash commit names the bean' || bad "squash subject: $(git log -1 --format=%s)"
head=$(git rev-parse HEAD); out=$("$BIN"/fleet-land-bean bean-cf 2>&1)
grep -q '^SKIP bean-cf — content conflict' <<<"$out" && [ "$(git rev-parse HEAD)" = "$head" ] \
  && ok 'land-bean flags a branch whose net diff conflicts' || bad "land-bean on a conflicting branch: $out"
[ "$(git worktree list | grep -c .)" = 1 ] && ok 'land-bean leaves no scratch worktree' || bad "worktrees left: $(git worktree list)"
