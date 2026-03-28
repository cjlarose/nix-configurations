# Minecraft Mod Config Module System

**Date:** 2026-03-26
**Branch:** minecraft

## Goal

Build a reusable, home-manager-style module system for declaratively managing Minecraft mod config files with Nix. Anyone running a Fabric modded server can use this to generate fully-populated config files from typed Nix options — no manual editing, no runtime-generated config drift.

The library lives in its own repo (`nix-minecraft-mod-config`) and is usable by anyone. It is not tied to any specific server or modpack. Each mod module defines the mod's default configuration as Nix options; users enable the mods they use and override only the values they want to change. The output is format-agnostic and wirable into nix-minecraft's `symlinks`, packwiz, or any other deployment mechanism.

## Repositories

- **`nix-minecraft-mod-config`** — the module system library. Contains the entry point, per-mod modules, and output module. Exposed via flake as `lib.evalModConfigs`. This repo is general-purpose and contains no server-specific overrides.
- **`nix-configurations`** (this repo) — our NixOS configurations. References `nix-minecraft-mod-config` as a flake input and provides a per-server user module (`packages/minecraft/mod-config.nix`) that enables specific mods and declares our server's overrides. This is the only place server-specific values live.

## Design

### Approach: standalone `lib.evalModules`

The tool is a standalone `lib.evalModules` evaluation — not a NixOS module. It takes `pkgs` and a user module, evaluates all per-mod module definitions against the user's overrides, and returns structured outputs. This keeps it decoupled from NixOS so it can be wired into nix-minecraft, packwiz, or anything else.

### Directory structure

**`nix-minecraft-mod-config` repo:**
```
default.nix              # lib.evalModules entry point (exposed as lib.evalModConfigs)
flake.nix                # exposes lib.evalModConfigs = import ./default.nix
modules/
  output.nix             # defines config.files and config.build.*
  mods/
    waystones.nix
    frostiful.nix
    scorchful.nix
    origins.nix
    # ... one file per mod (or mod group)
```

**`nix-configurations` repo (our usage):**
```
packages/minecraft/
  mod-config.nix           # per-server override declarations (the "user module")
```

### Entry point

`default.nix` in the `nix-minecraft-mod-config` repo is a two-argument function:

```nix
{ pkgs }:
userModule:
let
  result = pkgs.lib.evalModules {
    modules = [
      { _module.args = { inherit pkgs; }; }
      ./modules/output.nix
      ./modules/mods/waystones.nix
      ./modules/mods/frostiful.nix
      # ... all mod modules
      userModule
    ];
  };
in result.config
```

Returning `result.config` (not just `result.config.build`) gives the caller access to both `config.files` and `config.build.*`.

The flake exposes this as:
```nix
outputs = { self }: {
  lib.evalModConfigs = import ./default.nix;
};
```

### Output options (`modules/output.nix`)

Per-mod modules contribute to `config.files` — an attrset mapping config-directory-relative paths to file derivations. The `build.directory` output is derived from it automatically:

```nix
{ pkgs, lib, config, ... }: {
  options = {
    files = lib.mkOption {
      type = lib.types.attrsOf lib.types.package;
      default = {};
      description = ''
        Attrset mapping config-directory-relative paths to generated file
        derivations. E.g. "waystones-common.toml" -> <drv>.
        Paths are relative to the server's config/ directory.
      '';
    };

    build.directory = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      description = ''
        A derivation whose root is the config directory, containing symlinks
        to all generated config files. Suitable for use as a packwiz config
        source or for dropping directly into a server's config/ directory.
      '';
    };
  };

  config.build.directory = pkgs.linkFarm "minecraft-mod-configs"
    (lib.mapAttrsToList (name: path: { inherit name path; }) config.files);
}
```

### Call site (nix-minecraft integration)

Example wiring in a NixOS configuration. `nix-minecraft-mod-config` is passed in as a flake input. Derivations are valid values for nix-minecraft's `symlinks` attrset — they coerce to paths.

