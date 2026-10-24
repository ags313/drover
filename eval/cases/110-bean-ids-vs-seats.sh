# shellcheck shell=bash
# --- bean ids vs seat names sharing the bean prefix ----------------------------------------------------------
# Bean prefix x-, seats x-claude-coder, x-grok-coder, x-codex-reviewer, lead x-lead. A follow-up citing x-ab12
# (on main) names seats that \b alone still reads as x-grok and x-lead. Only x-ab12 is checked; an uncited
# missing bean is still refused. herdr is stubbed: check_beans runs before the prompt is sent.
cd "$DROVER_REPO" || exit 1
bean x-ab12 todo; git add -A; git commit -qm 'chore(beans): x-ab12'
mkdir -p "$T/stub"; printf '#!/bin/sh\necho "{}"\n' > "$T/stub/herdr"; chmod +x "$T/stub/herdr"
seats='x-claude-coder:claude x-grok-coder:grok x-codex-reviewer:codex'
txt='fleet-done x-grok-coder x-ab12 DONE "fixed" /r/x-codex-reviewer-review-x-ab12-by-x-grok-coder.md; ask x-lead'
ids=$(DROVER_BEAN_PREFIX=x- DROVER_ROSTER="$seats" DROVER_LEAD_SEATS=x-lead bash -c '. "$0"; drover_bean_ids "$1"' "$BIN/drover-env" "$txt")
[ "$ids" = x-ab12 ] && ok 'bean ids skip seat names that share the bean prefix' || bad "bean ids: $(printf '%s' "$ids" | tr '\n' ' ')"
run_followup(){ PATH="$T/stub:$PATH" DROVER_BEAN_PREFIX=x- FLEET="$seats" DROVER_LEAD_SEATS=x-lead "$BIN"/fleet followup x-grok-coder "$1" 2>&1; }
out=$(run_followup "$txt"); rc=$?
[ "$rc" = 0 ] && ok 'followup to a seat sharing the bean prefix dispatches' || bad "followup refused (rc=$rc): $out"
out=$(run_followup "fleet-done x-grok-coder x-zz99"); rc=$?
[ "$rc" = 2 ] && grep -q 'bean x-zz99 not on' <<<"$out" && ok 'followup still refuses a cited bean missing from main' || bad "missing bean not refused (rc=$rc): $out"
