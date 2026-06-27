{
  nixpkgs-25-11,
  nixpkgs-26-05,
  sharedOverlays,
  additionalPackages,
  home-manager-25-11,
  home-manager-26-05,
  pce,
  impermanence,
  disko,
  determinate,
  nix-minecraft,
  mattpocock-skills,
  microvm,
  hermes-agent,
  picktrace-nix-configurations,
  cjlarose-llm-wiki,
  cjlarose-home-manager-modules,
  self,
  ...
}:
let
  ghosttyTerminfoModule = import ../nixos-modules/ghostty-terminfo.nix;
  allowUnfreeModule = import ../nixos-modules/allow-unfree.nix;
  hosts = {
    "bots" = nixpkgs-26-05.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit sharedOverlays additionalPackages pce impermanence disko;
        nixpkgs = nixpkgs-26-05;
        home-manager = home-manager-26-05;
        stateVersion = "23.11";
        system = "x86_64-linux";
      };
      modules = [ ./bots ];
    };
    "cache" = nixpkgs-26-05.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit sharedOverlays additionalPackages impermanence disko;
        nixpkgs = nixpkgs-26-05;
        home-manager = home-manager-26-05;
        stateVersion = "24.05";
        system = "x86_64-linux";
      };
      modules = [ ./cache ];
    };
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
    "dns" = nixpkgs-26-05.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit sharedOverlays additionalPackages impermanence disko self;
        nixpkgs = nixpkgs-26-05;
        home-manager = home-manager-26-05;
        stateVersion = "23.11";
        system = "x86_64-linux";
      };
      modules = [ ./dns ];
    };
    "immich" = nixpkgs-25-11.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit sharedOverlays additionalPackages impermanence disko;
        nixpkgs = nixpkgs-25-11;
        home-manager = home-manager-25-11;
        stateVersion = "24.11";
        system = "x86_64-linux";
      };
      modules = [ ./immich ];
    };
    "media" = nixpkgs-26-05.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit sharedOverlays additionalPackages microvm;
        home-manager = home-manager-26-05;
        stateVersion = "25.11";
        system = "x86_64-linux";
      };
      modules = [ ./media ];
    };
    "hermes" = nixpkgs-26-05.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit sharedOverlays additionalPackages microvm hermes-agent;
        home-manager = home-manager-26-05;
        stateVersion = "25.11";
        system = "x86_64-linux";
      };
      modules = [ ./hermes ];
    };
    "splitpro" = nixpkgs-26-05.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit sharedOverlays additionalPackages impermanence disko;
        nixpkgs = nixpkgs-26-05;
        home-manager = home-manager-26-05;
        stateVersion = "24.11";
        system = "x86_64-linux";
      };
      modules = [ ./splitpro ];
    };
    "ns1010301" = nixpkgs-26-05.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit sharedOverlays additionalPackages impermanence disko determinate nix-minecraft microvm picktrace-nix-configurations cjlarose-llm-wiki cjlarose-home-manager-modules mattpocock-skills self;
        nixpkgs = nixpkgs-26-05;
        home-manager = home-manager-26-05;
        stateVersion = "25.11";
        system = "x86_64-linux";
      };
      modules = [ ./ns1010301 ];
    };
    "minecraft-mellowcatfe" = nixpkgs-26-05.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit sharedOverlays additionalPackages nix-minecraft microvm;
        home-manager = home-manager-26-05;
        stateVersion = "25.11";
        system = "x86_64-linux";
      };
      modules = [ ./minecraft-mellowcatfe ];
    };
  };
in
  builtins.mapAttrs (_: host: host.extendModules {
    modules = [ ghosttyTerminfoModule allowUnfreeModule ];
    specialArgs = { inherit additionalPackages; };
  }) hosts
