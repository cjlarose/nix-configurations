{ config, pkgs, lib, ... }:

let
  cfg = config.services.tailscale-dns;
  tailscaleDnsScript = pkgs.writeShellApplication {
    name = "tailscale-dns-manager";
    runtimeInputs = [ ];
    text = ''
      TAILSCALE="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
      DNS_SERVER="${cfg.dnsServer}"
      STATE_FILE="/var/run/tailscale-dns.state"

      if "$TAILSCALE" status > /dev/null 2>&1; then
        TAILSCALE_UP=1
      else
        TAILSCALE_UP=0
      fi

      # Even when Tailscale is connected, the DNS server may be unreachable
      # (e.g. it's behind a subnet router that appears active but isn't forwarding).
      # Probe the server directly with a short timeout before treating it as available.
      if [ "$TAILSCALE_UP" -eq 1 ] && /usr/bin/dig @"$DNS_SERVER" +time=2 +tries=1 +short . NS > /dev/null 2>&1; then
        CONNECTED=1
      else
        CONNECTED=0
      fi

      PREV=$(cat "$STATE_FILE" 2>/dev/null || echo "unknown")

      log() {
        echo "$(date '+%Y-%m-%d %H:%M:%S %z') $*"
      }

      if [ "$CONNECTED" -eq 1 ] && [ "$PREV" != "1" ]; then
        log "Tailscale connected and DNS server reachable: setting DNS to $DNS_SERVER"
        /usr/sbin/networksetup -listallnetworkservices | tail -n +2 | sed 's/^\*//' | while IFS= read -r svc; do
          /usr/sbin/networksetup -setdnsservers "$svc" "$DNS_SERVER" || true
        done
        echo "1" > "$STATE_FILE"
      elif [ "$CONNECTED" -eq 0 ] && [ "$PREV" != "0" ]; then
        log "Tailscale disconnected or DNS server unreachable: clearing DNS"
        /usr/sbin/networksetup -listallnetworkservices | tail -n +2 | sed 's/^\*//' | while IFS= read -r svc; do
          /usr/sbin/networksetup -setdnsservers "$svc" "Empty" || true
        done
        echo "0" > "$STATE_FILE"
      fi
    '';
  };
in {
  options.services.tailscale-dns = {
    enable = lib.mkEnableOption "Tailscale DNS management daemon";
    dnsServer = lib.mkOption {
      type = lib.types.str;
      description = "DNS server IP to use when connected to Tailscale";
    };
    pollInterval = lib.mkOption {
      type = lib.types.int;
      default = 10;
      description = "How often (in seconds) to check Tailscale connection status";
    };
  };

  config = lib.mkIf cfg.enable {
    launchd.daemons.tailscale-dns = {
      command = "${tailscaleDnsScript}/bin/tailscale-dns-manager";
      serviceConfig = {
        RunAtLoad = true;
        StartInterval = cfg.pollInterval;
        StandardOutPath = /var/log/tailscale-dns.log;
        StandardErrorPath = /var/log/tailscale-dns.log;
      };
    };
  };
}
