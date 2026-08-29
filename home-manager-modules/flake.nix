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
      # LLM-agent tooling: the LLM wiki integration, opencode, herdr, git-surgeon,
      # tuicr and the gh-stack skill, plus the skill installs and the
      # herdr SessionStart hook wired onto programs.claude-code. Claude Code itself
      # is NOT owned here any more -- the consumer configures stock
      # programs.claude-code directly with harness-config's lib (see home/cjlarose).
      # The wiki integration is self-contained here (the read-only querying-notes
      # skill into ~/.claude/skills, plus LLM_WIKI_PATH, driven by
      # cjlarose.llmAgents.wiki.*), so the former `llm-agents-wiki` output (a
      # programs.llmWiki bridge paired with the wiki flake's own module) is gone.
      llm-agents = import ./llm-agents;
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
