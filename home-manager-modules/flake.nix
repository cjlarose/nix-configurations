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
      # Unified LLM-agent tooling: Claude Code, lavish-axi, the LLM wiki
      # integration, opencode and herdr. Replaces the former separate claude /
      # phx-workflow / lavish / opencode modules.
      llm-agents = import ./llm-agents;
      # Pair with llm-agents ONLY where the LLM wiki flake's own module is also
      # imported -- it defines programs.llmWiki, which that module declares.
      llm-agents-wiki = import ./llm-agents/wiki-bridge.nix;
      coder = import ./coder.nix;
      direnv = import ./direnv.nix;
      ghostty = import ./ghostty.nix;
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
        ./ghostty.nix
      ]; };
    };
  };
}
