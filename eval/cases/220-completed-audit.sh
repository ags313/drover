# shellcheck shell=bash
# --- completed-audit: rewritten subjects, duplicate seats, squashes, and reverted code -----------------------
# Isolate the fixtures from the other checker branches and their intentionally unlanded work.
mkdir -p "$T/audit"; git init -q -b main "$T/audit"
cd "$T/audit" || exit 1
git config user.email eval@example.invalid; git config user.name eval
mkdir -p .beans src; echo init > src/init; git add -A; git commit -qm init
for id in ca01 ca02 ca03 ca04; do bean "bean-$id" completed; done
git add -A; git commit -qm 'chore: complete audit fixtures'
# Status folded into a cherry-pick changes its patch-id, but preserves its subject.
git checkout -qb fleet/z-bean-ca01; echo feature > src/ca01; git add -A; git commit -qm 'feat: audit rewritten land'
git checkout -q main; git cherry-pick --no-commit fleet/z-bean-ca01
bean bean-ca01 completed 'Status folded into the landing.'; git add -A; git commit -qm 'feat: audit rewritten land'
# A superseded seat sorts BEFORE the landed seat. It must not condemn the bean.
git checkout -qb fleet/a-bean-ca01; echo obsolete > src/obsolete; git add -A; git commit -qm 'feat: superseded seat'
git checkout -q main
# A whole-branch squash lists each original subject in its body.
git checkout -qb fleet/c1-bean-ca02; echo one > src/ca02; git add -A; git commit -qm 'feat: audit squash first'
echo two >> src/ca02; git commit -qam 'feat: audit squash second'
git checkout -q main; git merge -q --squash fleet/c1-bean-ca02 >/dev/null
bean bean-ca02 completed 'Squashed.'; git add -A
git commit -qm 'feat: combined audit work' -m 'feat: audit squash first
feat: audit squash second'
# A real revert keeps the subject in history (and in the revert message), but removes the code.
git checkout -qb fleet/c1-bean-ca03; echo reverted > src/ca03; git add -A; git commit -qm 'feat: audit reverted work (bean-ca03)'
git checkout -q main; git merge -q --ff-only fleet/c1-bean-ca03; git revert --no-edit HEAD >/dev/null 2>&1
# A patch-identical landing still takes the fast path; bean-only follow-up commits are harmless.
git checkout -qb fleet/c1-bean-ca04; echo fast > src/ca04; git add -A; git commit -qm 'feat: audit patch match'
git checkout -q main; git cherry-pick fleet/c1-bean-ca04 >/dev/null
git checkout -q fleet/c1-bean-ca04; bean bean-ca04 completed 'Branch-only status note.'
git add -A; git commit -qm 'chore: branch status'; git checkout -q main
git remote add origin "$T/audit"; git fetch -q origin
out=$(DROVER_REPO="$T/audit" FLEET_STATE="$T/audit-state" "$BIN"/fleet-completed-audit)
for id in ca01 ca02 ca04; do
  grep -q "^bean-$id ::" <<<"$out" && bad "completed-audit falsely flagged $id: $out" || ok "completed-audit quiet on $id (rewritten/duplicate, squash, patch match)"
done
grep -q '^bean-ca03 ::' <<<"$out" && grep -q 'code not landed): 1$' <<<"$out"   && ok 'completed-audit reports reverted code even when its patch and subject remain in history' || bad "completed-audit revert: $out"
out=$(DROVER_REPO="$T/audit" FLEET_STATE="$T/audit-state" "$BIN"/fleet-completed-audit --count)
[ "$out" = 1 ] && ok 'completed-audit caches the bean count' || bad "completed-audit cached count: $out"
# Reverting the revert restores the landing, including when the original commit is an ancestor.
git revert --no-edit HEAD~1 >/dev/null 2>&1
git fetch -q origin
out=$(DROVER_REPO="$T/audit" FLEET_STATE="$T/audit-state" "$BIN"/fleet-completed-audit)
grep -q 'code not landed): 0$' <<<"$out" && ok 'completed-audit recognises restored code' || bad "completed-audit restored: $out"
# A branch owns Y, not the reverted X it inherited when cut from main.
echo other > src/zz99; git add -A; git commit -qm 'feat: other bean-zz99 work'
git checkout -qb fleet/c1-bean-ca05
echo own > src/ca05; git add -A; git commit -qm 'feat: own bean-ca05 work'
git checkout -q main; git revert --no-edit HEAD >/dev/null 2>&1
git cherry-pick --no-commit fleet/c1-bean-ca05
bean bean-ca05 completed; git add -A; git commit -qm 'feat: own bean-ca05 work'
# Explicit branch and default HEAD must both ignore another bean's removed ancestor.
out=$("$BIN"/fleet-branch-landed --base main --all fleet/c1-bean-ca05); rc=$?
if [ "$rc" = 0 ] && [ -z "$out" ]; then
  ok 'branch-landed: another bean reverted after branch cut does not undo this branch landing'
else
  bad "branch-landed inherited revert (rc=$rc): $out"
fi
git checkout -q fleet/c1-bean-ca05
out=$("$BIN"/fleet-branch-landed --base main --all); rc=$?
if [ "$rc" = 0 ] && [ -z "$out" ]; then
  ok 'branch-landed: default HEAD also ignores another bean reverted ancestor'
else
  bad "branch-landed HEAD inherited revert (rc=$rc): $out"
fi
git checkout -q main; git fetch -q origin
out=$(DROVER_REPO="$T/audit" FLEET_STATE="$T/audit-state" "$BIN"/fleet-completed-audit)
if grep -q 'code not landed): 0$' <<<"$out"; then
  ok 'completed-audit stays quiet on a landed branch with another bean reverted ancestor'
else
  bad "completed-audit inherited revert: $out"
fi
cd "$DROVER_REPO" || exit 1

