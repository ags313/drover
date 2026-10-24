# shellcheck shell=bash
# --- clear_dialogs: folder-trust prompts are answered; a changed layout or bare chrome is left alone ----
# A copy of fleet-watch beside a stub `fleet`: status lists the seats, read prints $SCREENS/<seat>, keys logs.
mkdir -p "$T/kbin" "$T/screens"; cp "$BIN"/fleet-watch "$BIN"/drover-env "$T/kbin/"
cat > "$T/kbin/fleet" <<'STUB'
#!/usr/bin/env bash
case $1 in
  status) printf 'NAME KIND STATE\n'; for f in "$SCREENS"/*; do printf '%s x idle\n' "${f##*/}"; done ;;
  read) cat "$SCREENS/$2" ;;
  keys) shift; echo "$*" >> "$KEYS" ;;
esac
exit 0
STUB
chmod +x "$T/kbin/fleet"
printf '  Trust this folder? Codex can read, edit, and run files here, ...\n\n› 1. Trust and continue\n  2. Quit\n\n  enter continue · esc quit\n' > "$T/screens/cx-on1"
printf '  1. Trust and continue\n› 2. Quit\n\n  enter continue · esc quit\n' > "$T/screens/cx-on2"
printf ' ❯ No, exit\n   Yes, I trust this folder\n\n Enter to confirm · Esc to exit\n' > "$T/screens/cl-trust"
cat > "$T/screens/agy-on1" <<'SCREEN'
Accessing workspace:
/home/ags/.herdr/worktrees/bob/fleet-bob-agy-coder
Do you trust the contents of this project?
Antigravity CLI requires permission to read, edit, and execute files here.
> Yes, I trust this folder
  No, exit
  ↑/↓ Navigate · enter Confirm
SCREEN
sed 's/^> Yes/  Yes/; s/^  No/> No/' "$T/screens/agy-on1" > "$T/screens/agy-on2"
printf '  Working (12s)\n\n  enter continue · esc quit\n' > "$T/screens/cx-chrome"
SCREENS="$T/screens" KEYS="$T/keys" FLEET_STATE="$T/kw/state" "$T/kbin/fleet-watch" dialogs >/dev/null 2>&1
grep -qx 'cx-on1 Enter' "$T/keys" && grep -q 'dialog: trusted own worktree on cx-on1 (codex)$' "$T/kw/watch.log" \
  && ok 'clear_dialogs: codex folder-trust with the cursor on "1. Trust and continue" gets Enter, logged (codex)' \
  || bad "codex trust: keys=$(tr '\n' '|' < "$T/keys" 2>/dev/null) log=$(tr '\n' '|' < "$T/kw/watch.log" 2>/dev/null)"
grep -qx 'cl-trust Down Enter' "$T/keys" && grep -q 'dialog: trusted own worktree on cl-trust$' "$T/kw/watch.log" \
  && ok 'clear_dialogs: the Claude folder-trust case is unchanged (Down Enter)' || bad "claude trust: keys=$(tr '\n' '|' < "$T/keys" 2>/dev/null)"
grep -qx 'agy-on1 Enter' "$T/keys" && grep -q 'dialog: trusted own worktree on agy-on1 (agy)$' "$T/kw/watch.log" \
  && ok 'clear_dialogs: Antigravity folder-trust with the cursor on Yes gets Enter, logged (agy)' \
  || bad "agy trust: keys=$(tr '\n' '|' < "$T/keys" 2>/dev/null) log=$(tr '\n' '|' < "$T/kw/watch.log" 2>/dev/null)"
[ "$(wc -l < "$T/keys")" = 3 ] && ok 'clear_dialogs: cursor on No or "2. Quit" and bare "enter continue" chrome get no keys' \
  || bad "dialog keys sent to the wrong seats: $(tr '\n' '|' < "$T/keys")"

# Silent seat recovery: real tracked changes, persistent state, bounded prompt stub.
mkdir -p "$T/sbin" "$T/silent/tasks" "$T/silent/inbox"
cp "$BIN"/fleet-watch "$BIN"/drover-env "$T/sbin/"
git clone -q "$T/origin.git" "$T/silent-wt" 2>/dev/null
git -C "$T/silent-wt" checkout -qb main origin/main
git -C "$T/silent-wt" checkout -qb fleet/test-coder
printf 'dirty\n' >> "$T/silent-wt/src/a.txt"
cat > "$T/sbin/fleet" <<'STUB'
#!/usr/bin/env bash
printf 'NAME KIND STATE\ntest-coder opencode %s\nother-coder opencode MISSING\n' "$(cat "$SILENT_ROOT/status")"
exit 1 # Real fleet status returns nonzero if another roster seat is missing.
STUB
cat > "$T/sbin/herdr" <<'STUB'
#!/usr/bin/env bash
case $2 in
  get) jq -n --arg cwd "$SILENT_ROOT/../silent-wt" '{result:{agent:{cwd:$cwd}}}' ;;
  prompt) printf '%s\n' "$*" >> "$SILENT_ROOT/prompts" ;;
