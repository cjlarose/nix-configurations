{ pkgs, config, lib, sharedOverlays, stateVersion, system, additionalPackages, home-manager, intranetHosts, ... }:

let
  # Hermes config rendered to config.yaml. Defined here so the same value feeds
  # both `services.hermes-agent.settings` and the ExecStartPre that re-materializes
  # config.yaml at service start (see the systemd block below for why).
  hermesSettings = {
    model.default = "anthropic/claude-opus-4-8";
    toolsets = [ "all" ];
    terminal.backend = "local";
    # One shared transcript per channel (not per-user), so the agent sees
    # every participant's messages in a channel as common context.
    group_sessions_per_user = false;
    # Reply inline in the channel instead of spawning a thread per message.
    discord.auto_thread = false;
  };
  hermesConfigYaml = (pkgs.formats.yaml { }).generate "hermes-config.yaml" hermesSettings;

  # The agent's terminal tool runs in a sandboxed shell that does NOT inherit
  # GITHUB_TOKEN, so gh/git are unauthenticated there. Authenticate gh
  # persistently from the token at service start (writes ~/.config/gh on the
  # persistent /var/lib/hermes share) and wire it into git's credential helper,
  # so the agent can clone/push in its terminal without the token in its env.
  ghAuthScript = pkgs.writeShellScript "hermes-gh-auth" ''
    set -euo pipefail
    export PATH=${lib.makeBinPath [ pkgs.gh pkgs.git pkgs.gnugrep pkgs.coreutils ]}:$PATH
    umask 077
    # Extract the token WITHOUT exporting it: gh refuses to persist credentials
    # (writes nothing to ~/.config/gh) when GITHUB_TOKEN is present in the env.
    # We want it stored so the agent's sandboxed terminal — which has no
    # GITHUB_TOKEN — is authenticated via the config file + git credential helper.
    token=$(grep -m1 '^GITHUB_TOKEN=' /var/lib/hermes/.hermes/.env | cut -d= -f2- || true)
    [ -n "$token" ] || { echo "no GITHUB_TOKEN in .env; skipping gh auth"; exit 0; }
    printf %s "$token" | gh auth login --with-token
    gh auth setup-git
  '';