```nix
{ nixpkgs, ..., additionalPackages, system, nix-minecraft-mod-config, ... }:
let
  allowUnfreePredicate = import ../../shared/unfree-predicate.nix { inherit nixpkgs; };
in { pkgs, config, ... }:
let
  modConfigs = nix-minecraft-mod-config.lib.evalModConfigs { inherit pkgs; }
    (import ../../packages/minecraft/mod-config.nix);
  configSymlinks = pkgs.lib.mapAttrs'
    (name: value: pkgs.lib.nameValuePair "config/${name}" value)
    modConfigs.files;
in {
  services.minecraft-servers.servers.mellowcatfe.symlinks =
    { mods = "${additionalPackages.${system}.minecraft-modpack}/mods"; }
    // configSymlinks;
}
```

### User module (per-server overrides)

A plain NixOS-style module — only the overrides for your server. This lives in the consumer repo, not in `nix-minecraft-mod-config`:

```nix
{ ... }: {
  mods.waystones = {
    enable = true;
    minimumBaseXpCost = 1.0;
    waystoneXpCostMultiplier = 5.0;
    dimensionalWarp = "GLOBAL_ONLY";
    restrictRenameToOwner = true;
    xpCostPerLeashed = 10;
  };

  mods.frostiful = {
    enable = true;
    freezingConfig.doPassiveFreezing = false;
    freezingConfig.doWindSpawning = false;
  };
}
```

With no user module (or an empty one), every mod is disabled and no config files are generated. Enabling a mod with just `mods.waystones.enable = true` produces the mod's complete default config — useful for pinning configs to known-good defaults and preventing runtime generation drift.

### Per-mod module format

Each mod module declares typed options whose defaults match the mod's compiled-in defaults, then contributes generated files to `config.files` when enabled. The module is general-purpose — it models the mod's config schema, not any particular server's preferences.

Example (`modules/mods/waystones.nix`):

```nix
{ pkgs, lib, config, ... }:
let
  cfg = config.mods.waystones;
  fmt = pkgs.formats.toml {};
in {
  options.mods.waystones = {
    enable = lib.mkEnableOption "waystones mod config management";

    dimensionalWarp = lib.mkOption {
      type = lib.types.enum [ "ALLOW" "GLOBAL_ONLY" "DENY" ];
      default = "ALLOW";
      description = "Whether players can warp between dimensions via waystones.";
    };

    minimumBaseXpCost = lib.mkOption {
      type = lib.types.float;
      default = 0.0;
    };

    extraConfig = lib.mkOption {
      type = lib.types.attrs;
      default = {};
      description = ''
        Raw attrset merged on top of the structured options via lib.recursiveUpdate.
        Note: lib.recursiveUpdate replaces lists entirely rather than merging them.
        Use with care for config keys whose values are lists.
      '';
    };
  };

  config.files = lib.mkIf cfg.enable {
    "waystones-common.toml" = fmt.generate "waystones-common.toml"
      (lib.recursiveUpdate
        {
          restrictions = { inherit (cfg) dimensionalWarp restrictRenameToOwner; };
          xpCost = { inherit (cfg) minimumBaseXpCost waystoneXpCostMultiplier xpCostPerLeashed; };
        }
        cfg.extraConfig);
  };
}
```

`extraConfig` is included on every mod module as an escape hatch for config keys not explicitly modeled, or for mods whose configs are too complex to model fully. Because `lib.recursiveUpdate` replaces lists rather than merging them, it is not suitable for list-valued config keys — those must be set in full via `extraConfig` or modeled as explicit options.

### Addon mod support pattern

Some mods have addon mods that extend the base mod's config (e.g. Origins has origins-plus-plus, extraorigins, moborigins). The base module provides an enable flag for each supported addon. When enabled, the addon's entries are added to the config with `lib.mkDefault true`, so users can still override individual values with plain assignments.

