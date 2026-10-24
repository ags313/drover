# shellcheck shell=bash
# --- fleet-claim reap: young-branch-bean ---------------------------------------------------------------------
now=$(date -u +%FT%TZ); old=$(date -u -d '2 days ago' +%FT%TZ 2>/dev/null || date -u -v-2d +%FT%TZ)
printf 'c1\tbean-new1\tsrc/young.txt\t%s\nc2\tbean-gone\tsrc/old.txt\t%s\n' "$now" "$old" > "$DROVER_HOME/claims.tsv"
out=$("$BIN"/fleet-claim reap)
grep -q 'released src/old.txt' <<<"$out" && ok 'claim reap releases an old claim on a missing bean' || bad 'claim reap kept an old missing-bean claim'
grep -q 'src/young.txt' "$DROVER_HOME/claims.tsv" && ok 'claim reap keeps a young claim on a branch-only bean' || bad 'claim reap dropped a young claim'

