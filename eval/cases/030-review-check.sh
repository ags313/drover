# shellcheck shell=bash
# --- review-check --------------------------------------------------------------------------------------------
printf 'Reading additional input from stdin...\nOpenAI Codex v0.50.0\n--------\nworkdir: /x\n' > "$FLEET_REPORTS/s-bean-x-review.out"
{ echo 'VERDICT: CHANGES'; echo 'src/a.ts:12 reads the status before the write commits; a failed write records success.'
  echo 'src/b.ts:40 swallows the error and returns an empty list, which the caller renders as "no data".'
  echo 'Fix both, add a test where the dependency throws.'; } > "$FLEET_REPORTS/s-bean-y-review.md"
echo 'short note' > "$FLEET_REPORTS/codex-reviewer-self-serve.md"
# fleet-review-check leaves a short file alone for its first 15 minutes (a review still being written), so the
# fixtures are 20 minutes old, inside a 60-minute window. With fresh files and --minutes 5 the banner-only case
# could never fire.
python3 -c 'import os, sys, time; t = time.time() - 1200; [os.utime(f, (t, t)) for f in sys.argv[1:]]' \
  "$FLEET_REPORTS"/s-bean-x-review.out "$FLEET_REPORTS"/s-bean-y-review.md "$FLEET_REPORTS"/codex-reviewer-self-serve.md
out=$("$BIN"/fleet-review-check --minutes 60)
grep -q '^EMPTY s-bean-x-review.out' <<<"$out" && ok 'review-check fires on a banner-only review' || bad 'review-check missed banner-only review'
grep -q 's-bean-y-review' <<<"$out" && bad 'review-check flagged a grounded review' || ok 'review-check quiet on a grounded review'
grep -q 'self-serve' <<<"$out" && bad 'review-check flagged a reviewer seat report' || ok 'review-check quiet on a seat report named *-reviewer-*'

