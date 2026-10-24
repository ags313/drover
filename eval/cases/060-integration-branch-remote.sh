# shellcheck shell=bash
# --- integration branch and remote ---------------------------------------------------------------------------
up=$(DROVER_MAIN_BRANCH=trunk DROVER_REMOTE=fork bash -c '. "$0"; printf %s "$DROVER_UPSTREAM"' "$BIN/drover-env")
[ "$up" = fork/trunk ] && ok 'DROVER_MAIN_BRANCH/DROVER_REMOTE set the upstream' || bad "upstream is '$up', want fork/trunk"
def=$(bash -c '. "$0"; printf %s "$DROVER_UPSTREAM"' "$BIN/drover-env")
[ "$def" = origin/main ] && ok 'upstream defaults to origin/main' || bad "default upstream is '$def'"

