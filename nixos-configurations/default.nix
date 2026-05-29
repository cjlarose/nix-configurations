{
  nixpkgs-24-05,
  nixpkgs-24-11,
  nixpkgs-25-05,
  nixpkgs-25-11,
  sharedOverlays,
  additionalPackages,
  home-manager-24-05,
  home-manager-24-11,
  home-manager-25-05,
  home-manager-25-11,
  pce,
  impermanence,
  disko,
  determinate,
  nix-minecraft,
  mattpocock-skills,
  microvm,
  picktrace-nix-configurations,
  cjlarose-home-manager-modules,
  self,
  ...
}:
let
  ghosttyTerminfoModule = import ../nixos-modules/ghostty-terminfo.nix;
  hosts = {
    "builder" = (
      import ./builder {
        inherit sharedOverlays additionalPackages;
        nixpkgs = nixpkgs-24-05;
        home-manager = home-manager-24-05;
        stateVersion = "23.05";
      }
    );
    "bootstrap" = (
      import ./bootstrap {
        inherit sharedOverlays disko impermanence;
        nixpkgs = nixpkgs-24-11;
        stateVersion = "24.11";
      }
    );
    "bots" = (
      import ./bots {
        inherit sharedOverlays additionalPackages pce impermanence disko;
        nixpkgs = nixpkgs-25-11;
        home-manager = home-manager-25-11;
        stateVersion = "23.11";
      }
    );
    "cache" = (
      import ./cache {
        inherit sharedOverlays additionalPackages impermanence;
        nixpkgs = nixpkgs-25-05;
        home-manager = home-manager-25-05;
        stateVersion = "24.05";
      }
    );
    "coder" = (
      import ./coder {
        inherit sharedOverlays additionalPackages impermanence;
        nixpkgs = nixpkgs-24-05;
        home-manager = home-manager-24-05;
        stateVersion = "24.05";
      }
    );
    "edge-lax" = nixpkgs-25-11.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit sharedOverlays additionalPackages impermanence disko;
        nixpkgs = nixpkgs-25-11;
        home-manager = home-manager-25-11;
        stateVersion = "25.11";
        system = "x86_64-linux";
        intranetHosts = additionalPackages."x86_64-linux".intranetHosts;
      };
      modules = [ ./edge-lax ];
    };
    "dns" = (
      import ./dns {
        inherit sharedOverlays additionalPackages impermanence disko self;
        nixpkgs = nixpkgs-25-11;
        home-manager = home-manager-25-11;
        stateVersion = "23.11";
      }
    );
    "immich" = (
      import ./immich {
        inherit sharedOverlays additionalPackages impermanence disko;
        nixpkgs = nixpkgs-25-05;
        home-manager = home-manager-25-05;
        stateVersion = "24.11";
      }
    );
    "media" = nixpkgs-25-11.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit sharedOverlays additionalPackages microvm;
        home-manager = home-manager-25-11;
        stateVersion = "25.11";
        system = "x86_64-linux";
      };
      modules = [ ./media ];
    };
    "memos" = (
      import ./memos {
        inherit sharedOverlays additionalPackages impermanence disko;
        nixpkgs = nixpkgs-25-05;
        home-manager = home-manager-25-05;
        stateVersion = "25.05";
      }
    );
    "palworld" = (
      import ./palworld {
        inherit sharedOverlays additionalPackages;
        nixpkgs = nixpkgs-24-05;
        home-manager = home-manager-24-05;
        stateVersion = "23.11";
      }
    );
    "photos" = (
      import ./photos.nix {
        inherit sharedOverlays additionalPackages;
        nixpkgs = nixpkgs-24-05;
        home-manager = home-manager-24-05;
        stateVersion = "23.05";
      }
    );
    "splitpro" = (
      import ./splitpro {
        inherit sharedOverlays additionalPackages impermanence;
        nixpkgs = nixpkgs-25-05;
        home-manager = home-manager-25-05;
        stateVersion = "24.11";
      }
    );
    "unifi" = (
      import ./unifi {
        inherit sharedOverlays additionalPackages impermanence;
        nixpkgs = nixpkgs-24-11;
        home-manager = home-manager-24-11;
        stateVersion = "24.11";
      }
    );
    "ns1010301" = (
      import ./ns1010301 {
        inherit sharedOverlays additionalPackages impermanence disko determinate nix-minecraft microvm picktrace-nix-configurations cjlarose-home-manager-modules mattpocock-skills self;
        nixpkgs = nixpkgs-25-11;
        home-manager = home-manager-25-11;
        stateVersion = "25.11";
      }
    );
    "minecraft-mellowcatfe" = nixpkgs-25-11.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit sharedOverlays additionalPackages nix-minecraft microvm;
        home-manager = home-manager-25-11;
        stateVersion = "25.11";
        system = "x86_64-linux";
      };
      modules = [ ./minecraft-mellowcatfe ];
    };
  };
in
  builtins.mapAttrs (_: host: host.extendModules {
    modules = [ ghosttyTerminfoModule ];
    specialArgs = { inherit additionalPackages; };
  }) hosts
