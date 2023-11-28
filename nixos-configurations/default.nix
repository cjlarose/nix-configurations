{ nixpkgs, home-manager, fzfVim, fzfProject, tfenv, nixos-generators, ... }: {
  "builder" = (
    import ./builder.nix { inherit nixpkgs home-manager fzfVim fzfProject tfenv nixos-generators; }
  );
  "pt-dev" = (
    import ./pt-dev.nix { inherit nixpkgs home-manager fzfVim fzfProject tfenv; }
  );
  "photos" = (
    import ./photos.nix { inherit nixpkgs home-manager fzfVim fzfProject tfenv; }
  );
}
