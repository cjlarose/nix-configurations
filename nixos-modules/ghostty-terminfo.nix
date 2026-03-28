{ pkgs, additionalPackages, ... }:

{
  # Install the xterm-ghostty terminfo entry on all hosts so that programs
  # looking up terminal capabilities by $TERM can find it. Without this,
  # TERM=xterm-ghostty arrives via the SSH pty-req but the terminfo database
  # has no matching entry.
  environment.systemPackages = [ additionalPackages.${pkgs.system}.ghostty-terminfo ];
}
