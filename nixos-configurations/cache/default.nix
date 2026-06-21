{ nixpkgs, sharedOverlays, additionalPackages, home-manager, stateVersion, impermanence, ... }:
let
  system = "x86_64-linux";
in nixpkgs.lib.nixosSystem {
  inherit system;
  modules = [
    ({ pkgs, lib, ... }: {
      boot = {
        loader.systemd-boot.enable = true;
        zfs.devNodes = "/dev/disk/by-label/tank";
        # Roll the root dataset back to a pristine snapshot on every boot
        # (impermanence). Under 26.05's systemd stage-1 initrd this is a
        # oneshot service ordered after the pool import and before the root
        # mount; the scripted-initrd `boot.initrd.postDeviceCommands` form is
        # not supported by systemd initrd.
        initrd.systemd.services.rollback-root = {
          description = "Roll back tank/root to its blank snapshot";
          wantedBy = [ "initrd.target" ];
          after = [ "zfs-import-tank.service" ];
          before = [ "sysroot.mount" ];
          unitConfig.DefaultDependencies = "no";
          serviceConfig.Type = "oneshot";
          path = [ pkgs.zfs ];
          script = ''
            zfs rollback -r tank/root@blank
          '';
        };
      };
    })
    (import ./configuration.nix { inherit nixpkgs sharedOverlays stateVersion system; })
    ({ pkgs, ... } : {
      imports = [
        impermanence.nixosModules.impermanence
      ];
      environment.persistence."/persistence" = {
        hideMounts = true;
        directories = [
          {
            directory = "/etc/nixos";
          }
          {
            directory = "/var/lib/acme";
            user = "acme";
            group = "acme";
            mode = "0755";
          }
          {
            # Persist the tailscale node identity across the impermanence
            # @blank rollback; without this every reboot drops the host off
            # the tailnet and requires a re-auth from the console. Every other
            # impermanence host in this repo persists this.
            directory = "/var/lib/tailscale";
            user = "root";
            group = "root";
            mode = "0700";
          }
        ];
        users = {
          cjlarose = {
            directories = [
              ".ssh"
              "gc-roots"
              "workspace"
            ];
          };
        };
      };
    })
    home-manager.nixosModules.home-manager {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.users.cjlarose = (import ../../home/cjlarose) {
        inherit system stateVersion additionalPackages;
      };
    }
  ];
}
