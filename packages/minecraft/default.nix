{ pkgs, nix-minecraft }:
let
  pkgsWithMinecraft = pkgs.extend nix-minecraft.overlays.default;
in
pkgsWithMinecraft.fetchPackwizModpack {
  src = ./modpack;
  side = "both";
  packHash = "sha256-PSI169kONxed7ASQjRbnTOsP4p80Vr3oro1zndGGnh4=";
}
