{
  description = "NixOS-based development environment";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/release-22.05";
    darwin.url = "github:lnl7/nix-darwin/master";
    darwin.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    fzfVim.url = "github:cjlarose/fzf.vim";
    fzfVim.inputs.nixpkgs.follows = "nixpkgs";
    fzfProject.url = "github:cjlarose/fzf-project";
    fzfProject.inputs.nixpkgs.follows = "nixpkgs";
    pinpox.url = "github:cjlarose/pinpox-nixos";
    pinpox.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, darwin, home-manager, fzfVim, fzfProject, pinpox }: {
    nixosConfigurations."router" = nixpkgs.lib.nixosSystem (
      let
        system = "x86_64-linux";
      in {
        inherit system;
        modules = [
          ({ pkgs, ... }: {
            imports = [ ./hardware-configuration-router.nix ];

            networking.hostName = "router";

            boot.loader.systemd-boot.enable = true;
            boot.loader.efi.canTouchEfiVariables = true;

            system.stateVersion = "22.05";

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

            environment.systemPackages = with pkgs; [
              lsof
              iotop
            ];

            services.openssh = {
              enable = true;
              passwordAuthentication = false;
              permitRootLogin = "no";
            };

            programs.ssh.startAgent = true;

            programs.zsh.enable = true;

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
              server = true;
            };
          }
        ];
      }
    );

    nixosConfigurations."pt-dev" = nixpkgs.lib.nixosSystem (
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
              2376 # docker daemon
              3000 # web-client
              5432 # postgresql
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

            virtualisation.docker = {
              enable = true;
              listenOptions = [
                "/run/docker.sock"
                "0.0.0.0:2376"
              ];
            };

            environment.systemPackages = with pkgs; [
              lsof
              iotop
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
              enableTCPIP = true;
              authentication = ''
                # Allow any user on the local system to connect to any database with
                # any database user name using Unix-domain sockets (the default for local
                # connections).
                #
                # TYPE  DATABASE        USER            ADDRESS                 METHOD
                local   all             all                                     trust

                # Require password authentication when accessing over TCP/IP, all addresses
                #
                # TYPE  DATABASE        USER            ADDRESS                 METHOD
                host    all             all             0.0.0.0/0               scram-sha-256
              '';
              extraPlugins = with pkgs.postgresql14Packages; [ postgis ];
              dataDir = "/pt-postgresql";
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

            services.openiscsi = {
              enable = true;
              name = "iqn.2020-08.org.linux-iscsi.toothyshouse:pt-dev";
              enableAutoLoginOut = true;
              discoverPortal = "montero.toothyshouse.com";
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
              server = true;
            };
          }
        ];
      }
    );

    darwinConfigurations."LaRose-MacBook-Pro" = darwin.lib.darwinSystem (
      let
        system = "x86_64-darwin";
      in {
        inherit system;
        modules = [
          ({ pkgs, ... }: {
            environment.systemPackages = [
              pkgs.vim
            ];
            services.nix-daemon.enable = true;
            programs.zsh.enable = true;
            system.stateVersion = 4;
            nixpkgs.overlays = [
              fzfVim.overlay
              fzfProject.overlay
            ];
          })
          home-manager.darwinModules.home-manager {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.chrislarose = import ./home.nix;
            home-manager.extraSpecialArgs = {
              inherit system pinpox;
              server = false;
            };
          }
        ];
      }
    );
  };
}
