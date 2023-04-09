{ nixpkgs, home-manager, fzfVim, fzfProject, pinpox, ... }: {
  "pt-dev" = (
    import ./pt-dev.nix { inherit nixpkgs home-manager fzfVim fzfProject pinpox; }
  );
}
