# shellcheck shell=bash
# --- fleet rules: every harness with a plugin-dir loader gets a manifest -------------------------------------
export FLEET_SKILLS="$T/skills"
out=$("$BIN"/fleet rules --dry-run 2>/dev/null)   # captured: grep -q under pipefail SIGPIPEs fleet
grep -qx 'host=cursor' <<<"$out" && ok 'rules dry-run would install the cursor manifest' || bad 'rules dry-run skips cursor'
"$BIN"/fleet rules >/dev/null 2>&1
grep -q '"host": "cursor"' "$FLEET_SKILLS/cursor/plugin.json" 2>/dev/null && [ -f "$FLEET_SKILLS/cursor/skills/fleet-peers/SKILL.md" ] \
  && ok 'rules installs cursor/plugin.json with fleet-peers' || bad 'rules installed no cursor manifest'
out=$("$BIN"/fleet rules --dry-run 2>/dev/null)
grep -q '^host=' <<<"$out" && bad 'rules dry-run reports a diff right after install' || ok 'rules dry-run quiet after install'
