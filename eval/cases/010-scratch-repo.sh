# shellcheck shell=bash
# --- scratch repo with an origin -----------------------------------------------------------------------------
git init -q --bare "$T/origin.git"
git init -q -b main "$DROVER_REPO"; cd "$DROVER_REPO" || exit 1
git config user.email eval@example.invalid; git config user.name eval
mkdir -p .beans src
bean(){ printf -- '---\ntitle: %s\nstatus: %s\n---\n%s\n' "$1" "$2" "${3:-}" > ".beans/$1--t.md"; }
echo 1 > src/a.txt; git add -A; git commit -qm init
git remote add origin "$T/origin.git"; git push -q origin main
# bean-good1: completed in the same commit that changes code and names it
echo 2 > src/a.txt; bean bean-good1 completed; git add -A; git commit -qm 'fix: thing (bean-good1)'
# bean-good2: completed, body names a SHA that is on main
sha=$(git rev-parse --short HEAD); bean bean-good2 completed "Landed in $sha."; git add -A; git commit -qm 'chore(beans): close'
# bean-good3: completed with no code, declared
bean bean-good3 completed 'Landed: none — a decision record'; git add -A; git commit -qm 'chore(beans): decide'
# bean-bad1: completed, names nothing, only a bean-file commit mentions it
bean bean-bad1 completed; git add -A; git commit -qm 'chore(beans): close bean-bad1'
# bean-bad2: completed, names a SHA that exists but is not on main
git checkout -qb side; echo x > src/b.txt; git add -A; git commit -qm side; side=$(git rev-parse --short HEAD)
git checkout -q main; bean bean-bad2 completed "Landed in $side."; git add -A; git commit -qm 'chore(beans): close'
# bean-todo: not completed -> never checked
bean bean-todo todo; git add -A; git commit -qm 'chore(beans): file'
# bean-bad3: bean-bad1 under a non-ASCII file name. git quoted it ("...dow\303\263dca.md"), the .md test failed
# and the bean was never audited.
printf -- '---\ntitle: bean-bad3\nstatus: completed\n---\n' > .beans/bean-bad3--dowódca.md; git add -A; git commit -qm 'chore(beans): close bean-bad3'
git push -q origin main; git fetch -q origin

out=$("$BIN"/fleet-landed-check --hours 24); rc=$?
for b in bean-bad1 bean-bad2 bean-bad3; do grep -q "^UNPROVEN $b:" <<<"$out" && ok "landed-check fires on $b" || bad "landed-check missed $b"; done
for b in bean-good1 bean-good2 bean-good3 bean-todo; do grep -q "$b" <<<"$out" && bad "landed-check flagged $b" || ok "landed-check quiet on $b"; done
[ "$rc" = 1 ] && ok "landed-check exit 1 on violations" || bad "landed-check exit $rc"

