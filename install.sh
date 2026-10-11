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
#   ./install.sh --project NAME [--repo PATH] [--load] ...
#                                 one of several projects, each with its own repository, roster, state and
#                                 watcher: config ~/.config/drover/projects/NAME/config (seeded with seat names
#                                 prefixed NAME-, DROVER_REPO=PATH), state ~/.local/share/drover/projects/NAME,
#                                 units drover-<job>@NAME (systemd) / dev.drover.<job>.NAME (launchd).
#                                 --uninstall --project NAME removes only that project's units.
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
DRY=0 FORCE=0 LOAD=0 WATCHDOG=0 UNINSTALL=0 PROJECT="" REPO=""
while [ $# -gt 0 ]; do case $1 in
  --dry-run) DRY=1 ;; --force) FORCE=1 ;; --load) LOAD=1 ;; --load-watchdog) LOAD=1 WATCHDOG=1 ;;
  --uninstall) UNINSTALL=1 ;;
  --project) PROJECT=${2:?--project NAME}; shift ;; --project=*) PROJECT=${1#*=} ;;
  --repo) REPO=${2:?--repo PATH}; shift ;; --repo=*) REPO=${1#*=} ;;
  -h|--help) sed -n '2,23p' "$0"; exit 0 ;;
  *) echo "unknown option: $1" >&2; exit 64 ;; esac; shift; done

# The config the scripts read, and where this install's state lives (bin/drover-env resolves the same paths).
CFG_FILE="$CFG_DIR/config"
if [ -n "$PROJECT" ]; then
  # The name is part of unit names, paths and the seats' shell: keep it to what is safe in all three.
  [[ $PROJECT =~ ^[a-z0-9][a-z0-9_-]*$ ]] || { echo "--project: use lowercase letters, digits, - and _" >&2; exit 64; }
  CFG_FILE="${DROVER_PROJECTS_DIR:-$CFG_DIR/projects}/$PROJECT/config"
  HOME_DIR="$HOME/.local/share/drover/projects/$PROJECT"
fi
[ -z "$REPO" ] || [ -n "$PROJECT" ] || { echo "--repo needs --project (set DROVER_REPO in $CFG_FILE instead)" >&2; exit 64; }
[ -z "$REPO" ] || REPO=$(cd "$REPO" && pwd) || { echo "--repo: no such directory" >&2; exit 64; }

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
# A job's unit name in this install: drover-fleet-watch, or drover-fleet-watch@NAME / dev.drover.fleet-watch.NAME.
unit(){
  if [ -z "$PROJECT" ]; then echo "$1"
  elif [ "$DROVER_SERVICES" = launchd ]; then echo "$1.$PROJECT"
  else echo "$1@$PROJECT"; fi
}
# The unit systemd starts and stops for a job: its timer when it has one.
sd_unit(){ if [ -f "$SRC/systemd/$1.timer.in" ]; then echo "$(unit "$1").timer"; else echo "$(unit "$1").service"; fi; }

if [ "$UNINSTALL" = 1 ]; then
  say "$DROVER_SERVICES${PROJECT:+ (project $PROJECT)}:"
  for job in $(jobs); do
    u=$(unit "$job")
    case $DROVER_SERVICES in
      launchd)
        p="$LA/$u.plist"; [ -f "$p" ] || continue
        launchctl print "gui/$(id -u)/$u" >/dev/null 2>&1 && run launchctl bootout "gui/$(id -u)/$u"
        run rm -f "$p" ;;
      systemd)
        [ -f "$SD/$u.service" ] || continue
        systemctl --user is-enabled --quiet "$(sd_unit "$job")" 2>/dev/null && run systemctl --user disable --now "$(sd_unit "$job")"
        systemctl --user is-active --quiet "$u.service" 2>/dev/null && run systemctl --user stop "$u.service"
        run rm -f "$SD/$u.service" "$SD/$u.timer" ;;
    esac
  done
  [ "$DROVER_SERVICES" = systemd ] && run systemctl --user daemon-reload
  if [ -n "$PROJECT" ]; then   # the scripts are shared by every project: they stay
    say "kept: $CFG_FILE (config), $HOME_DIR (state, reports) and the scripts in $BIN_DIR."
    exit 0
  fi
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

say "config in $(dirname "$CFG_FILE"):"
[ -d "$(dirname "$CFG_FILE")" ] || run mkdir -p "$(dirname "$CFG_FILE")"
[ -d "$CFG_DIR" ] || run mkdir -p "$CFG_DIR"
[ -f "$CFG_DIR/caps" ] || run cp "$SRC/examples/caps" "$CFG_DIR/caps"   # spend caps: one machine, one budget
if [ ! -f "$CFG_FILE" ]; then
  if [ -z "$PROJECT" ]; then run cp "$SRC/examples/config" "$CFG_FILE"
  else
    # herdr seat names are global, so two projects' seats must never share one: every seat is NAME-<seat>.
    # The role is still the name's last word (forum-claude-coder is a coder).
    echo "  seed $CFG_FILE (seats prefixed $PROJECT-${REPO:+, DROVER_REPO=$REPO})"
    [ "$DRY" = 1 ] || sed -E \
      -e "/^DROVER_ROSTER=/s/(:-| )([a-z][a-z0-9-]*:[a-z]+)/\\1$PROJECT-\\2/g" \
      -e "/^DROVER_LEAD_SEATS=/s/(:-| )(lead[a-z0-9-]*)/\\1$PROJECT-\\2/g" \
      -e "s|^DROVER_REPO=\"\\\$\\{DROVER_REPO:-\\}\"|DROVER_REPO=\"\${DROVER_REPO:-$(sed_esc "$REPO")}\"|" \
      "$SRC/examples/config" > "$CFG_FILE"
  fi
