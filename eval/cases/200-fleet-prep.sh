# shellcheck shell=bash
# --- fleet-prep: a seat's worktree goes on fleet/<seat>-<bean> before the brief ---------------------------------
# Seat worktrees of $DROVER_REPO (origin/main is the upstream). Leftover work -> parked on wip/, ends clean on the
# bean branch at the origin/main tip; a seat already on its bean branch is untouched; an existing bean branch is
# resumed, not reset; a bean not pushed yet is cut from local main; the shared checkout is refused. Then the same
# through `fleet assign` (stub herdr reports the seat's cwd).
cd "$DROVER_REPO" || exit 1
git checkout -q main; git push -q origin main; git fetch -q origin
pwt(){ git worktree add -q -b "$2" "$T/pw/$1" "${3:-main}"; }
pst(){ printf '%s %s %s' "$(git -C "$1" branch --show-current)" "$(git -C "$1" rev-parse --short HEAD)" "$(git -C "$1" status --porcelain | wc -l | tr -d ' ')"; }
up=$(git rev-parse --short origin/main)
pwt s1 fleet/s1-old; echo dirt >> "$T/pw/s1/src/a.txt"; echo new > "$T/pw/s1/src/untracked.txt"
out=$("$BIN"/fleet-prep s1 x-ab12 "$T/pw/s1" 2>&1); rc=$?
wip=$(git for-each-ref --format='%(refname:short)' 'refs/heads/wip/s1-*' | head -1)
[ "$rc" = 0 ] && [ "$(pst "$T/pw/s1")" = "fleet/s1-x-ab12 $up 0" ] && [ -n "$wip" ] \
  && [ "$(git show "$wip:src/untracked.txt" 2>/dev/null)" = new ] && git show "$wip:src/a.txt" | grep -qx dirt \
  && ok 'fleet-prep parks a modified + an untracked file on wip/ and ends clean on the bean branch at origin/main' \
  || bad "fleet-prep park (rc=$rc): state='$(pst "$T/pw/s1")' want 'fleet/s1-x-ab12 $up 0' wip='$wip' out: $out"
echo mid >> "$T/pw/s1/src/a.txt"; before=$(git for-each-ref 'refs/heads/wip/' | wc -l)
out=$("$BIN"/fleet-prep s1 x-ab12 "$T/pw/s1" 2>&1); rc=$?
[ "$rc" = 0 ] && [ "$(pst "$T/pw/s1")" = "fleet/s1-x-ab12 $up 1" ] && [ "$(git for-each-ref 'refs/heads/wip/' | wc -l)" = "$before" ] \
  && ok 'fleet-prep leaves a seat already on its bean branch alone (dirty tree kept, nothing parked)' || bad "mid-work seat (rc=$rc): $(pst "$T/pw/s1") out: $out"
git -C "$T/pw/s1" checkout -q -- src/a.txt
pwt s2 fleet/s2-x-ab12; echo work > "$T/pw/s2/src/s2.txt"; git -C "$T/pw/s2" add -A; git -C "$T/pw/s2" commit -qm 'feat: s2 work (x-ab12)'
mine=$(git -C "$T/pw/s2" rev-parse --short HEAD); git -C "$T/pw/s2" switch -q -c fleet/s2-other
out=$("$BIN"/fleet-prep s2 x-ab12 "$T/pw/s2" 2>&1); rc=$?
[ "$rc" = 0 ] && [ "$(pst "$T/pw/s2")" = "fleet/s2-x-ab12 $mine 0" ] && ok 'fleet-prep resumes an existing bean branch, never resets it' \
  || bad "resume (rc=$rc): $(pst "$T/pw/s2") want fleet/s2-x-ab12 $mine 0; out: $out"
bean x-lc01 todo; git add -A; git commit -qm 'chore(beans): x-lc01 (not pushed)'
out=$("$BIN"/fleet-prep s2 x-lc01 "$T/pw/s2" 2>&1); rc=$?
[ "$rc" = 0 ] && [ "$(pst "$T/pw/s2")" = "fleet/s2-x-lc01 $(git rev-parse --short main) 0" ] && ok 'fleet-prep cuts a bean not pushed yet from local main' \
  || bad "local-main bean (rc=$rc): $(pst "$T/pw/s2") out: $out"
head=$(git rev-parse HEAD); echo shared >> src/a.txt
out=$("$BIN"/fleet-prep s1 x-ab12 "$DROVER_REPO" 2>&1); rc=$?
[ "$rc" = 2 ] && grep -q 'shared checkout' <<<"$out" && [ "$(git branch --show-current) $(git rev-parse HEAD)" = "main $head" ] \
  && [ -z "$(git for-each-ref 'refs/heads/wip/s1-*' --contains "$head")" ] && ok 'fleet-prep refuses the shared checkout' || bad "shared checkout (rc=$rc): $out"
git checkout -q -- src/a.txt
pwt s3 fleet/s3-old; echo left > "$T/pw/s3/src/left.txt"; : > "$T/herdr.log"
out=$(hf env HERDR_CWD="$T/pw/s3" FLEET_ROOT="$DROVER_REPO" FLEET='s3-coder:claude' FLEET_BRIEFS="$T/home/briefs" "$BIN"/fleet assign x-ab12 s3-coder 2>&1); rc=$?
[ "$rc" = 0 ] && [ "$(pst "$T/pw/s3")" = "fleet/s3-coder-x-ab12 $up 0" ] && [ -n "$(git for-each-ref 'refs/heads/wip/s3-coder-*')" ] \
  && grep -q '^agent prompt s3-coder New bean: .* x-ab12' "$T/herdr.log" && ok 'fleet assign parks leftover work and briefs on a clean bean branch' \
  || bad "assign + prep (rc=$rc): $(pst "$T/pw/s3") out: $out"

