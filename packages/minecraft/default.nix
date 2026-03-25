{ pkgs, nix-minecraft }:
let
  pkgsWithMinecraft = pkgs.extend nix-minecraft.overlays.default;
in
pkgsWithMinecraft.fetchPackwizModpack {
  src = ./.;
  packHash = "sha256-Rdg6q7RVZGpWhGkOgvkDfR/n5IC0EIefv2HH3xGJgtg=";
}