fi
for f in "$SRC"/examples/briefs/*; do
  [ -f "$HOME_DIR/briefs/$(basename "$f")" ] || run cp "$f" "$HOME_DIR/briefs/"
done

# Every config's seats and repository, read the way drover-env reads them (environment cleared first).
cfg_get(){ env -u DROVER_REPO -u DROVER_ROSTER -u DROVER_LEAD_SEATS bash -c '. "$1" >/dev/null 2>&1; printf "%s" "${!2:-}"' _ "$1" "$2"; }
all_cfgs(){ ls "$CFG_DIR/config" "${DROVER_PROJECTS_DIR:-$CFG_DIR/projects}"/*/config 2>/dev/null || true; }
if [ -f "$CFG_FILE" ]; then
  # Two configs naming one seat would both dispatch into it; two on one repository would both land and push.
  me_repo=$(cfg_get "$CFG_FILE" DROVER_REPO)
  me_seats=$(for s in $(cfg_get "$CFG_FILE" DROVER_ROSTER) $(cfg_get "$CFG_FILE" DROVER_LEAD_SEATS); do echo "${s%%:*}"; done)
  for c in $(all_cfgs); do
    [ "$c" -ef "$CFG_FILE" ] && continue
    r=$(cfg_get "$c" DROVER_REPO); [ -n "$r" ] || continue   # an unconfigured default config runs nothing
    [ -n "$me_repo" ] && [ "$r" -ef "$me_repo" ] && say "WARN: $c works on the same repository ($r): run one watcher per repository"
    dup=$(for s in $(cfg_get "$c" DROVER_ROSTER) $(cfg_get "$c" DROVER_LEAD_SEATS); do echo "${s%%:*}"; done | grep -Fx -f <(echo "$me_seats") | tr '\n' ' ' || true)
    [ -z "$dup" ] || say "WARN: seat names also in $c: $dup— herdr names are global, rename them in one of the two"
  done
fi

# render TEMPLATE DEST: fill @BIN@, @LOGS@, @PATH@, @LABEL@ and @PROJECT_ENV@; write DEST only when it changed.
# Exit 0 = written.
# The PATH every unit runs with. Units outlive the shell: drop /nix/store entries (a nix-shell or direnv PATH),
# which garbage collection deletes; the profile dirs (/run/current-system/sw/bin, ~/.nix-profile/bin, ...) stay.
UNIT_PATH=$(IFS=:; for d in $PATH; do case $d in /nix/store/*|'') ;; *) printf '%s:' "$d" ;; esac; done)
UNIT_PATH=${UNIT_PATH%:}
render(){  # template dest label
  local tmp rc=1 env=""; tmp=$(mktemp)
  # systemd expands %-specifiers inside unit files, so a literal % in PATH is written %%.
  local path=$UNIT_PATH; [ "$DROVER_SERVICES" = systemd ] && path=${path//%/%%}
  if [ -n "$PROJECT" ]; then
    case $DROVER_SERVICES in
      systemd) env="Environment=DROVER_PROJECT=$PROJECT" ;;
      launchd) env="    <key>DROVER_PROJECT</key><string>$PROJECT</string>" ;;
    esac
  fi
  sed -e "s|@BIN@|$(sed_esc "$BIN_DIR")|g" -e "s|@LOGS@|$(sed_esc "$HOME_DIR/logs")|g" \
      -e "s|@PATH@|$(sed_esc "$path")|g" -e "s|@LABEL@|$(sed_esc "$3")|g" \
      -e "/^ *@PROJECT_ENV@\$/{s|.*|$(sed_esc "$env")|; /^\$/d;}" "$1" > "$tmp"
  if [ -f "$2" ] && cmp -s "$tmp" "$2"; then :
  else echo "  render ${1#"$SRC"/} -> $2"; [ "$DRY" = 1 ] || cp "$tmp" "$2"; rc=0; fi
  rm -f "$tmp"; return $rc
}

case $DROVER_SERVICES in
launchd)
  say "launchd plists in $LA:"
  [ -d "$LA" ] || run mkdir -p "$LA"
  for job in $(jobs); do
    u=$(unit "$job"); p="$LA/$u.plist"
    render "$SRC/launchd/$job.plist.in" "$p" "$u" || true
    case $job in *lead-watchdog) [ "$WATCHDOG" = 1 ] || continue ;; esac
    if [ "$LOAD" = 1 ]; then
      launchctl print "gui/$(id -u)/$u" >/dev/null 2>&1 && run launchctl bootout "gui/$(id -u)/$u"
      run launchctl bootstrap "gui/$(id -u)" "$p"
    fi
  done ;;
systemd)
  say "systemd user units in $SD:"
  [ -d "$SD" ] || run mkdir -p "$SD"
  changed=0
  for t in "$SRC"/systemd/*.in; do
    f=$(basename "$t" .in); job=${f%.*}
    render "$t" "$SD/$(unit "$job").${f##*.}" "$(unit "$job")" && changed=1
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

[ -n "$(cfg_get "$CFG_FILE" DROVER_REPO 2>/dev/null)" ] || \
  say "NEXT: set DROVER_REPO in $CFG_FILE to your project checkout, then run: fleet up"
[ -z "$PROJECT" ] || say "Run fleet commands inside the project's checkout, or anywhere with DROVER_PROJECT=$PROJECT."
case ":$PATH:" in *":$BIN_DIR:"*) ;; *) say "NOTE: $BIN_DIR is not on your PATH." ;; esac
[ "$LOAD" = 1 ] || [ "$DROVER_SERVICES" = none ] || \
  say "Units are rendered but not started. Start them with: ./install.sh ${PROJECT:+--project $PROJECT }--load"
