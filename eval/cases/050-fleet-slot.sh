# shellcheck shell=bash
# --- fleet-slot ----------------------------------------------------------------------------------------------
export FLEET_HEAVY_SLOTS=2   # one general slot (slot-2)
FLEET_SLOT_HELD=x "$BIN"/fleet-slot run -- true && ok 'slot re-entry runs directly' || bad 'slot re-entry failed'
# Milliseconds, not $SECONDS: that counter ticks on wall-clock second boundaries, so a 0.2 s call that
# straddles one reads as "1 s" and the push case went red on a quiet machine (2026-10-21).
now_ms(){ if [ -n "${EPOCHREALTIME:-}" ]; then local t=${EPOCHREALTIME/./}; echo $((t / 1000)); else python3 -c 'import time; print(int(time.time() * 1000))'; fi; }
"$BIN"/fleet-slot run -- sleep 3 & holder=$!; sleep 1
s=$(now_ms); "$BIN"/fleet-slot run -- true 2>/dev/null; waited=$(( $(now_ms) - s )); wait $holder
[ "$waited" -ge 1000 ] && ok "second general run waited for the slot (${waited}ms)" || bad "second general run did not wait (${waited}ms)"
"$BIN"/fleet-slot run -- sleep 3 & holder=$!; sleep 1
s=$(now_ms); "$BIN"/fleet-slot run --push -- true; waited=$(( $(now_ms) - s )); wait $holder
# The holder has ~2 s left: a push that waited for it reads >= 2000 ms, a free push slot well under that.
[ "$waited" -lt 1500 ] && ok "a push does not wait behind a general run (${waited}ms)" || bad "push waited ${waited}ms behind a general run"