in
{

  imports = [
    home-manager.nixosModules.home-manager
  ];

  networking = {
    hostName = "hermes";
    useNetworkd = true;
    # Resolve the fleet's *.cjlarose.dev FQDNs to their tailnet IPs locally (same
    # pattern as edge-lax), so Hermes can SSH-deploy targets by name over Tailscale
    # without depending on tailnet split-DNS for cjlarose.dev.
    extraHosts = builtins.readFile "${intranetHosts}/hosts";
    firewall.enable = true;
    # Static file server (nginx) is reachable only over the tailnet — open 443
    # on tailscale0 only, never on the microvm bridge or any public path.
    firewall.interfaces.tailscale0.allowedTCPPorts = [ 443 ];
  };

  systemd.network.enable = true;

  systemd.network.networks."20-lan" = {
    matchConfig.MACAddress = "02:00:00:00:00:04";
    networkConfig = {
      Address = [ "10.0.0.5/24" ];
      Gateway = "10.0.0.1";
      DNS = [ "1.1.1.1" ];
    };
  };

  time.timeZone = "America/Los_Angeles";

  system.stateVersion = stateVersion;

  nixpkgs.overlays = sharedOverlays;

  # Give the agent a modern nix toolchain in its terminal: nix-command + flakes
  # enable `nix shell nixpkgs#…`, `nix flake`, `nix build`, and `nix profile`
  # (which is otherwise disabled), so the agent can self-serve tooling instead
  # of relying solely on declarative extraPackages.
  nix.extraOptions = ''
    experimental-features = nix-command flakes
  '';

  security.sudo.wheelNeedsPassword = false;

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
    hostKeys = [
      {
        path = "/persistence/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
      {
        path = "/persistence/ssh/ssh_host_rsa_key";
        type = "rsa";
        bits = 4096;
      }
    ];
  };

  services.tailscale = {
    enable = true;
    openFirewall = true;
    port = 41645;
  };

  # Static file server for bingy.mellowcatfe.com. Serves generated HTML out of
  # /var/www (a dedicated persistent virtiofs share, tank/microvms/hermes/www)
  # over the tailnet only. The webroot is a *separate* share from the agent's
  # home (/var/lib/hermes, mode 0770) specifically so nginx (uid 60) can traverse
  # and read it without loosening the agent's home or its secrets. The dir is
  # owned hermes:nginx mode 2750 (setgid): the agent (hermes) writes generated
  # pages as owner; nginx reads them via the nginx group.
  #
  # Public DNS (DigitalOcean A record) points bingy.mellowcatfe.com at this
  # guest's *tailnet* IP (100.66.120.5), not ns1010301's public IP — so the site
  # is reachable only by tailnet members (owner + anyone the node is shared with),
  # the same "auth = tailnet reachability" model as jellyfin.cjlarose.dev. There is
  # no app-layer auth.
  #
  # TLS: DNS-01 ACME (not HTTP-01) is mandatory here — a 100.x CGNAT address is not
  # reachable from Let's Encrypt's HTTP validators, so only the DNS challenge can
  # succeed. Reuses the fleet's DigitalOcean token (full-zone scope, also used by
  # media/splitpro). Same idiom as splitpro's certs.
  security.acme = {
    acceptTerms = true;
    defaults.email = "cjlarose@gmail.com";
    certs."bingy.mellowcatfe.com" = {
      dnsPropagationCheck = false;
      dnsProvider = "digitalocean";
      dnsResolver = "1.1.1.1:53";
      domain = "bingy.mellowcatfe.com";
      environmentFile = "/persistence/secrets/digitalocean.secret";
    };
  };

  services.nginx = {
    enable = true;
    virtualHosts."bingy.mellowcatfe.com" = {
      # Bind only to the tailnet IP so the static root is unreachable over the
      # microvm bridge (10.0.0.0/24) or any other interface — belt-and-suspenders
      # on top of the tailscale0-only firewall rule above.
      listenAddresses = [ "100.66.120.5" ];
      enableACME = true;
      acmeRoot = null; # DNS-01: no HTTP webroot challenge directory
      forceSSL = true;
      root = "/var/www";
      locations."/".extraConfig = ''
        autoindex on;
      '';
    };
  };

  # nginx binds a fixed tailnet IP and reads its root + ACME-managed certs off
  # virtiofs shares (/var/www, /var/lib/acme) that mount *after* system
  # activation on this microvm (the documented activation-before-mount gotcha).
  # Order nginx and the per-cert ACME units after the mounts exist and after
  # tailscaled has assigned 100.66.120.5, so the listen address is bindable.
  systemd.services.nginx = {
    after = [ "tailscaled.service" ];
    wants = [ "tailscaled.service" ];
    unitConfig.RequiresMountsFor = [ "/var/www" "/var/lib/acme" ];
  };
  systemd.services."acme-bingy.mellowcatfe.com".unitConfig.RequiresMountsFor = [ "/var/lib/acme" ];

  # The /var/www webroot is a persistent virtiofs share owned hermes:nginx with
  # setgid (2750) so the agent (hermes) writes generated pages as owner and nginx
  # reads them via the nginx group. tmpfiles enforces ownership/mode each boot
  # (RequiresMountsFor keeps it ordered after the share mounts). 'z' (not 'Z')
  # so it only touches the top dir, not recursively every generated file.
  systemd.tmpfiles.settings."10-bingy-www"."/var/www".z = {
    user = "hermes";
    group = "nginx";
    mode = "2750";
  };

  # acme is dynamically allocated but owns the persistent /var/lib/acme certs
  # (its own virtiofs share). /var/lib/nixos (the uid/gid map) lives on the
  # impermanence-rolled-back root, so pin acme's ids to keep cert ownership stable
  # across reboots — same approach splitpro/media use. Verify free with
  # `getent passwd 995` / `getent group 993` on the guest if unsure.
  users.users.acme.uid = 995;
  users.groups.acme.gid = 993;

  programs.zsh.enable = true;

  users = {
    mutableUsers = false;
    users.cjlarose = {
      uid = 1000;
      isNormalUser = true;
      home = "/home/cjlarose";
      extraGroups = [ "wheel" ];
      shell = pkgs.zsh;
      hashedPassword = "$6$YLrfXTwu61JGE.v8$kR5ZdMso2lcnyy7s7GXkIb.kLDyQ2UW3aDyGerQYni96g2kPC1MIY48Y9Q3SdYe2ycuVCrKgH6DlOjUUsK02s0";
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGFtA/9w60OssA+Eji+Ygvd1XCJk/zw/uYLdiiaevELu cjlarose"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILXv1L7zwTqnZJUfqOUVvAe7HI8CoAbVAHBPJhQsohxw cjlarose@ns1010301"
      ];
    };
  };

  services.hermes-agent = {
    enable = true;
    addToSystemPackages = true;
    extraDependencyGroups = [ "messaging" "anthropic" ];
    environmentFiles = [ "/persistence/secrets/hermes.env" ];
    extraPackages = with pkgs; [ gh git openssh nixos-rebuild ];
    settings = hermesSettings;
  };

  # Pin the hermes uid/gid. The agent persists state under /var/lib/hermes (a
  # ZFS-backed virtiofs share), so a stable uid keeps ownership consistent across
  # rebuilds — the same reason media pins jellyfin to 998:998. It also lets the
  # host chown the deploy key to a known uid so the in-guest hermes user can read
  # it (Task 5 Step 2). 994 is below NixOS's auto-allocation range; verify it's
  # free with `getent passwd 994` on the guest if unsure.
  users.users.hermes.uid = 994;
  users.groups.hermes.gid = 994;

  # The module merges `environmentFiles` and `settings` into $HERMES_HOME/.env
  # and config.yaml at *activation* time, but on this microvm activation runs
  # before the /persistence/secrets and /var/lib/hermes virtiofs shares are
  # mounted — so neither file gets written, and the gateway starts with no
  # credentials and Hermes's default model (claude-fable-5, which 404s). Install
  # both at *service start* instead (after the shares are mounted, ordered by
  # RequiresMountsFor), so it's deterministic across reboots. The `+` prefix runs
  # each step as root so it can read the root-owned secret and chown to hermes.
  # config.yaml is fully declarative here, so it's overwritten each start
  # (Hermes's only runtime addition is cosmetic onboarding flags).
  systemd.services.hermes-agent = {
    unitConfig.RequiresMountsFor = [ "/persistence/secrets" "/var/lib/hermes" ];
    serviceConfig.ExecStartPre = lib.mkAfter [
      "+${pkgs.coreutils}/bin/install -D -o hermes -g hermes -m 0600 /persistence/secrets/hermes.env /var/lib/hermes/.hermes/.env"
      "+${pkgs.coreutils}/bin/install -D -o hermes -g hermes -m 0600 ${hermesConfigYaml} /var/lib/hermes/.hermes/config.yaml"
      # Runs as the hermes user (no `+`) after .env is installed; `-` makes a
      # missing/invalid token non-fatal so it never blocks the gateway.
      "-${ghAuthScript}"
    ];
  };

  # Hermes deploys the whole fleet (host + guests) from ns1010301 itself, so it
  # only needs SSH access to the host as cjlarose. Guests are deployed on the
  # host via nixos-rebuild, matching how the fleet is normally operated.
  programs.ssh.extraConfig = ''
    Host ns1010301.cjlarose.dev
      User cjlarose
      IdentityFile /persistence/secrets/hermes_deploy_ed25519
      IdentitiesOnly yes
  '';

  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.users.cjlarose = (import ../../home/cjlarose) {
    inherit system stateVersion additionalPackages;
  };
}
