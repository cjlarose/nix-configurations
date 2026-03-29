{ pkgs, nix-minecraft }:
let
  pkgsWithMinecraft = pkgs.extend nix-minecraft.overlays.default;
in
pkgsWithMinecraft.fetchPackwizModpack {
  src = ./.;
  side = "both";
  packHash = "sha256-GfozcwJIF9xs0IXeHi3h1ClTVSljqp/olzFFeqekhDA=";
}
