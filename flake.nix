{
  description = "NixOS-based development environment";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/release-22.05";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    fzfVim.url = "github:cjlarose/fzf.vim";
    fzfVim.inputs.nixpkgs.follows = "nixpkgs";
    fzfProject.url = "github:cjlarose/fzf-project";
    fzfProject.inputs.nixpkgs.follows = "nixpkgs";
    pinpox.url = "github:pinpox/nixos";
    pinpox.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, home-manager, fzfVim, fzfProject, pinpox }: {
    nixosConfigurations.dev = nixpkgs.lib.nixosSystem (
      let
        system = "x86_64-linux";
      in {
        inherit system;
        modules = [
          ({ pkgs, ... }: {
            imports = [ ./hardware-configuration.nix ];

            networking.hostName = "pt-dev";

            boot.loader.systemd-boot.enable = true;
            boot.loader.efi.canTouchEfiVariables = true;

            system.stateVersion = "22.05";

            networking.firewall.allowedTCPPorts = [
              80 # ingress-nginx
              443 # ingress-nginx
              3000 # web-client
              6443 # k8s API
              10250 # k8s node API
            ];

            nix = {
              package = pkgs.nixFlakes;
              extraOptions = ''
                experimental-features = nix-command flakes
              '';
              registry.nixpkgs.flake = nixpkgs;
            };

            nixpkgs.overlays = [
              fzfVim.overlay
              fzfProject.overlay
            ];

            security.sudo.wheelNeedsPassword = false;
            security.pam.loginLimits = [
              {
                domain = "*";
                type = "soft";
                item = "nofile";
                value = "65536";
              }
            ];

            virtualisation.docker.enable = true;

            environment.systemPackages = with pkgs; [
              lsof
            ];

            services.openssh = {
              enable = true;
              passwordAuthentication = false;
              permitRootLogin = "no";
            };

            programs.ssh.startAgent = true;

            programs.zsh.enable = true;

            services.avahi = {
              enable = true;
              publish = {
                enable = true;
                addresses = true;
              };
            };

            services.postgresql = {
              enable = true;
              authentication = ''
                # Allow any user on the local system to connect to any database with
                # any database user name using Unix-domain sockets (the default for local
                # connections).
                #
                # TYPE  DATABASE        USER            ADDRESS                 METHOD
                local   all             all                                     trust

                # Require password authentication when accessing 127.0.0.1
                #
                # TYPE  DATABASE        USER            ADDRESS                 METHOD
                host    all             all             127.0.0.1/32            scram-sha-256

                # The same over IPv6.
                #
                # TYPE  DATABASE        USER            ADDRESS                 METHOD
                host    all             all             ::1/128                 scram-sha-256
              '';
            };

            services.k3s = {
              enable = true;
              role = "server";
              extraFlags = toString [
                "--disable traefik"
                "--disable servicelb"
              ];
            };

            services.dockerRegistry = {
              enable = true;
            };

            users.mutableUsers = false;

            users.users.cjlarose = {
              isNormalUser = true;
              home = "/home/cjlarose";
              extraGroups = [ "docker" "wheel" ];
              shell = pkgs.zsh;
              hashedPassword = "$6$YLrfXTwu61JGE.v8$kR5ZdMso2lcnyy7s7GXkIb.kLDyQ2UW3aDyGerQYni96g2kPC1MIY48Y9Q3SdYe2ycuVCrKgH6DlOjUUsK02s0";
              openssh.authorizedKeys.keys = [
                "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGFtA/9w60OssA+Eji+Ygvd1XCJk/zw/uYLdiiaevELu cjlarose"
              ];
            };
          })
          home-manager.nixosModules.home-manager {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.cjlarose = import ./home.nix;
            home-manager.extraSpecialArgs = {
              inherit system pinpox;
            };
          }
        ];
      }
    );
  };
}
