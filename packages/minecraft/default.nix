{ pkgs, nix-minecraft }:
let
  pkgsWithMinecraft = pkgs.extend nix-minecraft.overlays.default;
in
pkgsWithMinecraft.fetchPackwizModpack {
  src = ./.;
  side = "both";
  packHash = "sha256-it8xUXsDiLB7Qov+l5qnL6CWw8R/mBG9WrOTz4bTOmY=";
}