esac
STUB
chmod +x "$T/sbin/fleet" "$T/sbin/herdr"
printf '1\tbean-silent\n' > "$T/silent/tasks/test-coder"
echo 'done' > "$T/silent/status"
spass(){ PATH="$T/sbin:$PATH" SILENT_ROOT="$T/silent" FLEET_TASKS="$T/silent/tasks" FLEET_STATE="$T/silent/state" FLEET_INBOX="$T/silent/inbox" "$T/sbin/fleet-watch" silent >/dev/null; }
sdir="$T/silent/state/silent/bean-silent"
spass
[ ! -f "$T/silent/prompts" ] && ok 'silent: fresh idle seat is not nudged' || bad 'silent: premature nudge'
echo $(( $(date +%s)-300 )) > "$sdir/idle"
spass; spass
[ "$(wc -l < "$T/silent/prompts")" = 1 ] && grep -q 'finish bean-silent: run the gate, commit, report, announce with fleet-done' "$T/silent/prompts" \
  && [ "$(grep -c 'NUDGE test-coder bean-silent$' "$T/silent/watch.log")" = 1 ] \
  && ok 'silent: five minutes idle with tracked changes sends exactly one nudge' || bad 'silent: missing or repeated prompt'
echo working > "$T/silent/status"; spass
echo 'done' > "$T/silent/status"; spass
echo $(( $(date +%s)-300 )) > "$sdir/idle"
echo $(( $(date +%s)-300 )) > "$sdir/nudged"
spass; spass
[ "$(wc -l < "$T/silent/prompts")" = 1 ] && [ "$(grep -c 'needs lead: silent seat' "$T/silent/state/blocked")" = 1 ] \
  && ok 'silent: second stop flags the bean once without another nudge' || bad 'silent: second-stop escalation'
# Announcements suppress even an overdue idle seat; keep each verdict in the inbox.
for verdict in DONE BLOCKED PARTIAL; do
  rm -f "$sdir/announced" "$sdir/nudged" "$sdir/flagged"
  printf '2\ttest-coder\tbean-silent\t%s\tsummary\treport\n' "$verdict" > "$T/silent/inbox/a.msg"
  spass
  [ -f "$sdir/announced" ] && [ "$(wc -l < "$T/silent/prompts")" = 1 ] \
    && ok "silent: $verdict announcement prevents nudge" || bad "silent: nudged after $verdict"
done
# A clean worktree with bean commits still needs recovery; untracked-only does not.
rm -f "$T/silent/inbox/a.msg" "$sdir/announced" "$sdir/nudged" "$sdir/flagged"
git -C "$T/silent-wt" -c user.name=eval -c user.email=eval@example.invalid commit -qam 'bean-silent work'
spass
[ "$(wc -l < "$T/silent/prompts")" = 2 ] && ok 'silent: clean tree with commits ahead is nudged' || bad 'silent: missed unreported commits'

# Clean at the base (including untracked-only scratch) is never unfinished work.
git -C "$T/silent-wt" branch -f main HEAD
rm -f "$sdir/nudged" "$sdir/flagged"
echo scratch > "$T/silent-wt/untracked"
spass
[ "$(wc -l < "$T/silent/prompts")" = 2 ] && ok 'silent: untracked-only tree at base is not nudged' || bad 'silent: nudged a clean tracked tree'
echo dirty >> "$T/silent-wt/src/a.txt"
echo working > "$T/silent/status"; spass
echo 'done' > "$T/silent/status"; spass
[ "$(wc -l < "$T/silent/prompts")" = 2 ] && ok 'silent: working resets the continuous idle window' || bad 'silent: task age mistaken for idle age'

# An announcement belongs to a dispatch, not all future rounds of the bean.
printf '10\tbean-round\n' > "$T/silent/tasks/test-coder"
printf '11\ttest-coder\tbean-round\tDONE\tsummary\treport\n' > "$T/silent/inbox/a.msg"
spass
rdir="$T/silent/state/silent/bean-round"
rm -f "$T/silent/inbox/a.msg" # Simulate the inbox drain after recording the marker.
echo $(( $(date +%s)-300 )) > "$rdir/idle"
spass
[ -f "$rdir/announced" ] && [ "$(wc -l < "$T/silent/prompts")" = 2 ] \
  && ok 'silent: drained DONE still suppresses the same task' || bad 'silent: lost announcement on same task'
printf '12\tbean-round\n' > "$T/silent/tasks/test-coder"
spass
echo $(( $(date +%s)-300 )) > "$rdir/idle"
spass; spass
[ ! -f "$rdir/announced" ] && [ "$(wc -l < "$T/silent/prompts")" = 3 ] \
  && [ "$(grep -c 'NUDGE test-coder bean-round$' "$T/silent/watch.log")" = 1 ] \
  && ok 'silent: new task for an announced bean gets one nudge after five idle minutes' || bad 'silent: old DONE hid a later round'
help=$("$T/sbin/fleet-watch" --help)
printf '%s\n' "$help" | grep -q 'fleet-watch enqueue' && printf '%s\n' "$help" | grep -q 'fleet-watch queue ' \
  && ok 'watch help includes enqueue and queue' || bad 'watch help truncates usage'

