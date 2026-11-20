# State every impermanence host keeps across its root rollback, whatever it
# runs. Each host still lists its own service state (acme, tailscale, ...)
# alongside this.
#
# - /var/lib/nixos holds the uid/gid maps. Without it, every user or group with
#   no pinned id is renumbered on any boot where the set of system users
#   changes, and files on persistent storage keep the old numbers. immich's
#   26.05 move hit exactly that (immich 995 -> 997, its whole media library
#   suddenly unwritable).
# - /etc/machine-id keeps one host identity, and so one journal directory,
#   across boots. impermanence suppresses systemd-machine-id-commit itself.
# - /var/log keeps the journal, so the boot before a reboot can be inspected.
# - /var/lib/systemd/timers keeps Persistent=true timers' last-run stamps, so a
#   job missed while the host was down (the nightly restic backups among them)
#   runs late after boot instead of being skipped.
# - /var/lib/systemd/coredump keeps crash dumps for debugging.
#
# /var/lib/nixos and /var/log are in nixpkgs' pathsNeededForBoot, so
# impermanence bind-mounts them in the initrd, before activation creates users.
{ ... }:
{
  environment.persistence."/persistence" = {
    directories = [
      "/var/lib/nixos"
      "/var/log"
      "/var/lib/systemd/timers"
      "/var/lib/systemd/coredump"
    ];
    files = [
      "/etc/machine-id"
    ];
  };

  # The journal now lands on /persistence, which is 4 GB on cache; cap it
  # explicitly rather than rely on journald's percentage default.
  services.journald.extraConfig = ''
    SystemMaxUse=500M
  '';
}
