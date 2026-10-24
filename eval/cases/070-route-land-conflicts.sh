# shellcheck shell=bash
# --- route_land_conflicts: the reason fleet-land-bean writes is the reason fleet-watch routes ----------------
# The real fleet-land-bean flags bean-rl (its only commit conflicts with main); a copy of fleet-watch beside a
# stub `fleet` (one live coder) runs one routing pass. bean-env's reason is an env failure -> stays flagged.
cd "$DROVER_REPO" || exit 1
echo 1 > src/r.txt; git add -A; git commit -qm 'r'
git checkout -qb fleet/c1-bean-rl; echo B > src/r.txt; git add -A; git commit -qm 'feat: r (bean-rl)'
git checkout -q main; echo M > src/r.txt; git add -A; git commit -qm 'main moves r'
"$BIN"/fleet-land-bean bean-rl >/dev/null 2>&1
rl_reason=$(cat "$FLEET_STATE/needs-land/bean-rl" 2>/dev/null)
echo 'typecheck failed on cherry-pick — manual land' > "$FLEET_STATE/needs-land/bean-env"
python3 -c 'import os, sys, time; t = time.time() - 300; [os.utime(f, (t, t)) for f in sys.argv[1:]]' \
  "$FLEET_STATE/needs-land/bean-rl" "$FLEET_STATE/needs-land/bean-env" 2>/dev/null
mkdir -p "$T/wbin"; cp "$BIN"/fleet-watch "$BIN"/drover-env "$T/wbin/"
printf '#!/usr/bin/env bash\n[ "$1" = status ] && printf "NAME KIND STATE\\nclaude-coder claude idle\\n"\n' > "$T/wbin/fleet"; chmod +x "$T/wbin/fleet"
FLEET_BRIEFS="$T/home/briefs" "$T/wbin/fleet-watch" route-land >/dev/null 2>&1
grep -q '^bean-rl	' "$FLEET_STATE/followups/claude-coder" 2>/dev/null && [ ! -e "$FLEET_STATE/needs-land/bean-rl" ] \
  && [ "$(cat "$FLEET_STATE/owner/bean-rl" 2>/dev/null)" = claude-coder ] \
  && ok "route-land hands fleet-land-bean's conflict flag to a live coder" \
  || bad "route-land bean-rl: reason='$rl_reason' still-flagged=$([ -e "$FLEET_STATE/needs-land/bean-rl" ] && echo yes || echo no) owner='$(cat "$FLEET_STATE/owner/bean-rl" 2>/dev/null)' followup=$(grep -c '^bean-rl	' "$FLEET_STATE/followups/claude-coder" 2>/dev/null)"
[ -e "$FLEET_STATE/needs-land/bean-env" ] && ok 'route-land keeps an env-failure flag' || bad 'route-land routed an env failure'
# bean-ro: the same real reason, but the brief cannot be written -> nothing recorded, so the flag stays
printf '%s\n' "$rl_reason" > "$FLEET_STATE/needs-land/bean-ro"
python3 -c 'import os, sys, time; t = time.time() - 300; os.utime(sys.argv[1], (t, t))' "$FLEET_STATE/needs-land/bean-ro"
chmod 555 "$T/home/briefs"
FLEET_BRIEFS="$T/home/briefs" "$T/wbin/fleet-watch" route-land >/dev/null 2>&1
chmod 755 "$T/home/briefs"
[ -e "$FLEET_STATE/needs-land/bean-ro" ] && [ ! -e "$FLEET_STATE/owner/bean-ro" ] && ! grep -q '^bean-ro	' "$FLEET_STATE/followups/claude-coder" \
  && ok 'route-land keeps the flag when the hand-off cannot be written' || bad 'route-land cleared a flag it could not hand off'
