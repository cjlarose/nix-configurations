{ pkgs, nix-minecraft }:
let
  pkgsWithMinecraft = pkgs.extend nix-minecraft.overlays.default;
in
pkgsWithMinecraft.fetchPackwizModpack {
  src = ./modpack;
  side = "both";
  packHash = "sha256-W1lDd8Y1LIbWwTzf3lnHx/HsqWa3waVmCx2M16C9IxE=";
}
