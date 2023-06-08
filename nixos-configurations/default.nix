{ nixpkgs, home-manager, fzfVim, fzfProject, tfenv, ... }: {
  "pt-dev" = (
    import ./pt-dev.nix { inherit nixpkgs home-manager fzfVim fzfProject tfenv; }
  );
  "photos" = (
    import ./photos.nix { inherit nixpkgs home-manager fzfVim fzfProject tfenv; }
  );
}
