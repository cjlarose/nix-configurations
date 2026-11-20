{ system, additionalPackages, stateVersion }:
{ pkgs, ... }:
{
  # The base profile every cjlarose host imports. The LLM-agent tooling is not
  # here: it lives in ./llm-agents.nix, which a host imports alongside this one
  # to opt in.
  imports = [
    ../../home-manager-modules/dev-tools.nix
    ../../home-manager-modules/neovim.nix
    ../../home-manager-modules/git.nix
    ../../home-manager-modules/shell.nix
  ];

  # gh from nixpkgs-unstable (2.96.0) rather than the host's 26-05 (2.93.0);
  # see packages/default.nix.
  cjlarose.devTools.ghPackage = additionalPackages.${system}.gh;

  # GitHub's official stacked-PR extension: `gh stack ...` and a gh-stack on
  # PATH. Useful at the keyboard, independent of any agent -- the SKILL.md that
  # ships in the same package is installed by ./llm-agents.nix where imported.
  cjlarose.devTools.ghStack = {
    enable = true;
    package = additionalPackages.${system}.gh-stack;
  };

  cjlarose.shell.nvrPackage = additionalPackages.${system}.nvr;
  cjlarose.shell.kubePrompt = true;
  cjlarose.shell.dockerPrompt = true;

  home.stateVersion = stateVersion;

  home.sessionVariables = {
    THOR_MERGE = "${pkgs.neovim-remote}/bin/nvr -s -d";
  };

  # Deliberately small. This profile fans out to every cjlarose host, so it
  # carries only things wanted everywhere; per-project toolchains belong in
  # devshells, and picktrace's toolchain lives in that repo's
  # home/modules/picktrace-dev-packages.nix.
  home.packages = [
    pkgs._1password-cli
    additionalPackages.${system}.git-make-apply-command
    pkgs.oha
    pkgs.parallel
    pkgs.socat
    additionalPackages.${system}.trueColorTest
  ];

  programs.git.userName = "Christopher La Rose";
  programs.git.userEmail = "cjlarose@gmail.com";
  # gh is configured with git_protocol = ssh (see dev-tools), but anything else
  # handing out an https github URL still gets rewritten here.
  programs.git.extraConfig = {
    "url \"ssh://git@github.com/\"".insteadOf = "https://github.com/";
  };

  programs.ssh = {
    matchBlocks = {
      "*.toothyshouse.com" = {
        forwardAgent = true;
      };
    };
  };
}
