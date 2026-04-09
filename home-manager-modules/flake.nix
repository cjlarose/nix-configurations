{
  description = "Shared home-manager modules";

  outputs = { self }: {
    homeManagerModules = {
      neovim = import ./neovim.nix;
      git = import ./git.nix;
      shell = import ./shell.nix;
      dev-tools = import ./dev-tools.nix;
      karabiner = import ./karabiner.nix;
      _1password = import ./_1password.nix;
      coder = import ./coder.nix;
      direnv = import ./direnv.nix;
      default = { imports = [
        ./neovim.nix
        ./git.nix
        ./shell.nix
        ./dev-tools.nix
        ./direnv.nix
      ]; };
      darwinDefault = { imports = [
        ./karabiner.nix
        ./_1password.nix
      ]; };
    };
  };
}
