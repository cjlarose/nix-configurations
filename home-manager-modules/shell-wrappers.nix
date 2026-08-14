# Shell wrappers that are installed as packages in some places and by the
# dev-tools module in others.
#
# They live here, inside home-manager-modules, because that directory is its own
# flake: a module in it can import a sibling file but cannot reach up into
# packages/, while the root flake sees the whole tree and can reach down. So
# this is the one location both consumers can share, and sharing it is the
# point -- these are wrappers whose behaviour IS their definition, and two
# copies of one would drift apart silently.
#
# Takes pkgs rather than closing over one, so each consumer builds against its
# own: the dev-tools module gets the home's nixpkgs, packages/ gets the pin it
# names.
{ pkgs }:

{
  # jqp rather than jq: a second name, sitting alongside the real one instead of
  # shadowing it. Coloured and paged only when stdout is a terminal, so a
  # pipeline still receives plain json.
  wrappedJq = pkgs.writeShellScriptBin "jqp" ''
    if [ -t 1 ]; then
      ${pkgs.jq}/bin/jq --color-output "$@" | less
    else
      ${pkgs.jq}/bin/jq "$@"
    fi
  '';

  # rg, deliberately shadowing plain ripgrep: hidden files searched, .git
  # skipped, results ordered by path, paged when stdout is a terminal. Anything
  # wanting stock ripgrep behaviour installs pkgs.ripgrep instead of this.
  wrappedRg = pkgs.writeShellScriptBin "rg" ''
    if [ -t 1 ]; then
      ${pkgs.ripgrep}/bin/rg --hidden --glob '!.git' --sort path --pretty "$@" | less
    else
      ${pkgs.ripgrep}/bin/rg --hidden --glob '!.git' --sort path "$@"
    fi
  '';
}
