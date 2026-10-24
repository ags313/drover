# shellcheck shell=bash
# --- fleet-budget: every harness the row filter accepts gets a row -------------------------------------------
# A copy of fleet-budget beside a stub `fleet` (DROVER_BIN is the script's own dir): two cursor seats, one grok.
mkdir -p "$T/bbin"; cp "$BIN"/fleet-budget "$BIN"/drover-env "$T/bbin/"
cat > "$T/bbin/fleet" <<'STUB'
#!/usr/bin/env bash
case $1 in
  status) printf 'NAME KIND STATE\ncursor-coder cursor idle\ncursor-reviewer cursor MISSING\ngrok-coder grok idle\n'; exit 1 ;;
  read) echo 'ready' ;;
esac
STUB
chmod +x "$T/bbin/fleet"
out=$("$T/bbin/fleet-budget" 2>/dev/null)
grep -qE '^cursor +2 +subscription$' <<<"$out" && ok 'budget counts cursor seats' || bad "budget cursor row: $(grep '^cursor' <<<"$out" || echo none)"
grep -qE '^grok +1 +subscription$' <<<"$out" && ok 'budget grok row unchanged' || bad "budget grok row: $(grep '^grok' <<<"$out" || echo none)"
