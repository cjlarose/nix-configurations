{ home-manager, stateVersion, additionalPackages, system, impermanence, disko, self, ... }:
let
  flakeInputs = builtins.attrValues (builtins.removeAttrs self.inputs [ "self" ]);
in {
  imports = [
    {
      system.extraDependencies = flakeInputs;
    }
    (import ./disk-config.nix { inherit disko; })
    ({ pkgs, ... }: {
      imports = [
        impermanence.nixosModules.impermanence
      ];
      environment.persistence."/persistence" = {
        hideMounts = true;
        directories = [
          {
            directory = "/etc/nixos";
          }
        ];
      };
    })
    ./configuration.nix
    home-manager.nixosModules.home-manager
    {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.users.cjlarose = (import ../../home/cjlarose) {
        inherit system stateVersion additionalPackages;
        claudeUseNodeRuntime = true;
      };
    }
  ];
}
