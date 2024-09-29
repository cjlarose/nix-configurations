{ system, pkgs, additionalPackages, stateVersion, configurationName, email, ... }: {
  imports = [
    ./personal-scripts.nix
    ./neovim.nix
  ];

  home.stateVersion = stateVersion;

  home.sessionPath = [
    "$HOME/.yarn/bin"
    "$HOME/Library/Android/sdk/platform-tools"
    "/Applications/Visual Studio Code.app/Contents/Resources/app/bin"
  ];

  home.sessionVariables = {
    EDITOR = "nvr-edit-in-split-window";
    LESS = "--quit-if-one-screen --RAW-CONTROL-CHARS --no-init";
    THOR_MERGE = "nvr -s -d";
  };

  home.packages = [
    pkgs.abduco
    pkgs.dig
    pkgs.docker-client
    pkgs.git-absorb
    pkgs.htop
    pkgs.jq
    pkgs.neovim-remote
    pkgs.nil
    pkgs.nodePackages.bash-language-server
    pkgs.nodePackages.pyright
    pkgs.nodePackages.typescript-language-server
    pkgs.nodePackages.vscode-langservers-extracted
    pkgs.nodejs_20
    pkgs.omnisharp-roslyn
    pkgs.parallel
    pkgs.ripgrep
    pkgs.ruby
    pkgs.shellcheck
    pkgs.tmux
    pkgs.tree
    pkgs.unixtools.watch
    pkgs.wget
    pkgs.wrk
    pkgs.yarn
  ];

  home.shellAliases = {
    gs = "git status";
    defaultnix = "$EDITOR ~/workspace/cjlarose/nixos-dev-env/home/monicahung/default.nix";
    rebuild = "darwin-rebuild switch --flake '.#${configurationName}'";
    rmswp = "find . -type f -name \".*.swp\" -exec rm -f {} \;";
    git-branch-date2 = "git branch --sort=-committerdate | tail -r | tail -10";
    git-branch-date = "git branch --sort=committerdate | tail -10";
    gbd = "git branch -D";
    gpoh = "git push -u origin HEAD";
    gd = "git diff";
    grbc = "git rebase --continue";
    gc = "git commit -m";
    gcp = "git cherry-pick";
    gdn = "git diff --name-only";
  };

  programs.zsh = {
    enable = true;
    envExtra = ''
      export GIT_PACKAGE_DIR=${pkgs.git}
    '';
    initExtra = builtins.readFile ./.zshrc;
  };

  programs.git = {
    enable = true;
    userName = "Monica Hung";
    userEmail = email;
    extraConfig = {
      color.ui = true;
      commit.verbose = true;
      pull.ff = "only";
      rebase.autosquash = true;
    };
    ignores = [
      "[._]*.s[a-w][a-z]"
      "[._]s[a-w][a-z]"
    ];
  };

  programs.ssh = {
    enable = true;
    extraOptionOverrides = {
      AddKeysToAgent = "yes";
    };
    extraConfig = "IdentityAgent \"~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock\"";
  };

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
  };
}
