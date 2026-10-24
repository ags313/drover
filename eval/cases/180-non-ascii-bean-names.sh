# shellcheck shell=bash
# --- non-ASCII bean file names: git's core.quotepath=true printed ".beans/x--dow\303\263dca.md", the name match
# in refill failed and the bean was skipped as "not on main" every tick (forum-1avw, panel2-wrl3). The repo sets
# quotepath=true itself, so the case fires whatever the host config says. Same stub coder as the park case.
git init -q -b main "$T/ub"
( cd "$T/ub" && git config user.email e@x.invalid && git config user.name e && git config core.quotepath true && beans init >/dev/null \
  && beans create 'auto groups' -t task -s todo >/dev/null && for f in .beans/*--*.md; do mv "$f" "${f%%--*}--auto-groups-dowódca-béret.md"; done \
  && git add -A && git commit -qm bean )
uid=$(ls "$T/ub/.beans" | sed -n 's/--.*//p' | head -1)
upass(){ ( cd "$T/ub" && env -u DROVER_PROJECT DROVER_REPO="$T/ub" FLEET_QUEUE="$T/uq" FLEET_INBOX="$T/uin" FLEET_TASKS="$T/utasks" \
  FLEET_STATE="$T/uw/state" DISPATCHES="$T/udispatches" "$T/dbin/fleet-watch" dispatch >/dev/null 2>"$T/u.err" ); }
upass
[ "$(cat "$T/udispatches" 2>/dev/null)" = "$uid" ] && ok 'a bean file named with ó/é is dispatched on the first pass' \
  || bad "non-ASCII bean: dispatches='$(cat "$T/udispatches" 2>/dev/null)' $(grep -E 'SKIP|QUEUE' "$T/uw/watch.log" 2>/dev/null | tail -2 | tr '\n' ' ') err: $(head -c 300 "$T/u.err")"
# The caller's environment already lists core.quotepath=true twice (git takes the last; keys are case-insensitive)
# plus an unrelated user.name. drover-env, sourced twice, must leave quotepath false, the name matcher working,
# user.name kept, and exactly one entry added. Overwriting only the first match left the second true (review).
out=$(cd "$T/ub" && env GIT_CONFIG_COUNT=3 GIT_CONFIG_KEY_0=core.quotepath GIT_CONFIG_VALUE_0=true GIT_CONFIG_KEY_1=user.name \
  GIT_CONFIG_VALUE_1=caller GIT_CONFIG_KEY_2=Core.QuotePath GIT_CONFIG_VALUE_2=true \
  bash -c '. "$0"; . "$0"; printf "%s %s %s " "$(git config --get core.quotepath)" "$(git config --get user.name)" "$GIT_CONFIG_COUNT"
  git ls-files .beans | grep -m1 "^.beans/$1--"' "$BIN/drover-env" "$uid" 2>/dev/null)
[ "$out" = "false caller 4 .beans/$uid--auto-groups-dowódca-béret.md" ] && ok 'inherited repeated core.quotepath=true entries: still false, name matches, caller entry kept' \
  || bad "inherited quotepath entries: '$out'"

