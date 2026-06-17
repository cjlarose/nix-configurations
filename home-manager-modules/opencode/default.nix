{ additionalPackages, system, ... }:

{
  programs.opencode = {
    enable = true;
    package = additionalPackages.${system}.opencode;
  };
}
