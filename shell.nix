# shell.nix: every binary drover runs. `nix-shell` gives them all; on NixOS install the same list in your user or
# system profile too, because the systemd units and herdr's panes do not run inside this shell (install.sh warns
# about any the units' PATH lacks).
#
# nixpkgs is pinned below; pass your own with `nix-shell --arg pkgs 'import <nixpkgs> {}'`. claude-code and
# cursor-cli are unfree; unfree packages are allowed for this shell only.
let
  pinned = fetchTarball {
    url = "https://github.com/NixOS/nixpkgs/archive/6510408d147d8c5e6d76043e899e9251756f6a75.tar.gz";
    sha256 = "sha256-XK4KceonkwD8LuMAt/vNrz982mXJM5jeHAxMwsUXXAQ=";
  };
in
{
  pkgs ? import pinned { config.allowUnfree = true; },
}:
pkgs.mkShell {
  packages =
    with pkgs;
    [
      # What the scripts shell out to. GNU tools are fine on macOS too: drover-env probes the flavour.
      bash
      coreutils # stat, date, df, cp, mktemp, sha256sum, timeout, ...
      diffutils # cmp
      findutils
      gawk
      gnugrep
      gnused
      gnutar # fleet-observe restores worktree snapshots
      git # 2.40+
      jq
      perl # shasum (fleet sync/rules, fleet-track), fleet-watch's alarm-bounded steps
      python3 # ten of the scripts, and inline helpers in the bash ones
      nodejs # node and npx: fleet-check-inline-jest-fanout, the build/test gates
      sqlite # sqlite3: opencode spend cap, ops/oc-compact.sh
      lsof # fleet-sweep and oc-compact refuse to act without it

      # What drover drives.
      herdr # hosts the seats: `herdr agent|pane|tab|notification`
      beans # the task board: `beans list --ready`, `beans show`

      # Harness CLIs of the default roster (DROVER_ROSTER: claude, codex, opencode).
      claude-code # claude
      codex
      opencode

      # Optional harnesses: uncomment the ones your roster names.
      # cursor-cli # cursor-agent (unfree)
      # grok-cli # grok
      # agy (the Antigravity CLI) is not in nixpkgs.

      # Optional: graphify-nightly is a no-op without it.
      # graphify

      # Working on drover itself.
      shellcheck
      nixfmt
    ]
    ++ lib.optionals stdenv.hostPlatform.isLinux [
      procps # ps, pgrep (macOS has its own)
      libnotify # notify-send: fleet-alert's desktop channel (macOS uses osascript)
      systemd # systemd-run: per-seat TasksMax ceiling; systemctl --user for the units
    ];
}
