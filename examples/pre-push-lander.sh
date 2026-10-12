# pre-push-lander.sh — two additions for a .git/hooks/pre-push hook when the batch lander (bin/fleet-batch-land) is used.
# Paste each block into your hook, or source this file at the right points (marked below). Pairs with pre-push-lock.sh.
#
# 1. Seats report READY and never push main. While the enable marker exists, a push of main from a seat worktree is
#    refused unless it comes from the lander (which exports FLEET_BATCH_LANDER=1 around its gate and its push). The
#    refusal is scoped to seat worktrees, so your own checkout and disposable clones behave exactly as before.
#    Put this AFTER the hook has decided the push touches main (e.g. after reading remote_ref from stdin) and BEFORE
#    the gate. `root` is the worktree top level (git rev-parse --show-toplevel).
#
#       DROVER_WORKTREES defaults to ~/.herdr/worktrees/<repo name> (see bin/drover-env).
lander_marker="${FLEET_STATE:-${DROVER_HOME:-$HOME/.local/share/drover}/watch/state}/batch-land-enabled"
if [[ -f "$lander_marker" && "${FLEET_BATCH_LANDER:-}" != "1" && "$root/" == "${DROVER_WORKTREES:-$HOME/.herdr/worktrees}"/* ]]; then
  echo "[pre-push] the batch lander is on: seats never push main. Report READY instead:"
  echo "[pre-push]   fleet-batch-land ready <agent> <bean>   (the branch itself may be pushed; only main is refused)"
  echo "[pre-push] push refused"
  exit 1
fi

# 2. Bring the gate's test database up when its URLs are missing, so no seat needs a manual setup step. Not when the
#    operator supplied fixture manifests: those mean "no global database URL on purpose", and a fixture validator
#    refuses a push that has both. A setup failure is not fatal: the gate then refuses with its own "URLs missing".
#    DROVER_TESTDB_UP prints `export NAME=value` lines; MY_DB_URL / MY_FIXTURE_MANIFEST are your own variable names.
#
#       if [[ -z "${MY_DB_URL:-}" && -z "${MY_FIXTURE_MANIFEST:-}" && -n "${DROVER_TESTDB_UP:-}" ]]; then
#         if db_exports="$(cd "$root" && bash -c "$DROVER_TESTDB_UP" 2>>"$gate_log")"; then eval "$db_exports"; fi
#       fi
