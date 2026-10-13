---
# drover-ot0a
title: 'fleet: per-seat model pin and lead-only seats for a local ollama coder'
status: todo
type: feature
priority: high
created_at: 2026-10-13T20:36:25Z
updated_at: 2026-10-13T20:36:25Z
---

Owner 2026-10-13: a local qwen model runs under ollama (`qwen3-coder-next:q4_K_M`, 262k context, GPU). It joins the fleet as a coder for simple tasks. Verified: `~/.config/opencode/opencode.jsonc` has an `ollama` provider (`@ai-sdk/openai-compatible`, baseURL `http://localhost:11434/v1`) and `opencode run --model ollama/qwen3-coder-next:q4_K_M "..."` answers.

Two gaps in drover:
1. The model pin is per harness kind (`FLEET_OPENCODE_MODEL` in `bin/fleet` `agent_args()`). A second opencode seat cannot run a different model from `opencode-coder`.
2. Every seat on the roster gets beans from the watcher's top-up and refill. A small local model must receive only beans the lead hands to it.

Change 1, per-seat model pin:
- `agent_args()` takes the seat name as well as the kind (its caller at the spawn site passes both).
- After the kind's args, append ` --model $m` when `FLEET_MODEL_<seat>` is set (seat name with `-` replaced by `_`, for example `FLEET_MODEL_qwen_coder`) and the kind accepts `--model` (claude, opencode, agy). The per-seat value wins over the kind pin.
- Header comment next to `FLEET_OPENCODE_MODEL`: the variable, and that it is a spawn-time flag like the others. `fleet models` keeps reading the live model from the harness state.

Change 2, lead-only seats:
- Config `DROVER_MANUAL_SEATS` (space-separated seat names). The watcher's top-up and refill in `bin/fleet-watch` never dispatch to a seat on that list. `fleet assign <bean> <seat>` and `fleet review` work as before. Reviews of its branches route by the existing same-harness rule (kind opencode).
- `fleet status` marks such a seat (STATE suffix or a TITLE prefix "manual"), so the roster shows why it idles.

Docs: README section "Local model seat (ollama through opencode)": the provider snippet, roster line `qwen-coder:opencode`, `FLEET_MODEL_qwen_coder=ollama/qwen3-coder-next:q4_K_M`, `DROVER_MANUAL_SEATS=qwen-coder`, and that `fleet up` spawns it.

Tests: eval cases next to the existing ones in `eval/`: (a) `agent_args` with a per-seat pin emits `--model` for opencode and claude, not for codex or cursor; (b) refill with a manual seat free and a ready bean leaves the seat idle; (c) `fleet assign` to a manual seat succeeds.

Acceptance:
- [ ] two opencode seats run two different models after `fleet up`
- [ ] a seat in `DROVER_MANUAL_SEATS` never receives a bean from the watcher
- [ ] `fleet assign <bean> qwen-coder` dispatches to it
- [ ] docs and eval cases in place
