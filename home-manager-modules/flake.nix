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
      # phx-workflow / lavish / opencode modules. The wiki integration is now
      # self-contained here (the read-only querying-notes skill into
      # ~/.claude/skills, plus LLM_WIKI_PATH, driven by cjlarose.llmAgents.wiki.*),
      # so the former `llm-agents-wiki` output (a programs.llmWiki bridge paired
      # with the wiki flake's own module) is gone.
      llm-agents = import ./llm-agents;
      # Pair with llm-agents ONLY where home-manager's claude-code module has a
      # `plugins` option -- 26.05 and later. It does not exist on 25-11, where
      # defining it is a hard error rather than a no-op.
      llm-agents-superpowers = import ./llm-agents/superpowers-plugin.nix;
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
