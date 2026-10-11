#!/usr/bin/env bash
# install.sh — put drover on this machine. Idempotent; prints every action before (or instead of) doing it.
#
#   ./install.sh                  symlink bin/* into ~/.local/bin, create state dirs, seed config + briefs,
#                                 render the service units (not loaded): launchd plists into ~/Library/LaunchAgents
#                                 on macOS, systemd user units into ~/.config/systemd/user elsewhere
#   ./install.sh --load           ...and start fleet-watch, fleet-stale, fleet-standup-hourly, graphify-nightly
#   ./install.sh --load-watchdog  ...and also lead-watchdog (only if you run a backup-lead seat)
#   ./install.sh --dry-run        print the plan, change nothing
#   ./install.sh --force          replace existing files in ~/.local/bin that are not drover symlinks
#   ./install.sh --uninstall      stop + remove the units and the symlinks; keeps config and state
#
# Env: DROVER_BIN_DIR (default ~/.local/bin), DROVER_HOME (default ~/.local/share/drover),
#      DROVER_CONFIG_DIR (default ~/.config/drover), DROVER_SERVICES (launchd | systemd | none; default:
#      launchd if launchctl exists, else systemd if systemctl exists), LAUNCH_AGENTS (default
#      ~/Library/LaunchAgents), SYSTEMD_USER_DIR (default ~/.config/systemd/user)
set -euo pipefail
SRC="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="${DROVER_BIN_DIR:-$HOME/.local/bin}"
HOME_DIR="${DROVER_HOME:-$HOME/.local/share/drover}"
CFG_DIR="${DROVER_CONFIG_DIR:-$HOME/.config/drover}"
LA="${LAUNCH_AGENTS:-$HOME/Library/LaunchAgents}"
SD="${SYSTEMD_USER_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user}"
if [ -z "${DROVER_SERVICES:-}" ]; then
  if command -v launchctl >/dev/null; then DROVER_SERVICES=launchd
  elif command -v systemctl >/dev/null; then DROVER_SERVICES=systemd
  else DROVER_SERVICES=none; fi
fi
DRY=0 FORCE=0 LOAD=0 WATCHDOG=0 UNINSTALL=0
for a in "$@"; do case $a in
  --dry-run) DRY=1 ;; --force) FORCE=1 ;; --load) LOAD=1 ;; --load-watchdog) LOAD=1 WATCHDOG=1 ;;
  --uninstall) UNINSTALL=1 ;; -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
  *) echo "unknown option: $a" >&2; exit 64 ;; esac; done

run(){ echo "  $*"; [ "$DRY" = 1 ] || "$@"; }
say(){ echo "$*"; }
sed_esc(){ printf '%s' "$1" | sed -e 's/[\\|&]/\\&/g'; }
[ "$DRY" = 1 ] && say "(dry run — nothing is changed)"

