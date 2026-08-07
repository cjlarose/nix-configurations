---
name: bumping-cc
description: Use when rolling Claude Code forward on ns1010301 (the cjlarose user) and the pt-docker-cjlarose microvm (the picktrace user) by bumping nixpkgs-unstable — the recurring "update claude" / "bump claude-code" task across both flakes
---

# bumping-cc

Roll Claude Code forward on **both** targets at once by bumping `nixpkgs-unstable`:

- the [[ns1010301]] host's `cjlarose` user (Bun `claude-code` from **cjlarose**'s `nixpkgs-unstable`), and
- the `pt-docker-cjlarose` microvm's `picktrace` user (`claude-code` from **picktrace**'s `nixpkgs-unstable`).

`claude-code` is built from **each flake's own `nixpkgs-unstable`**, so you must bump
`nixpkgs-unstable` in **both** repos. Bumping only one leaves the other target stale.

> **Reference knowledge lives in the wiki** — query it (`wiki:querying-notes`) for the why:
> - **`[[Bumping Claude Code via nixpkgs-unstable]]`** — the full runbook with exact commands,
>   the concrete-values record, and the verification checklist. This skill is its executable
>   front half; the back half (host rebuild + in-place guest activation) is the `wiki:rebuilding-nixos`
>   skill.
> - **`[[Private Flake Inputs and nixos-rebuild as Root]]`** — why the host step skips root eval.
> - **`[[useUserPackages Routes home.packages Through the System Profile]]`** / **`[[Microvm No-Downtime Activation]]`** — why the VM needs an in-place **system** switch.
> - **`[[Fleet-Shared nixpkgs-unstable Stages Sibling Guest Generations]]`** — the sibling-guest
>   side effect to flag (don't silently activate the fleet).

## Step 1 — picktrace repo: bump `nixpkgs-unstable`, push `main`

cjlarose's `picktrace-nix-configurations` input tracks picktrace's **default branch (`main`)** —
push to `main`, not a feature branch.

```sh
cd ~/worktrees/picktrace/nix-configurations/default
nix flake update nixpkgs-unstable
NEW=$(nix flake metadata --json | python3 -c "import sys,json;print(json.load(sys.stdin)['locks']['nodes']['nixpkgs-unstable']['locked']['rev'])")
nix eval --raw "github:nixos/nixpkgs/$NEW#claude-code.version"   # sanity: version advanced
git add flake.lock && git commit -m "Bump nixpkgs-unstable to <rev>" && git push origin main
```

## Step 2 — cjlarose repo: bump `nixpkgs-unstable` AND re-pin picktrace, push `main`

Bump both inputs in one shot, commit **before** the host build (so `configurationRevision`
matches HEAD on the first switch).

```sh
cd ~/worktrees/cjlarose/nix-configurations/default
nix flake update nixpkgs-unstable picktrace-nix-configurations   # re-pin picktrace to step-1 HEAD
git add flake.lock && git commit -m "Bump nixpkgs-unstable to <rev> and picktrace to <picktrace-rev>" && git push origin main
```

**Don't forget the picktrace re-pin** — omitting it leaves the host building the VM from the old
picktrace rev (the VM stays stale).

## Step 3 — host: pre-build as the user, then SKIP ROOT EVAL

`sudo nixos-rebuild switch` fails: the lock bump busts root's eval cache and root can't fetch the
private `cjlarose-llm-wiki` `git+ssh` input. Build as the user, set the profile, activate
directly:

```sh
ROLLBACK_PATH="$(readlink -f /nix/var/nix/profiles/system)"
TOP=$(nix build .#nixosConfigurations.ns1010301.config.system.build.toplevel --no-link --print-out-paths)
sudo nix-env -p /nix/var/nix/profiles/system --set "$TOP"
sudo "$TOP/bin/switch-to-configuration" switch
/etc/profiles/per-user/cjlarose/bin/claude --version   # -> new version
```

## Step 4 — VM: in-place SYSTEM switch (zero downtime)

`useUserPackages = true`, so the `claude-code` package rides the **system** profile — an HM-only
activate is a no-op. Sync the closure DB via a **tempfile** (never piped through nested SSH),
then system-switch in place. Follow `[[Microvm No-Downtime Activation]]` / the `wiki:rebuilding-nixos`
skill steps 3–4:

```sh
CLOSURE_ROOT=/var/lib/microvms/pt-docker-cjlarose/current
TOPLEVEL=$(sudo sed -nE 's|.*init=(/nix/store/[^ ]+)/init.*|\1|p' "$CLOSURE_ROOT/bin/microvm-run" | head -1)
GUEST=picktrace@10.0.0.2
DUMP=$(mktemp); nix-store --dump-db $(nix-store -qR "$TOPLEVEL") > "$DUMP"
scp -q "$DUMP" "$GUEST:/tmp/nix-db-dump"
ssh "$GUEST" "sudo nix-store --load-db < /tmp/nix-db-dump && rm /tmp/nix-db-dump && nix-store --check-validity $TOPLEVEL && echo GUEST_DB_VALID"
rm -f "$DUMP"
ssh "$GUEST" "sudo $TOPLEVEL/bin/switch-to-configuration switch"
ssh picktrace@10.0.0.2 'claude --version; uptime'   # new version; uptime preserved
```

## Step 5 — flag the staged sibling guests

The host switch staged (but did not activate) new generations on the **other** cjlarose guests
(`hermes`, `media`, `minecraft-mellowcatfe`), since `nixpkgs-unstable` is fleet-shared. **Tell
the user** — don't silently activate the fleet (a stale-guest system switch reconciles unrelated
unit drift). See `[[Roll Forward Staged cjlarose Guest Generations]]`.

## Rollback

- Host: `sudo "$ROLLBACK_PATH/bin/switch-to-configuration" switch`.
- VM: `sudo systemctl restart microvm@pt-docker-cjlarose.service`.
