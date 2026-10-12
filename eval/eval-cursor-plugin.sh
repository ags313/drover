#!/usr/bin/env bash
# eval-cursor-plugin — LIVE check that a cursor seat loads the fleet-peers skill that `fleet rules` installs.
#
# Network and a logged-in cursor-agent required (each trial is two short model calls), so it is not part of
# eval-checkers. Installs into a scratch FLEET_SKILLS, then runs the same prompt N times with
# `--plugin-dir <FLEET_SKILLS>/cursor` (must answer fleet-peers) and N times without (must answer NONE).
# Prerequisites read from cursor-agent 2026.10.01: an authenticated profile (the authless local profile sets
# enableUserLocalPlugins=false), and the team admin setting allowUserLocalPluginImports not set to false
# (headless -p reads it at startup; unset or a failed fetch allows the import).
# Usage: eval/eval-cursor-plugin.sh [trials] [model]   (default 3, cursor's own default model)
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
N=${1:-3}; MODEL=${2:-}
command -v cursor-agent >/dev/null || { echo 'cursor-agent not installed'; exit 2; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
DROVER_CONFIG=/dev/null DROVER_REPO="$ROOT" DROVER_HOME="$T/home" FLEET_SKILLS="$T/skills" \
  "$ROOT"/bin/fleet rules >/dev/null 2>&1 || { echo 'fleet rules failed'; exit 2; }
[ -f "$T/skills/cursor/plugin.json" ] || { echo 'no cursor manifest installed'; exit 1; }
mkdir -p "$T/ws"; cd "$T/ws" || exit 2
P="List the names of every skill available to you whose name contains 'fleet'. Print only the names, one per line, or NONE."
fail=0
for i in $(seq "$N"); do
  for arm in with without; do
    a=(-p --trust --mode ask --output-format json ${MODEL:+--model "$MODEL"})
    [ "$arm" = with ] && a+=(--plugin-dir "$T/skills/cursor")
    out=$(timeout 180 cursor-agent "${a[@]}" "$P" 2>&1); rc=$?
    res=$(jq -r '.result // empty' <<<"$out" 2>/dev/null | tr '\n' ' ')
    tok=$(jq -r '.usage.inputTokens // "?"' <<<"$out" 2>/dev/null)
    if [ "$arm" = with ]; then grep -q 'fleet-peers' <<<"$res" && v=ok || v=FAIL
    else grep -qw 'NONE' <<<"$res" && ! grep -q 'fleet-peers' <<<"$res" && v=ok || v=FAIL; fi   # empty is not NONE
    [ "$rc" = 0 ] || v=FAIL
    [ "$v" = ok ] || fail=1
    printf '%-4s trial=%s arm=%-7s rc=%s inputTokens=%s result=%s\n' "$v" "$i" "$arm" "$rc" "$tok" "$res"
  done
done
[ "$fail" = 0 ] && echo "cursor loads fleet-peers via --plugin-dir: $N/$N, control NONE: $N/$N" || { echo 'cursor plugin check FAILED'; exit 1; }