# One job per template: a launchd plist, or a systemd service (+ a timer for the periodic ones).
jobs(){
  case $DROVER_SERVICES in
    launchd) for t in "$SRC"/launchd/*.plist.in; do basename "$t" .plist.in; done ;;
    systemd) for t in "$SRC"/systemd/*.service.in; do basename "$t" .service.in; done ;;
  esac
}
# The unit systemd starts and stops for a job: its timer when it has one.
sd_unit(){ if [ -f "$SRC/systemd/$1.timer.in" ]; then echo "$1.timer"; else echo "$1.service"; fi; }

if [ "$UNINSTALL" = 1 ]; then
  say "$DROVER_SERVICES:"
  for job in $(jobs); do
    case $DROVER_SERVICES in
      launchd)
        p="$LA/$job.plist"; [ -f "$p" ] || continue
        launchctl print "gui/$(id -u)/$job" >/dev/null 2>&1 && run launchctl bootout "gui/$(id -u)/$job"
        run rm -f "$p" ;;
      systemd)
        [ -f "$SD/$job.service" ] || continue
        systemctl --user is-enabled --quiet "$(sd_unit "$job")" 2>/dev/null && run systemctl --user disable --now "$(sd_unit "$job")"
        systemctl --user is-active --quiet "$job.service" 2>/dev/null && run systemctl --user stop "$job.service"
        run rm -f "$SD/$job.service" "$SD/$job.timer" ;;
    esac
  done
  [ "$DROVER_SERVICES" = systemd ] && run systemctl --user daemon-reload
  say "symlinks in $BIN_DIR:"
  for f in "$SRC"/bin/*; do
    l="$BIN_DIR/$(basename "$f")"
    [ -L "$l" ] && [ "$(readlink "$l")" = "$f" ] && run rm -f "$l"
  done
  say "kept: $CFG_DIR (config) and $HOME_DIR (state, reports). Remove them by hand if you want them gone."
  exit 0
fi

say "symlinks in $BIN_DIR:"
[ -d "$BIN_DIR" ] || run mkdir -p "$BIN_DIR"
for f in "$SRC"/bin/*; do
  l="$BIN_DIR/$(basename "$f")"
  if [ -L "$l" ] && [ "$(readlink "$l")" = "$f" ]; then continue; fi
  if [ -e "$l" ] || [ -L "$l" ]; then
    if [ "$FORCE" = 1 ]; then run rm -f "$l"
    else say "  SKIP $l — exists and is not a drover symlink (rerun with --force to replace it)"; continue; fi
  fi
  run ln -s "$f" "$l"
done

say "state dirs in $HOME_DIR:"
for d in queue inbox tasks briefs reports snapshots watch/state retro pump logs; do
  [ -d "$HOME_DIR/$d" ] || run mkdir -p "$HOME_DIR/$d"
done

say "config in $CFG_DIR:"
[ -d "$CFG_DIR" ] || run mkdir -p "$CFG_DIR"
for f in config caps; do
  [ -f "$CFG_DIR/$f" ] || run cp "$SRC/examples/$f" "$CFG_DIR/$f"
done
for f in "$SRC"/examples/briefs/*; do
  [ -f "$HOME_DIR/briefs/$(basename "$f")" ] || run cp "$f" "$HOME_DIR/briefs/"
done

# render TEMPLATE DEST: fill @BIN@, @LOGS@ and @PATH@; write DEST only when it changed. Exit 0 = written.
# The PATH every unit runs with. Units outlive the shell: drop /nix/store entries (a nix-shell or direnv PATH),
# which garbage collection deletes; the profile dirs (/run/current-system/sw/bin, ~/.nix-profile/bin, ...) stay.
UNIT_PATH=$(IFS=:; for d in $PATH; do case $d in /nix/store/*|'') ;; *) printf '%s:' "$d" ;; esac; done)
UNIT_PATH=${UNIT_PATH%:}
render(){
  local tmp rc=1; tmp=$(mktemp)
  # systemd expands %-specifiers inside unit files, so a literal % in PATH is written %%.
  local path=$UNIT_PATH; [ "$DROVER_SERVICES" = systemd ] && path=${path//%/%%}
  sed -e "s|@BIN@|$(sed_esc "$BIN_DIR")|g" -e "s|@LOGS@|$(sed_esc "$HOME_DIR/logs")|g" \
      -e "s|@PATH@|$(sed_esc "$path")|g" "$1" > "$tmp"
  if [ -f "$2" ] && cmp -s "$tmp" "$2"; then :
  else echo "  render ${1#"$SRC"/} -> $2"; [ "$DRY" = 1 ] || cp "$tmp" "$2"; rc=0; fi
  rm -f "$tmp"; return $rc
}

case $DROVER_SERVICES in
launchd)
  say "launchd plists in $LA:"
  [ -d "$LA" ] || run mkdir -p "$LA"
  for job in $(jobs); do
    p="$LA/$job.plist"
    render "$SRC/launchd/$job.plist.in" "$p" || true
    case $job in *lead-watchdog) [ "$WATCHDOG" = 1 ] || continue ;; esac
    if [ "$LOAD" = 1 ]; then
      launchctl print "gui/$(id -u)/$job" >/dev/null 2>&1 && run launchctl bootout "gui/$(id -u)/$job"
      run launchctl bootstrap "gui/$(id -u)" "$p"
    fi
  done ;;
systemd)
  say "systemd user units in $SD:"
  [ -d "$SD" ] || run mkdir -p "$SD"
  changed=0
  for t in "$SRC"/systemd/*.in; do
    render "$t" "$SD/$(basename "$t" .in)" && changed=1
  done
  [ "$changed" = 1 ] && run systemctl --user daemon-reload
  # A tool found only through nix-shell is not on UNIT_PATH: the watcher would run without it (no sqlite3: no
  # spend cap; no lsof: no worktree sweep). shell.nix lists them all; install them in your profile.
  missing=$(for t in git jq python3 perl sqlite3 lsof herdr beans systemd-run; do
    PATH=$UNIT_PATH command -v "$t" >/dev/null || printf ' %s' "$t"; done)
  [ -z "$missing" ] || say "WARN: not on the units' PATH:$missing — install them in your user or system profile (see shell.nix)"
  if [ "$LOAD" = 1 ]; then
    for job in $(jobs); do
      case $job in *lead-watchdog) [ "$WATCHDOG" = 1 ] || continue ;; esac
      run systemctl --user enable "$(sd_unit "$job")"
      run systemctl --user restart "$(sd_unit "$job")"
    done
    # A user manager stops every unit at logout unless the user lingers.
    [ "$(loginctl show-user "$(id -un)" -p Linger --value 2>/dev/null)" = yes ] || \
      say "NOTE: drover stops when you log out. Keep it running with: loginctl enable-linger $(id -un)"
  fi ;;
none)
  say "no launchctl or systemctl: no service units rendered. Run fleet-watch run under your own supervisor." ;;
esac

# shellcheck disable=SC1091
( . "$CFG_DIR/config" 2>/dev/null; [ -n "${DROVER_REPO:-}" ] ) || \
  say "NEXT: set DROVER_REPO in $CFG_DIR/config to your project checkout, then run: fleet up"
case ":$PATH:" in *":$BIN_DIR:"*) ;; *) say "NOTE: $BIN_DIR is not on your PATH." ;; esac
[ "$LOAD" = 1 ] || [ "$DROVER_SERVICES" = none ] || say "Units are rendered but not started. Start them with: ./install.sh --load"
