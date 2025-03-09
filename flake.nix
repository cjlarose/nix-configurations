{
  description = "NixOS-based development environment";

  inputs = {
    nixpkgs = {
      url = "github:nixos/nixpkgs/nixos-24.05";
    };
    nixpkgs-23-05 = {
      url = "github:nixos/nixpkgs/nixos-23.05";
    };
    nixpkgs-24-11 = {
      url = "github:nixos/nixpkgs/nixos-24.11";
    };
    darwin = {
      url = "github:lnl7/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager/release-24.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager-24-11 = {
      url = "github:nix-community/home-manager/release-24.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    fzfVim = {
      url = "github:cjlarose/fzf.vim";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    fzfProject = {
      url = "github:cjlarose/fzf-project";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    tfenv = {
      url = "github:cjlarose/tfenv-nix";
    };
    pce = {
      url = "git+ssh://git@github.com/cjlarose/pixel-cats-end-automation";
    };
    chicken-smoothie-automation = {
      url = "git+ssh://git@github.com/cjlarose/chicken-smoothie-automation";
    };
    impermanence = {
      url = "github:nix-community/impermanence";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    bundix = {
      url = "github:cjlarose/bundix";
      flake = false;
    };
    intranetHosts = {
      url = "git+ssh://git@github.com/cjlarose/intranet-hosts";
      flake = false;
    };
    omnisharpVim = {
      url = "github:OmniSharp/omnisharp-vim";
      flake = false;
    };
    trueColorTest = {
      url = "git+https://gist.github.com/db6c5654fa976be33808b8b33a6eb861.git";
      flake = false;
    };
    nvr = {
      url = "github:cstyles/nvr";
      flake = false;
    };
  };

  outputs = {
    bundix,
    darwin,
    disko,
    fzfProject,
    fzfVim,
    home-manager,
    home-manager-24-11,
    impermanence,
    intranetHosts,
    nixpkgs,
    nixpkgs-23-05,
    nixpkgs-24-11,
    omnisharpVim,
    pce,
    self,
    tfenv,
    trueColorTest,
    nvr,
    chicken-smoothie-automation,
  }:
    let
      supportedPlatforms = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ];

      additionalPackages = nixpkgs.lib.genAttrs supportedPlatforms (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in {
          atlas = nixpkgs-24-11.legacyPackages.${system}.atlas;
          chicken-smoothie-automation = chicken-smoothie-automation.packages.${system}.default;
          bundix = import "${bundix}/default.nix" { inherit pkgs; };
          intranetHosts = intranetHosts;
          git-make-apply-command = pkgs.writeShellScriptBin "git-make-apply-command" ''
            # This script is used to generate a command that can be used to apply a diff
            # The diff is passed to this script via stdin
            # The generated command is printed to stdout

            # Start the command
            printf '%b' 'printf %b $'"'"

            # Process input one byte at a time
            while IFS= read -r -d ''' -n1 char || [[ -n "$char" ]]; do
                # Get ASCII value
                LC_CTYPE=C printf -v ord "%d" "'$char"

                # Handle different character types
                if [[ "$char" == '\' ]]; then
                    # Escape backslashes
                    printf '%s' '\\\\'
                elif [[ "$ord" -ge 32 && "$ord" -le 126 ]] || [[ "$ord" -eq 10 ]]; then
                    # Printable characters are kept as-is
                    printf '%s' "$char"
                else
                    # Encode other characters as \xHH
                    printf '\\\\x%02x' "$ord"
                fi
            done

            # Close the command
            printf '%b' "'"' | git apply -\n'
          '';
          nix-direnv = nixpkgs-24-11.legacyPackages.${system}.nix-direnv;
          nvr = let
            manifest = (pkgs.lib.importTOML "${nvr.outPath}/Cargo.toml").package;
          in
            pkgs.rustPlatform.buildRustPackage {
              pname = manifest.name;
              version = manifest.version;
              cargoLock.lockFile = "${nvr.outPath}/Cargo.lock";
              src = pkgs.lib.cleanSource nvr.outPath;
            };
          python39 = nixpkgs-23-05.legacyPackages.${system}.python39;
          teleport_16 = nixpkgs-24-11.legacyPackages.${system}.teleport_16;
          trueColorTest = pkgs.stdenv.mkDerivation {
            name = "true-color-test";
            src = trueColorTest;
            buildPhase = ''
              chmod +x 24-bit-color.sh
            '';
            installPhase = ''
              mkdir -p $out/bin
              cp 24-bit-color.sh $out/bin
            '';
          };
          wrappedJq = pkgs.writeShellScriptBin "jq" ''
            if [ -t 1 ]; then
              ${pkgs.jq}/bin/jq --color-output "$@" | less
            else
              ${pkgs.jq}/bin/jq "$@"
            fi
          '';
          wrappedRg = pkgs.writeShellScriptBin "rg" ''
            if [ -t 1 ]; then
              ${pkgs.ripgrep}/bin/rg --pretty --sort path "$@" | less
            else
              ${pkgs.ripgrep}/bin/rg --sort path "$@"
            fi
          '';
          wrappedTailscale = pkgs.writeShellScriptBin "tailscale" ''
            exec /Applications/Tailscale.app/Contents/MacOS/Tailscale "$@"
          '';
          wrappedWireshark = pkgs.writeShellScriptBin "wireshark" ''
            exec /Applications/Wireshark.app/Contents/MacOS/Wireshark "$@"
          '';
        }
      );

      sharedOverlays = [
        fzfProject.overlay
        fzfVim.overlay
        tfenv.overlays.default
        (final: prev: {
          vimPlugins = prev.vimPlugins // {
            omnisharpVim = with final; vimUtils.buildVimPlugin {
              name = "omnisharp-vim";
              src = omnisharpVim;
            };
          };
        })
      ];
    in {
      nixosConfigurations = (
        import ./nixos-configurations {
          inherit nixpkgs nixpkgs-24-11 sharedOverlays additionalPackages home-manager home-manager-24-11 pce impermanence disko;
        }
      );

      darwinConfigurations = (
        import ./darwin-configurations {
          inherit nixpkgs nixpkgs-24-11 sharedOverlays additionalPackages darwin home-manager home-manager-24-11;
        }
      );

      diskoConfigurations = (
        import ./disko-configurations {}
      );

      packages = additionalPackages;
    };
}
