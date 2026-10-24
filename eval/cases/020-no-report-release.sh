# shellcheck shell=bash
# --- no-report release: ownership follows the released task --------------------------------------
mkdir -p "$T/release-bin" "$T/release/tasks" "$T/release/state/owner"
cp "$BIN"/drover-env "$T/release-bin/"
# Expose only the existing reap step in the scratch copy; dispatch remains the production path.
sed '/^if .* = once /i\
if [ "${1:-}" = eval-reap ]; then reap_tasks; exit 0; fi' "$BIN/fleet-watch" > "$T/release-bin/fleet-watch"
chmod +x "$T/release-bin/fleet-watch"
cat > "$T/release-bin/fleet" <<'STUB'
#!/usr/bin/env bash
case $1 in
  status) printf 'NAME KIND STATE\nx-next-coder claude idle\nx-old-coder opencode idle\n' ;;
  assign) printf '%s %s\n' "$2" "$3" >> "$RELEASE_DISPATCHES" ;;
esac
STUB
chmod +x "$T/release-bin/fleet"
release_env(){ FLEET_TASKS="$T/release/tasks" FLEET_STATE="$T/release/state" FLEET_QUEUE="$T/release/queue" \
  FLEET_INBOX="$T/release/inbox" FLEET_REPORTS="$T/release/reports" RELEASE_DISPATCHES="$T/release/dispatches" \
  "$T/release-bin/fleet-watch" "$@" >/dev/null; }
printf '%s\tbean-todo\t-\t-\n' "$(( $(date +%s) - 5400 ))" > "$T/release/tasks/x-old-coder"
echo x-old-coder > "$T/release/state/owner/bean-todo"
release_env eval-reap
[ ! -f "$T/release/tasks/x-old-coder" ] && [ ! -f "$T/release/state/owner/bean-todo" ] \
  && ok 'no-report release removes the released seat owner at 90 minutes' || bad 'no-report release retained task or owner'
release_env dispatch
[ "$(cat "$T/release/dispatches" 2>/dev/null)" = 'bean-todo x-next-coder' ] \
  && ok 'next dispatch hands the released bean to another idle coder' || bad 'released bean did not reach next coder'
printf '%s\tbean-todo\t-\t-\n' "$(( $(date +%s) - 5400 ))" > "$T/release/tasks/x-old-coder"
echo x-next-coder > "$T/release/state/owner/bean-todo"
release_env eval-reap
[ ! -f "$T/release/tasks/x-old-coder" ] && [ "$(cat "$T/release/state/owner/bean-todo")" = x-next-coder ] \
  && ok 'no-report release preserves a different seat owner' || bad 'no-report release removed another seat owner'

