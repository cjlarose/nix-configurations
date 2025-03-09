{ pkgs, ... }:

let
  gitMakeApplyCommand = pkgs.writeShellScriptBin "git-make-apply-command" ''
    # This script is used to generate a command that can be used to apply a diff
    # The diff is passed to this script via stdin
    # The generated command is printed to stdout

    # Start the command
    printf '%b' 'printf %b $'"'"

    # Process input one byte at a time
    while IFS= read -r -d ''' -n1 char || [[ -n "$char" ]]; do
        # Get ASCII value
        LC_CTYPE=C printf -v ord "%d" "'$char"

        # Handle different character types
        if [[ "$char" == '\' ]]; then
            # Escape backslashes
            printf '%s' '\\\\'
        elif [[ "$ord" -ge 32 && "$ord" -le 126 ]] || [[ "$ord" -eq 10 ]]; then
            # Printable characters are kept as-is
            printf '%s' "$char"
        else
            # Encode other characters as \xHH
            printf '\\\\x%02x' "$ord"
        fi
    done

    # Close the command
    printf '%b' "'"' | git apply -\n'
  '';

  runUntilFailure = pkgs.writeShellScriptBin "run-until-failure" ''
    while "$@"; do :; done
  '';

  runUntilSuccess = pkgs.writeShellScriptBin "run-until-success" ''
    while ! "$@"; do :; done
  '';
in {
  home.packages = [
    gitMakeApplyCommand
    runUntilFailure
    runUntilSuccess
  ];
}