Example: `mods.origins.enableOriginsPlusPlus = true` adds all origins-plus-plus origins to `origins_server.json` with all powers enabled. Individual origins or powers can then be disabled:

```nix
mods.origins = {
  enable = true;
  enableOriginsPlusPlus = true;
  origins."origins-plus-plus:land_shark".enabled = false;  # disable one origin
  origins."origins:enderian"."origins:throw_ender_pearl" = false;  # disable one power
};
```

### Format handling

| Extension | nixpkgs tool | Notes |
|-----------|-------------|-------|
| `.json` | `pkgs.formats.json {}` | |
| `.toml` | `pkgs.formats.toml {}` | |
| `.json5` | `pkgs.formats.json {}` | JSON5 is a superset of JSON; all Fabric mod JSON5 parsers accept plain JSON |
| `.cfg` / `.properties` | `pkgs.writeText` with explicit string interpolation | `pkgs.formats.keyValue {}` would work (it produces `key=value` with no spaces), but these files have elaborate comment headers worth preserving; `pkgs.writeText` with inline Nix strings is simpler for that reason |
| `.txt` | `pkgs.writeText` | custom line-based formats |

### Mods to implement

Each entry becomes one module file in `nix-minecraft-mod-config`. Mods with multiple config files contribute multiple entries to `config.files` from a single module. Default values for each option match the mod's own defaults (i.e. what the mod generates on first run with no config file present).

**TOML:**
- `waystones` → `waystones-common.toml`
- `aether` → `aether-common.toml`, `aether/aether_customizations.txt`
- `betterendisland` → `betterendisland-fabric-1_20.toml`
- `biomesoplenty` → `biomesoplenty/generation.toml`
- `farmersdelight` → `farmersdelight-common.toml`
- `goblintraders` → `goblintraders-entities.toml`
- `magnumtorch` → `magnumtorch-server.toml`
- `perfectplushie` → `perfectplushie-loot.toml`
- `endsdelight` → `ends_delight-common.toml`

**JSON:**
- `amendments` → `amendments-common.json`
- `bewitchment` → `bewitchment.json`
- `explorerscompass` → `explorerscompass.json`
- `frostiful` → `frostiful.json`
- `lootr` → `lootr.json`
- `mysticsbiomes` → `mysticsbiomes-common.json`
- `plushiebuddies` → `plushie_buddies.json`
- `scorchful` → `scorchful.json`
- `supplementaries` → `supplementaries-common.json`
- `ubesdelight` → `ubesdelight.json`
- `universalgraves` → `universal-graves/config.json`
- `origins` → `origins/origins_server.json` — vanilla origins built-in as defaults; `enableOriginsPlusPlus` flag adds all OPP origins
- `archers` → `archers/items_v2.json`, `archers/tweaks.json`, `archers/villages.json` — one module per RPG Series mod; items use `attrsOf attrs` with `lib.mkDefault` defaults
- `wizards` → `wizards/items_v4.json`, `wizards/tweaks.json`, `wizards/villages.json`
- `paladins` → `paladins/items_v5.json`, `paladins/shields.json`, `paladins/tweaks.json`, `paladins/villages.json`
- `rogues` → `rogues/items_v2.json`, `rogues/tweaks.json`, `rogues/villages.json`
- `rpgseries` → `rpg_series/loot_v2.json`
- `spellengine` → `spell_engine/enchantments.json`, `spell_engine/server.json5`
- `spellpower` → `spell_power/attributes.json`, `spell_power/enchantments.json`
- `deeperdarker` → `deeperdarker.json5`

**cfg / properties (use `pkgs.writeText`):**
- `easymobfarm` → `easy_mob_farm/mob_farm.cfg`

**Not in scope for initial implementation:** mods not in the mellowcatfe modpack, client-only configs, auto-generated caches (`rpg_series/tag_cache.json`, `spell_power/attributes.json` ordering-only diffs). Additional mods can be added by contributing new module files — the auto-discovery mechanism picks up any `.nix` file in `modules/mods/`.
