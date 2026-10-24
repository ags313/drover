# shellcheck shell=bash
# --- fleet-branch-landed: a branch's commits on main BY SUBJECT (a squash or rebase changes SHA and patch) ----------
# bean-bl01: two commits, squash-landed on main as one commit with the first subject and the second listed in its body
# (fleet-land-bean's squash format) plus an extra file, so neither SHA nor patch matches. Landed. Then a new bean
# commit (2 h old), a wip: commit and a commit naming no bean: only the bean commit is unlanded, with its AGE.
cd "$DROVER_REPO" || exit 1
git checkout -q main
git checkout -qb fleet/c1-bean-bl01; echo a > src/bl.txt; git add src/bl.txt; git commit -qm 'feat: bl (bean-bl01)'
echo b >> src/bl.txt; git commit -qam 'feat: bl part 2 (bean-bl01)'; p2=$(git rev-parse --short HEAD)
git checkout -q main; git merge -q --squash fleet/c1-bean-bl01 >/dev/null; echo extra > src/bl-extra.txt; git add -A
git commit -qm 'feat: bl (bean-bl01)' -m "Squash of fleet/c1-bean-bl01.

- $p2 feat: bl part 2 (bean-bl01)"
out=$("$BIN"/fleet-branch-landed --base main fleet/c1-bean-bl01); rc=$?
[ "$rc" = 0 ] && [ -z "$out" ] && ok 'branch-landed: a squash-landed branch is landed by subject (exit 0, no output)' || bad "squash-landed (rc=$rc): $out"
git checkout -q fleet/c1-bean-bl01
echo c >> src/bl.txt; GIT_COMMITTER_DATE="$(date -d '2 hours ago' -R 2>/dev/null || date -v-2H -R)" git commit -qam 'fix: bl again (bean-bl01)'
echo w > src/wip.txt; git add src/wip.txt; git commit -qm 'wip: leftover (bean-bl01)'
echo n > src/noise.txt; git add src/noise.txt; git commit -qm 'chore: names no bean'
git checkout -q main
out=$("$BIN"/fleet-branch-landed --base main fleet/c1-bean-bl01); rc=$?
age=$(sed -n '1s/^AGE //p' <<<"$out")
[ "$rc" = 1 ] && [ "$(sed -n '2,$p' <<<"$out")" = 'fix: bl again (bean-bl01)' ] && [ "${age:-0}" -ge 119 ] && [ "${age:-0}" -le 122 ] \
  && ok 'branch-landed: one new bean commit -> exit 1, AGE of the oldest, its subject; wip: and no-bean commits ignored' \
  || bad "unlanded (rc=$rc): $(tr '\n' '|' <<<"$out")"
out=$("$BIN"/fleet-branch-landed --base main --all fleet/c1-bean-bl01); rc=$?
[ "$rc" = 1 ] && [ "$(sed -n '2,$p' <<<"$out" | tr '\n' '|')" = 'chore: names no bean|wip: leftover (bean-bl01)|fix: bl again (bean-bl01)|' ] \
  && ok 'branch-landed --all: every non-merge commit counts (no-bean and wip: too)' || bad "--all (rc=$rc): $(tr '\n' '|' <<<"$out")"
# an ordinary one-parent commit whose subject starts "Merge " is work, not a merge commit (review of drover-104i)
git checkout -qb fleet/c1-bean-mg01 main; echo m > src/mg.txt; git add src/mg.txt
GIT_COMMITTER_DATE="$(date -d '1 hour ago' -R 2>/dev/null || date -v-1H -R)" git commit -qm 'Merge feature components (bean-mg01)'; git checkout -q main
out=$("$BIN"/fleet-branch-landed --base main fleet/c1-bean-mg01); rc=$?; age=$(sed -n '1s/^AGE //p' <<<"$out")
out2=$("$BIN"/fleet-branch-landed --base main --all fleet/c1-bean-mg01); rc2=$?
[ "$rc" = 1 ] && [ "$rc2" = 1 ] && [ "$(sed -n '2,$p' <<<"$out")" = 'Merge feature components (bean-mg01)' ] && [ "$out2" = "$out" ] \
  && [ "${age:-0}" -ge 59 ] && [ "${age:-0}" -le 62 ] && ok 'branch-landed: a one-parent "Merge ..." commit is unlanded work (default and --all)' \
  || bad "Merge-subject commit (rc=$rc/$rc2): $(tr '\n' '|' <<<"$out") / $(tr '\n' '|' <<<"$out2")"
: > "$FLEET_STATE/approved/bean-mg01"; head=$(git rev-parse HEAD); out=$("$BIN"/fleet-land-bean bean-mg01 2>&1); rc=$?
[ "$rc" = 0 ] && grep -q '^LANDED bean-mg01' <<<"$out" && [ "$(git log -1 --format=%s)" = 'Merge feature components (bean-mg01)' ] && [ ! -e "$FLEET_STATE/needs-land/bean-mg01" ] \
  && ok 'fleet-land-bean lands a "Merge ..." subject commit, no by-subject refusal' || bad "land Merge-subject (rc=$rc): $out"
git push -q origin main; git fetch -q origin
out=$("$BIN"/fleet-branch-landed fleet/c1-bean-bl01); rc=$?
[ "$rc" = 1 ] && [ "$(sed -n '2p' <<<"$out")" = 'fix: bl again (bean-bl01)' ] && ok 'branch-landed: default base is DROVER_UPSTREAM' || bad "default base (rc=$rc): $out"
"$BIN"/fleet-branch-landed --base nosuchref fleet/c1-bean-bl01 >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && ok 'branch-landed: unknown ref -> exit 2' || bad "unknown ref rc=$rc"
# fleet landable + fleet-land-bean: bean-sl01 is squash-landed under its subject (another patch); bean-nl01 is not landed
git checkout -qb fleet/c1-bean-sl01; echo s > src/sl.txt; git add src/sl.txt; git commit -qm 'feat: sl (bean-sl01)'; git checkout -q main
git checkout -qb fleet/c1-bean-nl01; echo n > src/nl.txt; git add src/nl.txt; git commit -qm 'feat: nl (bean-nl01)'; git checkout -q main
echo s2 > src/sl.txt; echo more > src/sl-more.txt; git add -A; git commit -qm 'feat: sl (bean-sl01)'
mkdir -p "$FLEET_STATE/approved"; : > "$FLEET_STATE/approved/bean-sl01"; : > "$FLEET_STATE/approved/bean-nl01"
out=$(FLEET_ROOT="$DROVER_REPO" "$BIN"/fleet landable 2>&1)
awk '$1=="bean-sl01" && $5=="landed" && /by subject/ {f=1} END{exit !f}' <<<"$out" && awk '$1=="bean-nl01" && $5=="clean" {f=1} END{exit !f}' <<<"$out" \
  && ok 'fleet landable: MERGE landed for the by-subject landed branch, clean for the other' || bad "landable: $out"
head=$(git rev-parse HEAD); out=$("$BIN"/fleet-land-bean bean-sl01 2>&1); rc=$?
[ "$rc" = 1 ] && grep -q '^SKIP bean-sl01 — already on main by subject' <<<"$out" && [ "$(git rev-parse HEAD)" = "$head" ] \
  && [ -f "$FLEET_STATE/needs-land/bean-sl01" ] && ok 'fleet-land-bean refuses a branch already on main by subject (flagged, main unchanged)' \
  || bad "land-bean by subject (rc=$rc): $out"
rm -f "$FLEET_STATE/needs-land/bean-sl01" "$FLEET_STATE/approved/bean-nl01"

