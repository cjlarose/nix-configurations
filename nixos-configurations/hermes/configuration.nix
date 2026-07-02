{ pkgs, config, lib, sharedOverlays, stateVersion, system, additionalPackages, home-manager, ... }:

let
  # Hermes config rendered to config.yaml. Defined here so the same value feeds
  # both `services.hermes-agent.settings` and the ExecStartPre that re-materializes
  # config.yaml at service start (see the systemd block below for why).
  hermesSettings = {
    model.default = "anthropic/claude-sonnet-4-6";
    # Trim thinking-token spend; medium is the cost/quality sweet spot for a
    # low-volume conversational bot. Levels: none|minimal|low|medium|high|xhigh.
    agent.reasoning_effort = "medium";
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

  # Fail-closed allowlist guard. hermes-agent 0.17.0 treats an EMPTY user+role
  # allowlist as "single-tenant, all guild members trusted" (adapter.py
  # _is_allowed_user: `if not has_users and not has_roles: return True`). If
  # /persistence/secrets/hermes.env ever fails to materialize with an allowlist
  # — e.g. a bad secret mount — the gateway would silently open to every guild
  # member. Refuse to start instead. Only trips when BOTH lists are empty (the
  # exact condition that triggers the open default); a normal config sails through.
  hermesEnvGuard = pkgs.writeShellScript "hermes-env-guard" ''
    set -euo pipefail
    export PATH=${lib.makeBinPath [ pkgs.gnugrep pkgs.coreutils ]}:$PATH
    env_file=/var/lib/hermes/.hermes/.env
    users=$(grep -m1 '^DISCORD_ALLOWED_USERS=' "$env_file" | cut -d= -f2- || true)
    roles=$(grep -m1 '^DISCORD_ALLOWED_ROLES=' "$env_file" | cut -d= -f2- || true)
    if [ -z "$users" ] && [ -z "$roles" ]; then
      echo "FATAL: DISCORD_ALLOWED_USERS and DISCORD_ALLOWED_ROLES both empty in $env_file." >&2
      echo "Refusing to start: empty allowlist = all guild members trusted." >&2
      exit 1
    fi
    echo "[hermes-env-guard] allowlist present (users=''${users:+set} roles=''${roles:+set}); continuing."
  '';
in
{

  imports = [
    home-manager.nixosModules.home-manager
  ];

  networking = {
    hostName = "hermes";
    useNetworkd = true;
    firewall.enable = true;
    # Static file server (nginx) is reachable only over the tailnet — open 443
    # on tailscale0 only, never on the microvm bridge or any public path.
    firewall.interfaces.tailscale0.allowedTCPPorts = [ 443 ];
    # Hermes API server — LAN only (microvm bridge, 10.0.0.0/24).
    firewall.interfaces.enp0s11.allowedTCPPorts = [ 8642 ];
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

  # Compressed RAM-backed swap — cushions bursty memory spikes into compressed
  # RAM rather than OOM-killing. zstd backs ~2-3x its real RAM cost. Useful on
  # this 4 GiB guest, where the Opus agent can spike.
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
  };

  # /tmp is a disk-backed block volume (see default.nix), not the RAM tmpfs root.
  # Clear it on boot to keep the tmpfs-style clear-on-reboot semantics (and set
  # the 1777 perms a freshly-formatted /tmp lacks).
  boot.tmp.cleanOnBoot = true;

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
  # /var/lib/hermes/www over the tailnet only. The webroot MUST live under
  # /var/lib/hermes: the hermes-agent service runs the agent's terminal/file
  # tools in a hardened mount namespace whose only writable path is its home
  # (/var/lib/hermes) — every other path, including a dedicated share, is
  # read-only *to the agent*, so the agent could not write generated pages
  # anywhere else. (This was learned the hard way: a dedicated /srv/bingy share
  # was rw in the real guest but read-only inside the agent sandbox.)
  #
  # The catch is traversal: /var/lib/hermes is mode 0770 hermes:hermes, so nginx
  # (uid 60) can't even enter it to reach www/. Rather than loosen the home (it
  # holds .hermes/.env secrets, .ssh, etc.), grant nginx a narrow POSIX ACL of
  # traverse-only (--x) on /var/lib/hermes — enabled by the dataset's
  # acltype=posix. --x lets nginx pass *through* to www/ but not list or read the
  # home's other entries (which keep their own restrictive modes regardless).
  # The www dir itself is hermes:nginx 2750 setgid so generated files inherit
  # group nginx and are readable by the web server.
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
      root = "/var/lib/hermes/www";
      locations."/".extraConfig = ''
        autoindex on;
      '';
    };
  };

  # nginx binds a fixed tailnet IP and reads its root (under /var/lib/hermes) +
  # ACME-managed certs (/var/lib/acme) off virtiofs shares that mount *after*
  # system activation on this microvm (the activation-before-mount gotcha). Order
  # nginx and the per-cert ACME units after the mounts exist and after tailscaled
  # has assigned 100.66.120.5, so the listen address is bindable.
  systemd.services.nginx = {
    after = [ "tailscaled.service" ];
    wants = [ "tailscaled.service" ];
    unitConfig.RequiresMountsFor = [ "/var/lib/hermes" "/var/lib/acme" ];
  };
  systemd.services."acme-bingy.mellowcatfe.com".unitConfig.RequiresMountsFor = [ "/var/lib/acme" ];

  # Create the webroot (hermes:nginx 2750 setgid so generated files inherit the
  # nginx group) and grant nginx traverse-only (--x) on the agent home so it can
  # reach into www/. tmpfiles runs after the /var/lib/hermes mount.
  #
  # Serving works because: (1) setgid on www/ makes new files group=nginx;
  # (2) the agent publishes pages via a shell redirect (umask 0007) so files land
  # mode 0640 — group-readable by nginx. NOTE: do NOT publish with a tool that
  # forces mode 0600 (the agent's write_file does) — a 0600 file zeroes the ACL
  # mask and nginx 403s; write via the shell (printf/cat > file) instead. The
  # default ACL below is belt-and-suspenders for group read on inherited entries.
  systemd.tmpfiles.settings."10-bingy-www" = {
    "/var/lib/hermes/www".d = {
      user = "hermes";
      group = "nginx";
      mode = "2750";
    };
    # Default ACL: new entries under www/ carry nginx group r-x (backs up the
    # setgid+umask path; ineffective if a writer forces mode 0600, see note above).
    "/var/lib/hermes/www".a.argument = "d:g:nginx:r-x,d:m::r-x";
    # POSIX ACL: append nginx traverse-only on the home dir (does not disturb the
    # existing owner/group/other bits, and the home's sensitive subdirs keep their
    # own modes so --x here exposes nothing but the path to www/).
    "/var/lib/hermes".a.argument = "u:nginx:x";
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
      extraGroups = [ "wheel" "hermes" ];
      shell = pkgs.zsh;
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
    extraPackages = with pkgs; [ gh git ];
    settings = hermesSettings;
  };

  # Pin the hermes uid/gid. The agent persists state under /var/lib/hermes (a
  # ZFS-backed virtiofs share), so a stable uid keeps ownership consistent across
  # rebuilds — the same reason media pins jellyfin to 998:998. 994 is below NixOS's
  # auto-allocation range; verify it's free with `getent passwd 994` on the guest
  # if unsure.
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
      # root-owned so the hermes user (the agent) cannot rewrite its own env.
      # 0640 + group hermes = the gateway, gh-auth, and env-guard can READ it;
      # only root (this ExecStartPre, run via `+`) writes it. Source stays the
      # root-only /persistence/secrets/hermes.env that hermes can't touch.
      "+${pkgs.coreutils}/bin/install -D -o root -g hermes -m 0640 /persistence/secrets/hermes.env /var/lib/hermes/.hermes/.env"
      "+${pkgs.coreutils}/bin/install -D -o hermes -g hermes -m 0600 ${hermesConfigYaml} /var/lib/hermes/.hermes/config.yaml"
      # Fail-closed allowlist check — runs as hermes (owns the 0600 .env),
      # after the install above, no `-` prefix so an empty allowlist is fatal.
      "${hermesEnvGuard}"
      # Runs as the hermes user (no `+`) after .env is installed; `-` makes a
      # missing/invalid token non-fatal so it never blocks the gateway.
      "-${ghAuthScript}"
    ];
  };

  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.users.cjlarose = (import ../../home/cjlarose) {
    inherit system stateVersion additionalPackages;
  };

  # The agent commits to git repos (e.g. the LLM wiki, nix-configurations) as the
  # hermes user, so it needs a durable git author identity — without it, commits
  # fail with "Author identity unknown". Set it via a minimal home-manager profile
  # (matching how cjlarose's identity is managed fleet-wide), NOT the full
  # home/cjlarose profile, which the agent doesn't need. home-manager writes this
  # to ~/.config/git/config (XDG), which does NOT collide with the ~/.gitconfig
  # that the ghAuthScript's `gh auth setup-git` writes the credential helper into —
  # git reads both files.
  home-manager.users.hermes = { ... }: {
    home.stateVersion = stateVersion;
    programs.git = {
      enable = true;
      userName = "Bingus Bongus";
      userEmail = "bingy@cjlarose.dev";
      extraConfig = {
        init.defaultBranch = "main";
        pull.ff = "only";
        push.autoSetupRemote = true;
      };
    };
  };
}
