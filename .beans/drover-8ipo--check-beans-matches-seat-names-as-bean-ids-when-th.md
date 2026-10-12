---
# drover-8ipo
title: check_beans matches seat names as bean ids when the seat prefix equals the bean prefix
status: todo
type: bug
priority: high
created_at: 2026-10-12T10:15:17Z
updated_at: 2026-10-12T10:15:17Z
---

In the drover project the seats are drover-claude-coder and drover-codex-reviewer and the bean prefix is drover-. Every fix-round follow-up fails:

    FOLLOWUP drover-t59r -> drover-claude-coder FAILED (rc=2: bean drover-clau drover-code not on nixos-multiproject) — requeued, agent left free

check_beans (bin/fleet:600-611) greps DROVER_BEAN_RE (bin/drover-env) over the prompt text. The follow-up text contains "fleet-done drover-claude-coder drover-t59r" and the report path ".../drover-codex-reviewer-review-...". The regex has no trailing boundary, so "drover-clau" and "drover-code" match as bean ids, and the dispatch is refused. The follow-up is requeued every tick (2026-10-12 11:09-11:13, ~/.local/share/drover/projects/drover/logs/fleet-watch.out). install.sh --project NAME seeds seats as NAME-<harness>-<role>, so every project whose bean prefix is NAME- hits this.

Fix:
1. DROVER_BEAN_RE ends with a boundary: the id is followed by a non-[a-z0-9] character or the end of text.
2. check_beans also ignores any match that is a prefix of a roster seat name.
3. Test: eval check with prefix x-, seat x-claude-coder, text "fleet-done x-claude-coder x-ab12": only x-ab12 is checked.

- [ ] follow-ups dispatch in a project whose seat prefix equals the bean prefix
- [ ] eval check covers the collision
- [ ] drover-t59r's queued follow-up dispatches after the fix lands
