{ system, pkgs, additionalPackages, stateVersion, includeCopilotVim, configurationName, email, yarnOverride, ... }: {
  imports = let
    baseImports = [
      ./personal-scripts.nix
      ./neovim.nix
    ];
  in baseImports ++ (if includeCopilotVim then [./copilot-vim.nix] else []);

  home.stateVersion = stateVersion;

  home.sessionPath = [
    "$HOME/.yarn/bin"
    "$HOME/.config/yarn/global/node_modules/.bin"
    "$HOME/go/bin"
    "$HOME/Library/Android/sdk/platform-tools"
    "/Applications/Visual Studio Code.app/Contents/Resources/app/bin"
  ];

  home.sessionVariables = {
    EDITOR = "nvr-edit-in-split-window";
    LESS = "--quit-if-one-screen --RAW-CONTROL-CHARS --no-init";
    THOR_MERGE = "nvr -s -d";
    GOPATH = "$HOME/go";
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
    pkgs.gnupg
    pkgs._1password
  ];

  home.shellAliases = let
    standardAliases = {
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
      cdb5 = "cd ~/go/src/go.1password.io/b5";
    };
    yarnAliases = (if yarnOverride then {yarn="op run --account agilebits --no-masking -- yarn";} else {});
  in standardAliases // yarnAliases;


  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
    nix-direnv = {
      enable = true;
      package = additionalPackages.${system}.nix-direnv;
    };
  };

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
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
      "url \"ssh://git@ssh.gitlab.1password.io:2227\"".insteadOf = "https://gitlab.1password.io";
      gpg.format = "ssh";
      "gpg \"ssh\"" = {
        program = "/Applications/1Password.app/Contents/MacOS/op-ssh-sign";
      };
    };
    ignores = [
      "[._]*.s[a-w][a-z]"
      "[._]s[a-w][a-z]"
    ];
    signing = {
      key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE4ftRm9tJtFBks5PtRi+gf7yFMhjaZ3zxGHd/B/tcBb";
      signByDefault = true;
    };
  };

  programs.go = {
    enable = true;
    package = pkgs.go_1_22;
  };

  programs.ssh = {
    enable = true;
    extraOptionOverrides = {
      AddKeysToAgent = "yes";
    };
    extraConfig = "IdentityAgent \"~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock\"";
    matchBlocks = {
      "gitlab gitlab.1password.io ssh.gitlab.1password.io" = {
        hostname = "ssh.gitlab.1password.io";
        port = 2227;
      };
    };
  };

  programs.zsh = {
    enable = true;
    envExtra = ''
      export GIT_PACKAGE_DIR=${pkgs.git}
    '';
    initExtra = builtins.readFile ./.zshrc;
  };
}
