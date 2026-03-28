# Minecraft Mod Config Modules Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement all ~29 mod modules in the `nix-minecraft-mod-config` repo, create the `mod-config.nix` user module in `nix-configurations`, and wire it into ns1010301's configuration.

**Architecture:** Each mod gets a `.nix` file in `nix-minecraft-mod-config/modules/mods/`. Auto-discovered via `builtins.readDir` in `default.nix`. All configs use explicit per-key Nix options with inline hardcoded defaults. Complex mods (frostiful, scorchful, supplementaries) use per-section nested options with `inherit` in the config block. Origins uses `attrsOf (submodule { freeformType = attrsOf bool; })` with `lib.mkDefault` for vanilla origin defaults in the config block. RPG Series mods (archers, wizards, paladins, rogues, rpgseries, spellengine, spellpower) each get their own module; items/weapons/armor use `attrsOf lib.types.attrs` with `lib.mkDefault` entries, populated from the source config files. No `defaults/` directory — every key is a proper Nix option. The user module lives in `nix-configurations/packages/minecraft/mod-config.nix` and is referenced via the flake input.

**Tech Stack:** Nix flakes, `lib.evalModules`, `pkgs.formats.toml {}`, `pkgs.formats.json {}`, `pkgs.writeText`, `lib.recursiveUpdate`, `builtins.fromJSON`

---

## Repos

- **`~/worktrees/cjlarose/nix-minecraft-mod-config/default`** — module library (Tasks 1–30)
- **`~/worktrees/cjlarose/nix-configurations/default`** — NixOS configurations (Tasks 32–34)

## File Structure

**nix-minecraft-mod-config:**
```
flake.nix                          modify: add nixpkgs input + checks output
default.nix                        modify: auto-discover modules/mods/*.nix
checks.nix                         create
modules/mods/
  waystones.nix                    create
  amendments.nix                   create
  aether.nix                       create
  betterendisland.nix              create
  biomesoplenty.nix                create
  farmersdelight.nix               create
  goblintraders.nix                create
  magnumtorch.nix                  create
  perfectplushie.nix               create
  endsdelight.nix                  create
  bewitchment.nix                  create
  explorerscompass.nix             create
  lootr.nix                        create
  mysticsbiomes.nix                create
  plushiebuddies.nix               create
  ubesdelight.nix                  create
  universalgraves.nix              create
  frostiful.nix                    create
  scorchful.nix                    create
  supplementaries.nix              create
  deeperdarker.nix                 create
  origins.nix                      create
  archers.nix                      create
  wizards.nix                      create
  paladins.nix                     create
  rogues.nix                       create
  rpgseries.nix                    create
  spellengine.nix                  create
  spellpower.nix                   create
  easymobfarm.nix                  create

```

**nix-configurations:**
```
packages/minecraft/mod-config.nix                       create
nixos-configurations/ns1010301/configuration.nix        modify
```

---

## Testing

After each task: run `nix flake check` in `~/worktrees/cjlarose/nix-minecraft-mod-config/default`.
- Tasks 1: `checks.x86_64-linux.eval-empty` builds successfully.
- Tasks 2–31: Both `checks.x86_64-linux.eval-empty` and the module's `checks.x86_64-linux.<mod>-*` derivation build successfully.

Tests in `checks.nix` use `pkgs.runCommand` with `grep -qF` assertions to verify that the generated config files contain expected values when options are set to their pebblehost override values.

Final integration test: `nix build .#nixosConfigurations.ns1010301.config.system.build.toplevel --dry-run` in `~/worktrees/cjlarose/nix-configurations/default`.

---

## Task 1: Setup — flake, default.nix, mods/ directory

**Context:** `modules/output.nix` already exists in the repo. The flake wiring in `nix-configurations` (adding `nix-minecraft-mod-config` as a `path:` input and threading it through `nixos-configurations/default.nix` → `ns1010301/default.nix` → `configuration.nix`) was done in a prior session and is already committed.

**Files:**
- Modify: `flake.nix`
- Modify: `default.nix`
- Create: `modules/mods/.gitkeep` (empty placeholder until first mod module)

- [ ] **Step 0: Verify modules/output.nix exists**

```bash
cat ~/worktrees/cjlarose/nix-minecraft-mod-config/default/modules/output.nix
```
Expected: file exists and defines `options.files` and `config.build.directory` with `pkgs.linkFarm`.

- [ ] **Step 1: Update flake.nix to add nixpkgs input and checks output**

```nix
{
  description = "Home-manager-style module system for Minecraft mod config files";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";

  outputs = { self, nixpkgs }: let
    pkgs = nixpkgs.legacyPackages.x86_64-linux;
  in {
    lib.evalModConfigs = import ./default.nix;

    checks.x86_64-linux = import ./checks.nix { inherit self pkgs; };
  };
}
```

- [ ] **Step 2: Update default.nix to auto-discover modules/mods/**

```nix
{ pkgs }:
userModule:
let
  result = pkgs.lib.evalModules {
    modules = [
      { _module.args = { inherit pkgs; }; }
      ./modules/output.nix
    ] ++ (
      map (name: ./modules/mods/${name})
        (builtins.filter (n: pkgs.lib.hasSuffix ".nix" n)
          (builtins.attrNames (builtins.readDir ./modules/mods)))
    ) ++ [ userModule ];
  };
in result.config
```

- [ ] **Step 3: Create checks.nix**

```nix
{ self, pkgs }:
let
  lib = pkgs.lib;
  evalWith = userModule:
    self.lib.evalModConfigs { inherit pkgs; } ({ ... }: userModule);
  checkConfig = name: drv: patterns:
    pkgs.runCommand "test-${name}" { } (
      lib.concatStringsSep "\n"
        (map (p: "grep -qF ${lib.escapeShellArg p} ${drv}"
              + " || { echo 'FAIL: ${name}: expected pattern not found: ${p}'; exit 1; }")
          patterns)
      + "\ntouch $out"
    );
  checkJsonPath = name: drv: jqExpr: expected:
    pkgs.runCommand "test-${name}" { nativeBuildInputs = [ pkgs.jq ]; } ''
      result=$(jq -r ${lib.escapeShellArg jqExpr} ${drv})
      if [ "$result" != ${lib.escapeShellArg expected} ]; then
        echo "FAIL: ${name}: expected ${lib.escapeShellArg expected}, got $result"
        exit 1
      fi
      touch $out
    '';
in {
  eval-empty = (self.lib.evalModConfigs { inherit pkgs; } ({ ... }: {})).build.directory;
}
```

- [ ] **Step 4: Create modules/mods/ directory**

```bash
mkdir -p ~/worktrees/cjlarose/nix-minecraft-mod-config/default/modules/mods
```

- [ ] **Step 5: Update flake.lock**

```bash
cd ~/worktrees/cjlarose/nix-minecraft-mod-config/default
nix flake update
```

- [ ] **Step 6: Run check**

```bash
nix flake check
```
Expected: PASS (empty mods/ directory, evaluates with no mod modules)

- [ ] **Step 7: Commit**

```bash
cd ~/worktrees/cjlarose/nix-minecraft-mod-config/default
git add flake.nix flake.lock default.nix checks.nix
git commit -m "Add nixpkgs input, checks output, and auto-discovery of modules/mods/"
```

Also update nix-configurations lock:
```bash
cd ~/worktrees/cjlarose/nix-configurations/default
nix flake update nix-minecraft-mod-config
git add flake.lock && git commit -m "Update nix-minecraft-mod-config flake lock"
```

---

## Task 2: waystones module

Default source: `/tmp/mellowcatfe-config-20260325/waystones-common.toml`
Pebblehost overrides: `dimensionalWarp="GLOBAL_ONLY"`, `restrictRenameToOwner=true`, `minimumBaseXpCost=1.0`, `waystoneXpCostMultiplier=5.0`, `xpCostPerLeashed=10`

**Files:**
- Create: `modules/mods/waystones.nix`

- [ ] **Step 1: Create modules/mods/waystones.nix**

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
    };

    restrictRenameToOwner = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };

    minimumBaseXpCost = lib.mkOption {
      type = lib.types.float;
      default = 0.0;
    };

    waystoneXpCostMultiplier = lib.mkOption {
      type = lib.types.float;
      default = 0.0;
    };

    xpCostPerLeashed = lib.mkOption {
      type = lib.types.int;
      default = 0;
    };

    extraConfig = lib.mkOption {
      type = lib.types.attrs;
      default = {};
      description = ''
        Raw attrset merged on top of the structured options via lib.recursiveUpdate.
        Note: lib.recursiveUpdate replaces lists entirely rather than merging them.
      '';
    };
  };

  config.files = lib.mkIf cfg.enable {
    "waystones-common.toml" = fmt.generate "waystones-common.toml"
      (lib.recursiveUpdate {
        client = {
          disableTextGlow = false;
        };
        compatibility = {
          displayWaystonesOnJourneyMap = true;
          preferJourneyMapIntegration = true;
        };
        cooldowns = {
          globalWaystoneCooldownMultiplier = 1.0;
          inventoryButtonCooldown = 300;
          scrollUseTime = 32;
          warpPlateUseTime = 20;
          warpStoneCooldown = 30;
          warpStoneUseTime = 32;
        };
        inventoryButton = {
          creativeWarpButtonX = 88;
          creativeWarpButtonY = 33;
          inventoryButton = "";
          warpButtonX = 58;
          warpButtonY = 60;
        };
        restrictions = {
          allowWaystoneToWaystoneTeleport = true;
          dimensionalWarp = cfg.dimensionalWarp;
          dimensionalWarpAllowList = [];
          dimensionalWarpDenyList = [];
          generatedWaystonesUnbreakable = false;
          globalWaystoneSetupRequiresCreativeMode = true;
          leashedDenyList = [ "minecraft:wither" ];
          restrictRenameToOwner = cfg.restrictRenameToOwner;
          restrictToCreative = false;
          transportLeashed = true;
          transportLeashedDimensional = true;
        };
        worldGen = {
          customWaystoneNames = [];
          dimensionAllowList = [ "minecraft:overworld" "minecraft:the_nether" "minecraft:the_end" ];
          dimensionDenyList = [];
          forceSpawnInVillages = false;
          frequency = 25;
          nameGenerationMode = "PRESET_FIRST";
          spawnInVillages = true;
          worldGenStyle = "BIOME";
        };
        xpCost = {
          blocksPerXpLevel = 1000;
          dimensionalWarpXpCost = 3;
          globalWaystoneXpCostMultiplier = 0.0;
          inventoryButtonXpCostMultiplier = 0.0;
          inverseXpCost = false;
          maximumBaseXpCost = 3.0;
          minimumBaseXpCost = cfg.minimumBaseXpCost;
          portstoneXpCostMultiplier = 0.0;
          sharestoneXpCostMultiplier = 0.0;
          warpPlateXpCostMultiplier = 0.0;
          warpStoneXpCostMultiplier = 0.0;
          waystoneXpCostMultiplier = cfg.waystoneXpCostMultiplier;
          xpCostPerLeashed = cfg.xpCostPerLeashed;
        };
      } cfg.extraConfig);
  };
}
```

- [ ] **Step 2: Write test in checks.nix**

Add to `checks.nix` (inside the `in { ... }` block, before the closing `}`):

```nix
  waystones-overrides = checkConfig "waystones-overrides"
    (evalWith { mods.waystones = { enable = true; dimensionalWarp = "GLOBAL_ONLY"; restrictRenameToOwner = true; minimumBaseXpCost = 1.0; }; }).files."waystones-common.toml"
    [ "GLOBAL_ONLY" "restrictRenameToOwner = true" "minimumBaseXpCost = 1.0" ];
```

- [ ] **Step 3: Run check**

```bash
cd ~/worktrees/cjlarose/nix-minecraft-mod-config/default
nix flake check
```
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add modules/mods/waystones.nix checks.nix
git commit -m "Add waystones mod config module"
```

---

## Task 3: aether module

Default source (`aether-common.toml`): `/tmp/mellowcatfe-config-20260325/aether-common.toml`
Default source (`aether_customizations.txt`): `/tmp/pebblehost-config/config/aether/aether_customizations.txt` (†)
Pebblehost overrides: `Gameplay."Show Patreon message" = false`; `aether_customizations.txt` values are at pebblehost defaults

**Files:**
- Create: `modules/mods/aether.nix`

- [ ] **Step 1: Create modules/mods/aether.nix**

```nix
{ pkgs, lib, config, ... }:
let
  cfg = config.mods.aether;
  fmt = pkgs.formats.toml {};
in {
  options.mods.aether = {
    enable = lib.mkEnableOption "aether mod config management";

    showPatreonMessage = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };

    extraConfig = lib.mkOption {
      type = lib.types.attrs;
      default = {};
    };
  };

  config.files = lib.mkIf cfg.enable {
    "aether-common.toml" = fmt.generate "aether-common.toml"
      (lib.recursiveUpdate {
        Gameplay = {
          "Reposition attack message above hotbar" = false;
          "Show Patreon message" = cfg.showPatreonMessage;
          "Gives starting loot on entry" = true;
          "Use default Curios' menu" = false;
          "Gives player Aether Portal Frame item" = false;
          "Repeat Sun Spirit's battle dialogue" = true;
        };
        "Data Pack" = {
          "Add Temporary Freezing automatically" = false;
          "Add Ruined Portals automatically" = false;
        };
        Modpack = {
          "Randomize boss names" = true;
        };
      } cfg.extraConfig);

    "aether/aether_customizations.txt" = pkgs.writeText "aether_customizations.txt" ''
      haloEnabled:true
      haloColor:
      developerGlowEnabled:false
      developerGlowColor:
      moaSkin:
    '';
  };
}
```

- [ ] **Step 2: Write test in checks.nix**

Add to `checks.nix`:

```nix
  aether-overrides = checkConfig "aether-overrides"
    (evalWith { mods.aether = { enable = true; showPatreonMessage = false; }; }).files."aether-common.toml"
    [ "message\" = false" ];
```

- [ ] **Step 3: Run check** `nix flake check` — Expected: PASS

- [ ] **Step 4: Commit** `git add modules/mods/aether.nix checks.nix && git commit -m "Add aether mod config module (aether-common.toml + aether_customizations.txt)"`

---

## Task 4: betterendisland module

Default source: `/tmp/mellowcatfe-config-20260325/betterendisland-fabric-1_20.toml`
Pebblehost override: `general.resummonedDragonDropsEgg = true`

**Files:**
- Create: `modules/mods/betterendisland.nix`

- [ ] **Step 1: Create modules/mods/betterendisland.nix**

```nix
{ pkgs, lib, config, ... }:
let
  cfg = config.mods.betterendisland;
  fmt = pkgs.formats.toml {};
in {
  options.mods.betterendisland = {
    enable = lib.mkEnableOption "betterendisland mod config management";

    resummonedDragonDropsEgg = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };

    extraConfig = lib.mkOption {
      type = lib.types.attrs;
      default = {};
    };
  };

  config.files = lib.mkIf cfg.enable {
    "betterendisland-fabric-1_20.toml" = fmt.generate "betterendisland-fabric-1_20.toml"
      (lib.recursiveUpdate {
        general = {
          resummonedDragonDropsEgg = cfg.resummonedDragonDropsEgg;
          useVanillaSpawnPlatform = false;
        };
      } cfg.extraConfig);
  };
}
```

- [ ] **Step 2: Write test in checks.nix**

Add to `checks.nix`:

```nix
  betterendisland-overrides = checkConfig "betterendisland-overrides"
    (evalWith { mods.betterendisland = { enable = true; resummonedDragonDropsEgg = true; }; }).files."betterendisland-fabric-1_20.toml"
    [ "resummonedDragonDropsEgg = true" ];
```

- [ ] **Step 3: Run check** `nix flake check` — Expected: PASS

- [ ] **Step 4: Commit** `git add modules/mods/betterendisland.nix checks.nix && git commit -m "Add betterendisland mod config module"`

---

## Task 5: biomesoplenty module

Default source: `/tmp/mellowcatfe-config-20260325/biomesoplenty/generation.toml`
Pebblehost overrides: `bop_primary_overworld_region_weight=8`, `bop_overworld_rare_region_weight=4`, `bop_secondary_overworld_region_weight=6`

**Files:**
- Create: `modules/mods/biomesoplenty.nix`

- [ ] **Step 1: Create modules/mods/biomesoplenty.nix**

```nix
{ pkgs, lib, config, ... }:
let
  cfg = config.mods.biomesoplenty;
  fmt = pkgs.formats.toml {};
in {
  options.mods.biomesoplenty = {
    enable = lib.mkEnableOption "biomesoplenty mod config management";

    bopPrimaryOverworldRegionWeight = lib.mkOption {
      type = lib.types.int;
      default = 10;
    };

    bopOverworldRareRegionWeight = lib.mkOption {
      type = lib.types.int;
      default = 2;
    };

    bopSecondaryOverworldRegionWeight = lib.mkOption {
      type = lib.types.int;
      default = 8;
    };

    extraConfig = lib.mkOption {
      type = lib.types.attrs;
      default = {};
    };
  };

  config.files = lib.mkIf cfg.enable {
    "biomesoplenty/generation.toml" = fmt.generate "generation.toml"
      (lib.recursiveUpdate {
        nether = {
          bop_nether_region_weight = 13;
          bop_nether_rare_region_weight = 2;
        };
        overworld = {
          bop_primary_overworld_region_weight = cfg.bopPrimaryOverworldRegionWeight;
          bop_overworld_rare_region_weight = cfg.bopOverworldRareRegionWeight;
          bop_secondary_overworld_region_weight = cfg.bopSecondaryOverworldRegionWeight;
        };
      } cfg.extraConfig);
  };
}
```

- [ ] **Step 2: Write test in checks.nix**

Add to `checks.nix`:

```nix
  biomesoplenty-overrides = checkConfig "biomesoplenty-overrides"
    (evalWith { mods.biomesoplenty = { enable = true; bopPrimaryOverworldRegionWeight = 8; bopOverworldRareRegionWeight = 4; }; }).files."biomesoplenty/generation.toml"
    [ "bop_primary_overworld_region_weight = 8" "bop_overworld_rare_region_weight = 4" ];
```

- [ ] **Step 3: Run check** `nix flake check` — Expected: PASS

- [ ] **Step 4: Commit** `git add modules/mods/biomesoplenty.nix checks.nix && git commit -m "Add biomesoplenty mod config module"`

---

## Task 6: farmersdelight module

Default source: `/tmp/mellowcatfe-config-20260325/farmersdelight-common.toml`
Pebblehost overrides: `cuttingBoardFortuneBonus=0.2`, `richSoilBoostChance=0.4`

**Files:**
- Create: `modules/mods/farmersdelight.nix`

- [ ] **Step 1: Create modules/mods/farmersdelight.nix**

```nix
{ pkgs, lib, config, ... }:
let
  cfg = config.mods.farmersdelight;
  fmt = pkgs.formats.toml {};
in {
  options.mods.farmersdelight = {
    enable = lib.mkEnableOption "farmersdelight mod config management";

    cuttingBoardFortuneBonus = lib.mkOption {
      type = lib.types.float;
      default = 0.1;
    };

    richSoilBoostChance = lib.mkOption {
      type = lib.types.float;
      default = 0.2;
    };

    extraConfig = lib.mkOption {
      type = lib.types.attrs;
      default = {};
    };
  };

  config.files = lib.mkIf cfg.enable {
    "farmersdelight-common.toml" = fmt.generate "farmersdelight-common.toml"
      (lib.recursiveUpdate {
        settings = {
          enableVanillaCropCrates = true;
          cuttingBoardFortuneBonus = cfg.cuttingBoardFortuneBonus;
          farmersBuyFDCrops = true;
          enableRopeReeling = true;
          richSoilBoostChance = cfg.richSoilBoostChance;
          canvasSignDarkBackgroundList = ["gray" "purple" "blue" "brown" "green" "red" "black"];
          wanderingTraderSellsFDItems = true;
        };
        farming = {
          enableTomatoVineClimbingTaggedRopes = true;
          defaultTomatoVineRope = "farmersdelight:rope";
        };
        recipe_book = {
          enableRecipeBookCookingPot = true;
        };
        overrides = {
          rabbitStewJumpBoost = true;
          dispenserUsesToolsOnCuttingBoard = true;
          vanillaSoupExtraEffects = true;
          stack_size = {
            enableStackableSoupItems = true;
            soupItemList = ["minecraft:mushroom_stew" "minecraft:beetroot_soup" "minecraft:rabbit_stew"];
          };
        };
        world = {
          generateFDChestLoot = true;
          genFDCropsOnVillageFarms = true;
          genVillageCompostHeaps = true;
          wild_beetroots = { chance = 30; };
          wild_tomatoes = { chance = 100; };
          wild_cabbages = { chance = 30; };
          wild_onions = { chance = 120; };
          wild_potatoes = { chance = 100; };
          red_mushroom_colonies = { chance = 15; genRedMushroomColony = true; };
          wild_carrots = { chance = 120; };
          brown_mushroom_colonies = { chance = 15; genBrownMushroomColony = true; };
          wild_rice = { chance = 20; };
        };
      } cfg.extraConfig);
  };
}
```

- [ ] **Step 2: Write test in checks.nix**

Add to `checks.nix`:

```nix
  farmersdelight-overrides = checkConfig "farmersdelight-overrides"
    (evalWith { mods.farmersdelight = { enable = true; cuttingBoardFortuneBonus = 0.2; richSoilBoostChance = 0.4; }; }).files."farmersdelight-common.toml"
    [ "cuttingBoardFortuneBonus = 0.2" "richSoilBoostChance = 0.4" ];
```

- [ ] **Step 3: Run check** `nix flake check` — Expected: PASS

- [ ] **Step 4: Commit** `git add modules/mods/farmersdelight.nix checks.nix && git commit -m "Add farmersdelight mod config module"`

---

## Task 7: goblintraders module

Default source: `/tmp/mellowcatfe-config-20260325/goblintraders-entities.toml`
Pebblehost override: `gruntNoiseInterval=160` in both `goblinTrader` and `veinGoblinTrader` sections (default: 80)

**Files:**
- Create: `modules/mods/goblintraders.nix`

- [ ] **Step 1: Create modules/mods/goblintraders.nix**

```nix
{ pkgs, lib, config, ... }:
let
  cfg = config.mods.goblintraders;
  fmt = pkgs.formats.toml {};
  # Note: `manAmount` is intentional — the mod itself uses this key (typo in mod source).
  tradeDefaults = {
    uncommon = { includeChance = 1.0; minAmount = 3; manAmount = 5; };
    common   = { includeChance = 1.0; minAmount = 5; manAmount = 8; };
    legendary = { includeChance = 0.75; minAmount = 1; manAmount = 1; };
    rare     = { includeChance = 1.0; minAmount = 3; manAmount = 4; };
    epic     = { includeChance = 1.0; minAmount = 0; manAmount = 2; };
  };
in {
  options.mods.goblintraders = {
    enable = lib.mkEnableOption "goblin traders mod config management";

    gruntNoiseInterval = lib.mkOption {
      type = lib.types.int;
      default = 80;
      description = "Applied to both goblinTrader and veinGoblinTrader sections.";
    };

    extraConfig = lib.mkOption {
      type = lib.types.attrs;
      default = {};
    };
  };

  config.files = lib.mkIf cfg.enable {
    "goblintraders-entities.toml" = fmt.generate "goblintraders-entities.toml"
      (lib.recursiveUpdate {
        preventDespawnIfNamed = true;
        goblinTrader = {
          traderMaxSpawnLevel = 50;
          traderMinSpawnLevel = -64;
          canAttackBack = true;
          spawnInterval = 12000;
          traderDespawnDelay = 24000;
          restockDelay = 48000;
          traderSpawnDelay = 24000;
          traderSpawnChance = 25;
          gruntNoiseInterval = cfg.gruntNoiseInterval;
          trades = tradeDefaults;
        };
        veinGoblinTrader = {
          traderMaxSpawnLevel = 128;
          traderMinSpawnLevel = 0;
          canAttackBack = true;
          traderDespawnDelay = 24000;
          spawnInterval = 12000;
          restockDelay = 48000;
          traderSpawnDelay = 24000;
          traderSpawnChance = 25;
          gruntNoiseInterval = cfg.gruntNoiseInterval;
          trades = tradeDefaults;
        };
      } cfg.extraConfig);
  };
}
```

- [ ] **Step 2: Write test in checks.nix**

Add to `checks.nix`:

```nix
  goblintraders-overrides = checkConfig "goblintraders-overrides"
    (evalWith { mods.goblintraders = { enable = true; gruntNoiseInterval = 160; }; }).files."goblintraders-entities.toml"
    [ "gruntNoiseInterval = 160" ];
```

- [ ] **Step 3: Run check** `nix flake check` — Expected: PASS

- [ ] **Step 4: Commit** `git add modules/mods/goblintraders.nix checks.nix && git commit -m "Add goblintraders mod config module"`

---

## Task 8: magnumtorch module

Default source: `/tmp/mellowcatfe-config-20260325/magnumtorch-server.toml`
Pebblehost overrides: `diamond_torch.vertical_range=64`, `diamond_torch.shape_type="CUBOID"`, `amethyst_torch.shape_type="CUBOID"`

**Files:**
- Create: `modules/mods/magnumtorch.nix`

- [ ] **Step 1: Create modules/mods/magnumtorch.nix**

```nix
{ pkgs, lib, config, ... }:
let
  cfg = config.mods.magnumtorch;
  fmt = pkgs.formats.toml {};
in {
  options.mods.magnumtorch = {
    enable = lib.mkEnableOption "magnum torch mod config management";

    diamondTorchVerticalRange = lib.mkOption {
      type = lib.types.int;
      default = 32;
    };

    diamondTorchShapeType = lib.mkOption {
      type = lib.types.enum [ "ELLIPSOID" "CUBOID" ];
      default = "ELLIPSOID";
    };

    amethystTorchShapeType = lib.mkOption {
      type = lib.types.enum [ "ELLIPSOID" "CUBOID" ];
      default = "ELLIPSOID";
    };

    extraConfig = lib.mkOption {
      type = lib.types.attrs;
      default = {};
    };
  };

  config.files = lib.mkIf cfg.enable {
    "magnumtorch-server.toml" = fmt.generate "magnumtorch-server.toml"
      (lib.recursiveUpdate {
        diamond_torch = {
          blocked_spawn_types = ["NATURAL" "PATROL" "STRUCTURE" "JOCKEY"];
          mob_whitelist = [];
          vertical_range = cfg.diamondTorchVerticalRange;
          shape_type = cfg.diamondTorchShapeType;
          mob_blacklist = [];
          mob_category = ["MONSTER"];
          horizontal_range = 64;
        };
        emerald_torch = {
          blocked_spawn_types = ["NATURAL" "EVENT"];
          mob_whitelist = [];
          vertical_range = 64;
          shape_type = "CUBOID";
          mob_blacklist = [];
          mob_category = ["CREATURE"];
          horizontal_range = 128;
        };
        amethyst_torch = {
          blocked_spawn_types = ["NATURAL"];
          mob_whitelist = [];
          vertical_range = 32;
          shape_type = cfg.amethystTorchShapeType;
          mob_blacklist = [];
          mob_category = ["AMBIENT" "AXOLOTLS" "WATER_AMBIENT" "WATER_CREATURE" "UNDERGROUND_WATER_CREATURE"];
          horizontal_range = 64;
        };
      } cfg.extraConfig);
  };
}
```

- [ ] **Step 2: Write test in checks.nix**

Add to `checks.nix`:

```nix
  magnumtorch-overrides = checkConfig "magnumtorch-overrides"
    (evalWith { mods.magnumtorch = { enable = true; diamondTorchVerticalRange = 64; diamondTorchShapeType = "CUBOID"; amethystTorchShapeType = "CUBOID"; }; }).files."magnumtorch-server.toml"
    [ "vertical_range = 64" "shape_type = \"CUBOID\"" ];
```

- [ ] **Step 3: Run check** `nix flake check` — Expected: PASS

- [ ] **Step 4: Commit** `git add modules/mods/magnumtorch.nix checks.nix && git commit -m "Add magnumtorch mod config module"`

---

## Task 9: perfectplushie module

Default source: `/tmp/mellowcatfe-config-20260325/perfectplushie-loot.toml`
Pebblehost override: `villageLootTableChance=0.5` (default: 0.1)

**Files:**
- Create: `modules/mods/perfectplushie.nix`

- [ ] **Step 1: Create modules/mods/perfectplushie.nix**

```nix
{ pkgs, lib, config, ... }:
let
  cfg = config.mods.perfectplushie;
  fmt = pkgs.formats.toml {};
in {
  options.mods.perfectplushie = {
    enable = lib.mkEnableOption "perfectplushie mod config management";

    villageLootTableChance = lib.mkOption {
      type = lib.types.float;
      default = 0.1;
    };

    extraConfig = lib.mkOption {
      type = lib.types.attrs;
      default = {};
    };
  };

  config.files = lib.mkIf cfg.enable {
    "perfectplushie-loot.toml" = fmt.generate "perfectplushie-loot.toml"
      (lib.recursiveUpdate {
        loot_table_chances = {
          archaeologyLootTableChance = 0.1;
          buriedTreasureLootTableChance = 0.5;
          villageLootTableChance = cfg.villageLootTableChance;
        };
      } cfg.extraConfig);
  };
}
```

- [ ] **Step 2: Write test in checks.nix**

Add to `checks.nix`:

```nix
  perfectplushie-overrides = checkConfig "perfectplushie-overrides"
    (evalWith { mods.perfectplushie = { enable = true; villageLootTableChance = 0.5; }; }).files."perfectplushie-loot.toml"
    [ "villageLootTableChance = 0.5" ];
```

- [ ] **Step 3: Run check** `nix flake check` — Expected: PASS

- [ ] **Step 4: Commit** `git add modules/mods/perfectplushie.nix checks.nix && git commit -m "Add perfectplushie mod config module"`

---

## Task 10: endsdelight module

Default source: `/tmp/pebblehost-config/config/ends_delight-common.toml` (†)
No pebblehost overrides — these are at pebblehost defaults.

**Files:**
- Create: `modules/mods/endsdelight.nix`

- [ ] **Step 1: Create modules/mods/endsdelight.nix**

```nix
{ pkgs, lib, config, ... }:
let
  cfg = config.mods.endsdelight;
  fmt = pkgs.formats.toml {};
in {
  options.mods.endsdelight = {
    enable = lib.mkEnableOption "ends delight mod config management";

    extraConfig = lib.mkOption {
      type = lib.types.attrs;
      default = {};
    };
  };

  config.files = lib.mkIf cfg.enable {
    "ends_delight-common.toml" = fmt.generate "ends_delight-common.toml"
      (lib.recursiveUpdate {
        "Configs for End's Delight" = {
          allowedMobs = [
            "minecraft:enderman"
            "minecraft:endermite"
            "minecraft:ender_dragon"
            "minecraft:shulker"
          ];
          enableGristleTeleport = true;
          teleportRangeSize = 24;
          teleportMaxHeight = 32;
        };
      } cfg.extraConfig);
  };
}
```

- [ ] **Step 2: Write test in checks.nix**

Add to `checks.nix`:

```nix
  endsdelight-generates = checkConfig "endsdelight-generates"
    (evalWith { mods.endsdelight = { enable = true; }; }).files."ends_delight-common.toml"
    [ "enableGristleTeleport = true" "teleportRangeSize = 24" ];
```

- [ ] **Step 3: Run check** `nix flake check` — Expected: PASS

- [ ] **Step 4: Commit** `git add modules/mods/endsdelight.nix checks.nix && git commit -m "Add endsdelight mod config module"`

---

## Task 11: bewitchment module

Default source: `/tmp/mellowcatfe-config-20260325/bewitchment.json`
Pebblehost overrides: `enableCurses=false`, `altarDistributionRadius=36`

**Files:**
- Create: `modules/mods/bewitchment.nix`

- [ ] **Step 1: Create modules/mods/bewitchment.nix**

```nix
{ pkgs, lib, config, ... }:
let
  cfg = config.mods.bewitchment;
  fmt = pkgs.formats.json {};
in {
  options.mods.bewitchment = {
    enable = lib.mkEnableOption "bewitchment mod config management";

    enableCurses = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };

    altarDistributionRadius = lib.mkOption {
      type = lib.types.int;
      default = 24;
    };

    extraConfig = lib.mkOption {
      type = lib.types.attrs;
      default = {};
    };
  };

  config.files = lib.mkIf cfg.enable {
    "bewitchment.json" = fmt.generate "bewitchment.json"
      (lib.recursiveUpdate {
        disabledPoppets = [];
        enableCurses = cfg.enableCurses;
        enablePolymorph = true;
        altarDistributionRadius = cfg.altarDistributionRadius;
        generateSalt = true;
        generateSilver = true;
        owlWeight = 10; owlMinGroupCount = 1; owlMaxGroupCount = 2;
        ravenWeight = 10; ravenMinGroupCount = 1; ravenMaxGroupCount = 3;
        snakeWeight = 6; snakeMinGroupCount = 1; snakeMaxGroupCount = 2;
        toadWeight = 10; toadMinGroupCount = 1; toadMaxGroupCount = 3;
        ghostWeight = 20; ghostMinGroupCount = 1; ghostMaxGroupCount = 1;
        vampireWeight = 20; vampireMinGroupCount = 1; vampireMaxGroupCount = 1;
        werewolfWeight = 20; werewolfMinGroupCount = 1; werewolfMaxGroupCount = 1;
        hellhoundWeight = 6; hellhoundMinGroupCount = 1; hellhoundMaxGroupCount = 1;
      } cfg.extraConfig);
  };
}
```

- [ ] **Step 2: Write test in checks.nix**

Add to `checks.nix`:

```nix
  bewitchment-overrides = checkConfig "bewitchment-overrides"
    (evalWith { mods.bewitchment = { enable = true; enableCurses = false; altarDistributionRadius = 36; }; }).files."bewitchment.json"
    [ "\"enableCurses\": false" "\"altarDistributionRadius\": 36" ];
```

- [ ] **Step 3: Run check** `nix flake check` — Expected: PASS

- [ ] **Step 4: Commit** `git add modules/mods/bewitchment.nix checks.nix && git commit -m "Add bewitchment mod config module"`

---

## Task 12: amendments module

Default source: `/tmp/mellowcatfe-config-20260325/amendments-common.json`
Pebblehost overrides: read from `/tmp/pebblehost-config/config/amendments-common.json`

**Files:**
- Create: `modules/mods/amendments.nix`

- [ ] **Step 1: Read the default and pebblehost config files**

```bash
cat /tmp/mellowcatfe-config-20260325/amendments-common.json
cat /tmp/pebblehost-config/config/amendments-common.json
```

Identify which keys differ between the two files. Create explicit options for the differing keys, with defaults from the mellowcatfe (ns1010301) version. All other keys become hardcoded defaults in the config block.

- [ ] **Step 2: Create modules/mods/amendments.nix**

Follow the same pattern as bewitchment.nix: `pkgs.formats.json {}`, explicit options for keys that differ, `extraConfig` escape hatch, `lib.recursiveUpdate` in the config block. All keys from the default config should be present as hardcoded values in the generated output, with the differing keys using `cfg.*` references.

- [ ] **Step 3: Write test in checks.nix**

Add a `checkConfig` test that verifies the overridden values appear in the generated file.

- [ ] **Step 4: Run check** `nix flake check` — Expected: PASS

- [ ] **Step 5: Commit** `git add modules/mods/amendments.nix checks.nix && git commit -m "Add amendments mod config module"`

---

## Task 13: explorerscompass module

Default source: `/tmp/mellowcatfe-config-20260325/explorerscompass.json`
Pebblehost overrides: `common.allowTeleport=false`, `common.structureBlacklist=["minecraft:stronghold","minecraft:buried_treasure"]`

**Files:**
- Create: `modules/mods/explorerscompass.nix`

- [ ] **Step 1: Create modules/mods/explorerscompass.nix**

```nix
{ pkgs, lib, config, ... }:
let
  cfg = config.mods.explorerscompass;
  fmt = pkgs.formats.json {};
in {
  options.mods.explorerscompass = {
    enable = lib.mkEnableOption "explorerscompass mod config management";

    allowTeleport = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };

    structureBlacklist = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
    };

    extraConfig = lib.mkOption {
      type = lib.types.attrs;
      default = {};
    };
  };

  config.files = lib.mkIf cfg.enable {
    "explorerscompass.json" = fmt.generate "explorerscompass.json"
      (lib.recursiveUpdate {
        common = {
          allowTeleportComment = "Allows a player to teleport to a located structure when in creative mode, opped, or in cheat mode.";
          allowTeleport = cfg.allowTeleport;
          displayCoordinatesComment = "Allows players to view the precise coordinates and distance of a located structure on the HUD, rather than relying on the direction the compass is pointing.";
          displayCoordinates = true;
          maxRadiusComment = "The maximum radius that will be searched for a structure. Raising this value will increase search accuracy but will potentially make the process more resource intensive.";
          maxRadius = 10000;
          maxSamplesComment = "The maximum number of samples to be taken when searching for a structure.";
          maxSamples = 100000;
          structureBlacklistComment = "A list of structures that the compass will not display in the GUI and will not be able to search for. The wildcard character * can be used to match any number of characters, and ? can be used to match one character. Ex (ignore backslashes): [\"minecraft:stronghold\", \"minecraft:endcity\", \"minecraft:*village*\"]";
          structureBlacklist = cfg.structureBlacklist;
        };
        client = {
          displayWithChatOpenComment = "Displays compass information even while chat is open.";
          displayWithChatOpen = true;
          translateStructureNamesComment = "Attempts to translate structure names before fixing the unlocalized names. Translations may not be available for all structures.";
          translateStructureNames = true;
          overlayLineOffsetComment = "The line offset for information rendered on the HUD.";
          overlayLineOffset = 1;
          overlaySideComment = "The side for information rendered on the HUD. Ex: LEFT, RIGHT";
          overlaySide = "LEFT";
        };
      } cfg.extraConfig);
  };
}
```

- [ ] **Step 2: Write test in checks.nix**

Add to `checks.nix`:

```nix
  explorerscompass-overrides = checkConfig "explorerscompass-overrides"
    (evalWith { mods.explorerscompass = { enable = true; allowTeleport = false; structureBlacklist = [ "minecraft:stronghold" "minecraft:buried_treasure" ]; }; }).files."explorerscompass.json"
    [ "\"allowTeleport\": false" "minecraft:stronghold" "minecraft:buried_treasure" ];
```

- [ ] **Step 3: Run check** `nix flake check` — Expected: PASS

- [ ] **Step 4: Commit** `git add modules/mods/explorerscompass.nix checks.nix && git commit -m "Add explorerscompass mod config module"`

---

## Task 14: lootr module

Default source: `/tmp/mellowcatfe-config-20260325/lootr.json`
Pebblehost overrides: `debug.report_invalid_tables=false`, `breaking.blast_resistant=true`

**Files:**
- Create: `modules/mods/lootr.nix`

- [ ] **Step 1: Create modules/mods/lootr.nix**

```nix
{ pkgs, lib, config, ... }:
let
  cfg = config.mods.lootr;
  fmt = pkgs.formats.json {};
in {
  options.mods.lootr = {
    enable = lib.mkEnableOption "lootr mod config management";

    reportInvalidTables = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };

    blastResistant = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };

    extraConfig = lib.mkOption {
      type = lib.types.attrs;
      default = {};
    };
  };

  config.files = lib.mkIf cfg.enable {
    "lootr.json" = fmt.generate "lootr.json"
      (lib.recursiveUpdate {
        debug = { report_invalid_tables = cfg.reportInvalidTables; };
        seed = { randomize_seed = true; };
        conversion = {
          max_entry_age = 12000;
          disable = false;
          elytra = true;
          world_border = false;
        };
        breaking = {
          bypass_spawn_protection = true;
          enable_break = false;
          enable_fake_player_break = false;
          disable_break = false;
          power_comparators = true;
          blast_resistant = cfg.blastResistant;
          blast_immune = false;
          trapped_custom = false;
        };
        lists = {
          dimension_whitelist = [];
          dimension_blacklist = [];
          dimension_modid_blacklist = [];
          dimension_modid_whitelist = [];
          loot_table_blacklist = [];
          loot_modid_blacklist = [];
        };
        decay = {
          decay_value = 6000;
          decay_all = false;
          decay_modids = [];
          decay_loot_tables = [];
          decay_dimensions = [];
        };
        refresh = {
          refresh_value = 24000;
          refresh_all = false;
          refresh_modids = [];
          refresh_loot_tables = [];
          refresh_dimensions = [];
        };
        notifications = {
          notification_delay = 600;
          disable_notifications = false;
          disable_message_styles = false;
        };
        client = {
          vanilla_textures = false;
          old_textures = false;
        };
      } cfg.extraConfig);
  };
}
```

- [ ] **Step 2: Write test in checks.nix**

Add to `checks.nix`:

```nix
  lootr-overrides = checkConfig "lootr-overrides"
    (evalWith { mods.lootr = { enable = true; reportInvalidTables = false; blastResistant = true; }; }).files."lootr.json"
    [ "\"reportInvalidTables\": false" "\"blastResistant\": true" ];
```

- [ ] **Step 3: Run check** `nix flake check` — Expected: PASS

- [ ] **Step 4: Commit** `git add modules/mods/lootr.nix checks.nix && git commit -m "Add lootr mod config module"`

---

## Task 15: mysticsbiomes module

Default source: `/tmp/mellowcatfe-config-20260325/mysticsbiomes-common.json`
Pebblehost overrides: `biomeRegionWeight=6`, `rainbowChickenSpawnChance=10`

**Files:**
- Create: `modules/mods/mysticsbiomes.nix`

- [ ] **Step 1: Create modules/mods/mysticsbiomes.nix**

```nix
{ pkgs, lib, config, ... }:
let
  cfg = config.mods.mysticsbiomes;
  fmt = pkgs.formats.json {};
in {
  options.mods.mysticsbiomes = {
    enable = lib.mkEnableOption "mystics biomes mod config management";

    biomeRegionWeight = lib.mkOption {
      type = lib.types.int;
      default = 4;
    };

    rainbowChickenSpawnChance = lib.mkOption {
      type = lib.types.int;
      default = 6;
    };

    extraConfig = lib.mkOption {
      type = lib.types.attrs;
      default = {};
    };
  };

  config.files = lib.mkIf cfg.enable {
    "mysticsbiomes-common.json" = fmt.generate "mysticsbiomes-common.json"
      (lib.recursiveUpdate {
        biomeRegionWeight = cfg.biomeRegionWeight;
        enableStrawberryFields = true;
        enableLavenderMeadow = true;
        enableBambooBlossomForest = true;
        enableAutumnalGrove = true;
        enableLushOasis = true;
        enableLagoon = true;
        enableTropics = true;
        rainbowChickenBiomeSpawns = [
          "minecraft:plains"
          "minecraft:forest"
          "minecraft:flower_forest"
        ];
        rainbowChickenSpawnChance = cfg.rainbowChickenSpawnChance;
      } cfg.extraConfig);
  };
}
```

- [ ] **Step 2: Write test in checks.nix**

Add to `checks.nix`:

```nix
  mysticsbiomes-overrides = checkConfig "mysticsbiomes-overrides"
    (evalWith { mods.mysticsbiomes = { enable = true; biomeRegionWeight = 6; rainbowChickenSpawnChance = 10; }; }).files."mysticsbiomes-common.json"
    [ "\"biomeRegionWeight\": 6" "\"rainbowChickenSpawnChance\": 10" ];
```

- [ ] **Step 3: Run check** `nix flake check` — Expected: PASS

- [ ] **Step 4: Commit** `git add modules/mods/mysticsbiomes.nix checks.nix && git commit -m "Add mysticsbiomes mod config module"`

---

## Task 16: plushiebuddies module

Default source: `/tmp/mellowcatfe-config-20260325/plushie_buddies.json`
Pebblehost override: `plushieCost=5` (default: 10)

**Files:**
- Create: `modules/mods/plushiebuddies.nix`

- [ ] **Step 1: Create modules/mods/plushiebuddies.nix**

```nix
{ pkgs, lib, config, ... }:
let
  cfg = config.mods.plushiebuddies;
  fmt = pkgs.formats.json {};
in {
  options.mods.plushiebuddies = {
    enable = lib.mkEnableOption "plushie buddies mod config management";

    plushieCost = lib.mkOption {
      type = lib.types.int;
      default = 10;
    };

    extraConfig = lib.mkOption {
      type = lib.types.attrs;
      default = {};
    };
  };

  config.files = lib.mkIf cfg.enable {
    "plushie_buddies.json" = fmt.generate "plushie_buddies.json"
      (lib.recursiveUpdate {
        plushieCost = cfg.plushieCost;
        traderLevel = 5;
        isCustomTradeEnabled = true;
      } cfg.extraConfig);
  };
}
```

- [ ] **Step 2: Write test in checks.nix**

Add to `checks.nix`:

```nix
  plushiebuddies-overrides = checkConfig "plushiebuddies-overrides"
    (evalWith { mods.plushiebuddies = { enable = true; plushieCost = 5; }; }).files."plushie_buddies.json"
    [ "\"plushieCost\": 5" ];
```

- [ ] **Step 3: Run check** `nix flake check` — Expected: PASS

- [ ] **Step 4: Commit** `git add modules/mods/plushiebuddies.nix checks.nix && git commit -m "Add plushiebuddies mod config module"`

---

## Task 17: ubesdelight module

Default source: `/tmp/mellowcatfe-config-20260325/ubesdelight.json`
Pebblehost override: `bakingMatFortuneBonus=0.2` (default: 0.1)

**Files:**
- Create: `modules/mods/ubesdelight.nix`

- [ ] **Step 1: Create modules/mods/ubesdelight.nix**

```nix
{ pkgs, lib, config, ... }:
let
  cfg = config.mods.ubesdelight;
  fmt = pkgs.formats.json {};
in {
  options.mods.ubesdelight = {
    enable = lib.mkEnableOption "ubes delight mod config management";

    bakingMatFortuneBonus = lib.mkOption {
      type = lib.types.float;
      default = 0.1;
    };

    extraConfig = lib.mkOption {
      type = lib.types.attrs;
      default = {};
    };
  };

  config.files = lib.mkIf cfg.enable {
    "ubesdelight.json" = fmt.generate "ubesdelight.json"
      (lib.recursiveUpdate {
        enableUDCropCrates = true;
        farmersBuyUDCrops = true;
        wanderingTraderSellsUDItems = true;
        generateUDChestLoot = true;
        generateWildUbe = true;
        generateWildGarlic = true;
        generateWildGinger = true;
        generateWildLemongrass = true;
        bakingMatFortuneBonus = cfg.bakingMatFortuneBonus;
        isFoodEffectTooltip = true;
      } cfg.extraConfig);
  };
}
```

- [ ] **Step 2: Write test in checks.nix**

Add to `checks.nix`:

```nix
  ubesdelight-overrides = checkConfig "ubesdelight-overrides"
    (evalWith { mods.ubesdelight = { enable = true; bakingMatFortuneBonus = 0.2; }; }).files."ubesdelight.json"
    [ "\"bakingMatFortuneBonus\": 0.2" ];
```

- [ ] **Step 3: Run check** `nix flake check` — Expected: PASS

- [ ] **Step 4: Commit** `git add modules/mods/ubesdelight.nix checks.nix && git commit -m "Add ubesdelight mod config module"`

---

## Task 18: universalgraves module

Explicit typed option for every key in every section. The ns1010301 defaults are hardcoded inline. The `ui` section uses a single `lib.types.attrs` option since per-key typing of deeply nested button config would be impractical.

**Files:**
- Create: `modules/mods/universalgraves.nix`

- [ ] **Step 1: Create modules/mods/universalgraves.nix**

```nix
{ pkgs, lib, config, ... }:
let
  cfg = config.mods.universalgraves;
  fmt = pkgs.formats.json {};
in {
  options.mods.universalgraves = {
    enable = lib.mkEnableOption "universal graves mod config management";

    configVersion = lib.mkOption { type = lib.types.int; default = 3; };

    protection = {
      nonOwnerProtectionTime = lib.mkOption { type = lib.types.int; default = 900; };
      selfDestructionTime = lib.mkOption { type = lib.types.int; default = 1800; };
      dropItemsOnExpiration = lib.mkOption { type = lib.types.bool; default = true; };
      attackersBypassProtection = lib.mkOption { type = lib.types.bool; default = false; };
      useRealTime = lib.mkOption { type = lib.types.bool; default = false; };
    };

    interactions = {
      unlockingCost = lib.mkOption { type = lib.types.attrs; default = { type = "free"; count = 0; }; };
      giveDeathCompass = lib.mkOption { type = lib.types.bool; default = true; };
      enableUseDeathCompassToOpenGui = lib.mkOption { type = lib.types.bool; default = true; };
      enableClickToOpenGui = lib.mkOption { type = lib.types.bool; default = true; };
      shiftAndUseQuickPickup = lib.mkOption { type = lib.types.bool; default = true; };
      allowRemoteProtectionRemoval = lib.mkOption { type = lib.types.bool; default = true; };
      allowRemoteBreaking = lib.mkOption { type = lib.types.bool; default = true; };
      allowRemoteUnlocking = lib.mkOption { type = lib.types.bool; default = false; };
    };

    storage = {
      experienceType = lib.mkOption { type = lib.types.str; default = "percent_points"; };
      "experience_percent:setting_value" = lib.mkOption { type = lib.types.float; default = 100.0; };
      canStoreOnlyXp = lib.mkOption { type = lib.types.bool; default = false; };
      alternativeExperienceEntity = lib.mkOption { type = lib.types.bool; default = true; };
      blockedEnchantments = lib.mkOption { type = lib.types.listOf lib.types.str; default = []; };
    };

    placement = {
      playerGraveLimit = lib.mkOption { type = lib.types.int; default = -1; };
      replaceAnyBlock = lib.mkOption { type = lib.types.bool; default = false; };
      maxDistanceFromSourceLocation = lib.mkOption { type = lib.types.int; default = 8; };
      shiftLocationOnFailure = lib.mkOption { type = lib.types.bool; default = true; };
      maxShiftTries = lib.mkOption { type = lib.types.int; default = 5; };
      maxShiftDistance = lib.mkOption { type = lib.types.int; default = 40; };
      generateOnTopOfFluids = lib.mkOption { type = lib.types.bool; default = false; };
      generateOnGround = lib.mkOption { type = lib.types.bool; default = false; };
      createGravestoneAfterEmptying = lib.mkOption { type = lib.types.bool; default = false; };
      restoreReplacedBlockAfterPlayerBreaking = lib.mkOption { type = lib.types.bool; default = true; };
      cancelCreationForDamageTypes = lib.mkOption { type = lib.types.attrs; default = {}; };
      cancelCreationForIgnoredAttackerTypes = lib.mkOption { type = lib.types.attrs; default = {}; };
      blockingPredicates = lib.mkOption { type = lib.types.listOf lib.types.attrs; default = []; };
      blockInProtectedArea = lib.mkOption { type = lib.types.attrs; default = {}; };
      blacklistedWorlds = lib.mkOption { type = lib.types.listOf lib.types.str; default = []; };
      blacklistedAreas = lib.mkOption { type = lib.types.attrs; default = {}; };
      creationDefaultFailureText = lib.mkOption { type = lib.types.str; default = "<red><lang:'text.graves.creation_failed':'<gold>${position}':'<yellow>${world}>"; };
      creationClaimFailureText = lib.mkOption { type = lib.types.str; default = "<red><lang:'text.graves.creation_failed_claim':'<gold>${position}':'<yellow>${world}>"; };
    };

    teleportation = {
      cost = lib.mkOption { type = lib.types.attrs; default = { type = "creative"; count = 1; }; };
      requiredTime = lib.mkOption { type = lib.types.int; default = 5; };
      yOffset = lib.mkOption { type = lib.types.float; default = 1.0; };
      invincibilityTime = lib.mkOption { type = lib.types.int; default = 2; };
      allowMovementWhileWaiting = lib.mkOption { type = lib.types.bool; default = false; };
      text = lib.mkOption {
        type = lib.types.attrs;
        default = {
          timer = "<lang:'text.graves.teleport.teleport_timer':'${time}'>";
          timer_allow_moving = "<lang:'text.graves.teleport.teleport_timer_moving':'${time}'>";
          location = "<lang:'text.graves.teleport.teleport_location':'${position}'>";
          canceled = "<red><lang:'text.graves.teleport.teleport_cancelled'>";
        };
      };
    };

    model = {
      default = lib.mkOption { type = lib.types.str; default = "default"; };
      alternative = lib.mkOption { type = lib.types.listOf lib.types.attrs; default = []; };
      enableGeyserWorkaround = lib.mkOption { type = lib.types.bool; default = true; };
      gravestoneItemBase = lib.mkOption { type = lib.types.str; default = "minecraft:skeleton_skull"; };
      gravestoneItemNbt = lib.mkOption { type = lib.types.attrs; default = {}; };
    };

    ui = lib.mkOption {
      type = lib.types.attrs;
      default = {
          title = "<lang:'text.graves.players_grave':'\${player}'>";
          admin_title = "<lang:'text.graves.admin_graves'>";
          list_grave_icon = {
            base = {
              icon = "minecraft:chest";
              text = [
                "\${position} <gray>(\${world})"
                "<yellow>\${death_cause}"
                "<gray><lang:'text.graves.items_xp':'<white>\${item_count}':'<white>\${xp}'>"
                "<blue><lang:'text.graves.protected_time':'<white>\${protection_time}'>"
                "<red><lang:'text.graves.break_time':'<white>\${break_time}'>"
              ];
            };
            alt = {
              icon = "minecraft:trapped_chest";
              text = [
                "\${position} <gray>(\${world})"
                "<yellow>\${death_cause}"
                "<gray><lang:'text.graves.items_xp':'<white>\${item_count}':'<white>\${xp}'>"
                "<blue><lang:'text.graves.not_protected'>"
                "<red><lang:'text.graves.break_time':'<white>\${break_time}'>"
              ];
            };
          };
          admin_list_grave_icon = {
            base = {
              icon = "minecraft:chest";
              text = [
                "<dark_gray>[<white>\${player}</>]</> \${position} <gray>(\${world})"
                "<yellow>\${death_cause}"
                "<gray><lang:'text.graves.items_xp':'<white>\${item_count}':'<white>\${xp}'>"
                "<blue><lang:'text.graves.protected_time':'<white>\${protection_time}'>"
                "<red><lang:'text.graves.break_time':'<white>\${break_time}'>"
              ];
            };
            alt = {
              icon = "minecraft:trapped_chest";
              text = [
                "<dark_gray>[<white>\${player}</>]</> \${position} <gray>(\${world})"
                "<yellow>\${death_cause}"
                "<gray><lang:'text.graves.items_xp':'<white>\${item_count}':'<white>\${xp}'>"
                "<blue><lang:'text.graves.not_protected'>"
                "<red><lang:'text.graves.break_time':'<white>\${break_time}'>"
              ];
            };
          };
          grave_info = {
            base = {
              icon = "minecraft:oak_sign";
              text = [
                "\${position} <gray>(\${world})"
                "<yellow>\${death_cause}"
                "<gray><lang:'text.graves.items_xp':'<white>\${item_count}':'<white>\${xp}'>"
                "<blue><lang:'text.graves.protected_time':'<white>\${protection_time}'>"
                "<red><lang:'text.graves.break_time':'<white>\${break_time}'>"
              ];
            };
            alt = {
              icon = "minecraft:oak_sign";
              text = [
                "\${position} <gray>(\${world})"
                "<yellow>\${death_cause}"
                "<gray><lang:'text.graves.items_xp':'<white>\${item_count}':'<white>\${xp}'>"
                "<blue><lang:'text.graves.not_protected'>"
                "<red><lang:'text.graves.break_time':'<white>\${break_time}'>"
              ];
            };
          };
          unlock_grave = {
            base = {
              icon = "minecraft:gold_ingot";
              text = [
                "<#ffd257><lang:'text.graves.gui.unlock_grave'>"
                "<white><lang:'text.graves.gui.cost'> <#cfcfcf>\${cost}"
              ];
            };
            alt = {
              icon = "minecraft:gold_ingot";
              text = [
                "<dark_gray><lang:'text.graves.gui.unlock_grave'>"
                "<white><lang:'text.graves.gui.cost'> <#cfcfcf>\${cost} <gray>(<red><lang:'text.graves.gui.cost.not_enough'></red>)"
              ];
            };
          };
          previous_button = {
            base = {
              icon = {
                id = "universal_graves:icon";
                "Count" = 1;
                tag = { "Texture" = "previous_page"; };
              };
              text = "<lang:'text.graves.gui.previous_page'>";
            };
            alt = {
              icon = {
                id = "universal_graves:icon";
                "Count" = 1;
                tag = { "Texture" = "previous_page_blocked"; };
              };
              text = "<dark_gray><lang:'text.graves.gui.previous_page'>";
            };
          };
          next_button = {
            base = {
              icon = {
                id = "universal_graves:icon";
                "Count" = 1;
                tag = { "Texture" = "next_page"; };
              };
              text = "<lang:'text.graves.gui.next_page'>";
            };
            alt = {
              icon = {
                id = "universal_graves:icon";
                "Count" = 1;
                tag = { "Texture" = "next_page_blocked"; };
              };
              text = "<dark_gray><lang:'text.graves.gui.next_page'>";
            };
          };
          remove_protection_button = {
            base = {
              icon = {
                id = "universal_graves:icon";
                "Count" = 1;
                tag = { "Texture" = "remove_protection"; };
              };
              text = "<red><lang:'text.graves.gui.remove_protection'>";
            };
            alt = {
              icon = {
                id = "universal_graves:icon";
                "Count" = 1;
                tag = { "Texture" = "remove_protection"; };
              };
              text = [
                "<red><lang:'text.graves.gui.remove_protection'>"
                "<dark_red><bold><lang:'text.graves.gui.cant_reverse'>"
                ""
                "<white><lang:'text.graves.gui.click_to_confirm'>"
              ];
            };
          };
          break_grave_button = {
            base = {
              icon = {
                id = "universal_graves:icon";
                "Count" = 1;
                tag = { "Texture" = "break_grave"; };
              };
              text = "<red><lang:'text.graves.gui.break_grave'>";
            };
            alt = {
              icon = {
                id = "universal_graves:icon";
                "Count" = 1;
                tag = { "Texture" = "break_grave"; };
              };
              text = [
                "<red><lang:'text.graves.gui.break_grave'>"
                "<dark_red><bold><lang:'text.graves.gui.cant_reverse'>"
                ""
                "<white><lang:'text.graves.gui.click_to_confirm'>"
              ];
            };
          };
          quick_pickup_button = {
            icon = {
              id = "universal_graves:icon";
              "Count" = 1;
              tag = { "Texture" = "quick_pickup"; };
            };
            text = "<red><lang:'text.graves.gui.quick_pickup'>";
          };
          fetch_button = {
            base = {
              icon = "minecraft:lead";
              text = "<yellow><lang:'text.graves.gui.fetch'>";
            };
            alt = {
              icon = "minecraft:lead";
              text = "<yellow><lang:'text.graves.gui.fetch'>";
            };
          };
          teleport_button = {
            base = {
              icon = "minecraft:ender_pearl";
              text = [
                "<#a52dfa><lang:'text.graves.gui.teleport'>"
                "<white><lang:'text.graves.gui.cost'> <#cfcfcf>\${cost}"
              ];
            };
            alt = {
              icon = "minecraft:ender_pearl";
              text = [
                "<dark_gray><lang:'text.graves.gui.teleport'>"
                "<white><lang:'text.graves.gui.cost'> <#cfcfcf>\${cost} <gray>(<red><lang:'text.graves.gui.cost.not_enough'></red>)"
              ];
            };
          };
          back_button = {
            icon = "minecraft:structure_void";
            text = "<red><lang:'text.graves.gui.quick_pickup'>";
          };
          bar = {
            icon = "minecraft:white_stained_glass_pane";
            text = "";
          };
        };
      description = "Full UI config attrset. Replace the entire section to customize button layouts and text.";
    };

    text = lib.mkOption {
      type = lib.types.attrs;
      default = {
          grave_created = "<white><lang:'text.graves.created_at_expire':'<yellow>\${position}':'<gray>\${world}':'<red>\${break_time}'>";
          protection_ended = "<red><lang:'text.graves.no_longer_protected':'<gold>\${position}':'<white>\${world}':'<yellow>\${item_count}'>";
          grave_expired = "<red><lang:'text.graves.expired':'<gold>\${position}':'<white>\${world}':'<yellow>\${item_count}'>";
          grave_broken = "<gray><lang:'text.graves.somebody_broke':'<white>\${position}':'<white>\${world}':'<white>\${item_count}'>";
          grave_access_payment_no_access = "<red><lang:'text.graves.grave_unlock_payment.no_access'>";
          grave_payment_accepted = "<white><lang:'text.graves.grave_unlock_payment.accepted'>";
          grave_payment_failed = "<red><lang:'text.graves.grave_unlock_payment.failed':'<yellow>\${cost}'>";
          years_suffix = "y";
          days_suffix = "d";
          hours_suffix = "h";
          minutes_suffix = "m";
          seconds_suffix = "s";
          infinity = "\u221e";
          date_format = "dd.MM.yyyy, HH:mm";
          world_names = {};
        };
    };

    extraConfig = lib.mkOption { type = lib.types.attrs; default = {}; };
  };

  config.files = lib.mkIf cfg.enable {
    "universal-graves/config.json" = fmt.generate "config.json"
      (lib.recursiveUpdate {
        _comment = "Before changing anything, see https://github.com/Patbox/UniversalGraves#configuration";
        config_version = cfg.configVersion;
        protection = {
          non_owner_protection_time = cfg.protection.nonOwnerProtectionTime;
          self_destruction_time = cfg.protection.selfDestructionTime;
          drop_items_on_expiration = cfg.protection.dropItemsOnExpiration;
          attackers_bypass_protection = cfg.protection.attackersBypassProtection;
          use_real_time = cfg.protection.useRealTime;
        };
        interactions = {
          unlocking_cost = cfg.interactions.unlockingCost;
          give_death_compass = cfg.interactions.giveDeathCompass;
          enable_use_death_compass_to_open_gui = cfg.interactions.enableUseDeathCompassToOpenGui;
          enable_click_to_open_gui = cfg.interactions.enableClickToOpenGui;
          shift_and_use_quick_pickup = cfg.interactions.shiftAndUseQuickPickup;
          allow_remote_protection_removal = cfg.interactions.allowRemoteProtectionRemoval;
          allow_remote_breaking = cfg.interactions.allowRemoteBreaking;
          allow_remote_unlocking = cfg.interactions.allowRemoteUnlocking;
        };
        storage = {
          experience_type = cfg.storage.experienceType;
          "experience_percent:setting_value" = cfg.storage."experience_percent:setting_value";
          can_store_only_xp = cfg.storage.canStoreOnlyXp;
          alternative_experience_entity = cfg.storage.alternativeExperienceEntity;
          blocked_enchantments = cfg.storage.blockedEnchantments;
        };
        placement = {
          player_grave_limit = cfg.placement.playerGraveLimit;
          replace_any_block = cfg.placement.replaceAnyBlock;
          max_distance_from_source_location = cfg.placement.maxDistanceFromSourceLocation;
          shift_location_on_failure = cfg.placement.shiftLocationOnFailure;
          max_shift_tries = cfg.placement.maxShiftTries;
          max_shift_distance = cfg.placement.maxShiftDistance;
          generate_on_top_of_fluids = cfg.placement.generateOnTopOfFluids;
          generate_on_ground = cfg.placement.generateOnGround;
          create_gravestone_after_emptying = cfg.placement.createGravestoneAfterEmptying;
          restore_replaced_block_after_player_breaking = cfg.placement.restoreReplacedBlockAfterPlayerBreaking;
          cancel_creation_for_damage_types = cfg.placement.cancelCreationForDamageTypes;
          cancel_creation_for_ignored_attacker_types = cfg.placement.cancelCreationForIgnoredAttackerTypes;
          blocking_predicates = cfg.placement.blockingPredicates;
          block_in_protected_area = cfg.placement.blockInProtectedArea;
          blacklisted_worlds = cfg.placement.blacklistedWorlds;
          blacklisted_areas = cfg.placement.blacklistedAreas;
          creation_default_failure_text = cfg.placement.creationDefaultFailureText;
          creation_claim_failure_text = cfg.placement.creationClaimFailureText;
        };
        teleportation = {
          cost = cfg.teleportation.cost;
          required_time = cfg.teleportation.requiredTime;
          y_offset = cfg.teleportation.yOffset;
          invincibility_time = cfg.teleportation.invincibilityTime;
          allow_movement_while_waiting = cfg.teleportation.allowMovementWhileWaiting;
          text = cfg.teleportation.text;
        };
        model = {
          default = cfg.model.default;
          alternative = cfg.model.alternative;
          enable_geyser_workaround = cfg.model.enableGeyserWorkaround;
          gravestone_item_base = cfg.model.gravestoneItemBase;
          gravestone_item_nbt = cfg.model.gravestoneItemNbt;
        };
        ui = cfg.ui;
        text = cfg.text;
      } cfg.extraConfig);
  };
}
```

- [ ] **Write test in checks.nix**

Add to `checks.nix`:

```nix
  universalgraves-overrides = checkConfig "universalgraves-overrides"
    (evalWith { mods.universalgraves = { enable = true; storage."experience_percent:setting_value" = 50.0; placement.generateOnTopOfFluids = true; }; }).files."universal-graves/config.json"
    [ "\"experience_percent:setting_value\": 50.0" "\"generate_on_top_of_fluids\": true" ];
```

- [ ] **Step 2: Run check** `nix flake check` — Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add modules/mods/universalgraves.nix checks.nix
git commit -m "Add universalgraves mod config module"
```

---

## Task 19: frostiful module

One option per key, organized by section. Defaults are ns1010301 values. User module sets the 26 pebblehost overrides.

**Files:**
- Create: `modules/mods/frostiful.nix`

- [ ] **Step 1: Create modules/mods/frostiful.nix**

```nix
{ pkgs, lib, config, ... }:
let
  cfg = config.mods.frostiful;
  fmt = pkgs.formats.json {};
in {
  options.mods.frostiful = {
    enable = lib.mkEnableOption "frostiful mod config management";

    clientConfig = {
      frostOverlayStart = lib.mkOption { type = lib.types.float; default = 0.5; };
      doColdHeartOverlay = lib.mkOption { type = lib.types.bool; default = true; };
      renderDripParticles = lib.mkOption { type = lib.types.bool; default = true; };
      disableFrostOverlayWhenWearingFrostologyCloak = lib.mkOption { type = lib.types.bool; default = true; };
      shakeHandWhenShivering = lib.mkOption { type = lib.types.bool; default = true; };
      handShakeIntensity = lib.mkOption { type = lib.types.float; default = 1.0; };
    };

    updateConfig = {
      currentConfigVersion = lib.mkOption { type = lib.types.int; default = 2; };
      enableConfigUpdates = lib.mkOption { type = lib.types.bool; default = true; };
    };

    environmentConfig = {
      doDryBiomeNightFreezing = lib.mkOption { type = lib.types.bool; default = true; };
      nightTemperatureShift = lib.mkOption { type = lib.types.int; default = -1; };
      coldBiomeTemperatureChange = lib.mkOption { type = lib.types.int; default = -1; };
      freezingBiomeTemperatureChange = lib.mkOption { type = lib.types.int; default = -3; };
      rainWetnessIncrease = lib.mkOption { type = lib.types.int; default = 1; };
      touchingWaterWetnessIncrease = lib.mkOption { type = lib.types.int; default = 5; };
      dryRate = lib.mkOption { type = lib.types.int; default = 1; };
      onFireDryDate = lib.mkOption { type = lib.types.int; default = 50; };
      onFireWarmRate = lib.mkOption { type = lib.types.int; default = 50; };
      powderSnowFreezeRate = lib.mkOption { type = lib.types.int; default = 30; };
      warmthPerLightLevel = lib.mkOption { type = lib.types.int; default = 2; };
      minLightForWarmth = lib.mkOption { type = lib.types.int; default = 5; };
      ultrawarmWarmRate = lib.mkOption { type = lib.types.int; default = 15; };
      winterTemperatureShift = lib.mkOption { type = lib.types.int; default = -1; };
      isNightColdInSummer = lib.mkOption { type = lib.types.bool; default = false; };
    };

    combatConfig = {
      doChillagerPatrols = lib.mkOption { type = lib.types.bool; default = true; };
      straysCarryFrostArrows = lib.mkOption { type = lib.types.bool; default = true; };
      heatDrainPerLevel = lib.mkOption { type = lib.types.int; default = 210; };
      heatDrainEfficiency = lib.mkOption { type = lib.types.float; default = 0.5; };
      iceBreakerDamagePerLevel = lib.mkOption { type = lib.types.float; default = 1.0; };
      iceBreakerBaseDamage = lib.mkOption { type = lib.types.float; default = 3.0; };
      maxFrostSpellDistance = lib.mkOption { type = lib.types.float; default = 25.0; };
      frostWandCooldown = lib.mkOption { type = lib.types.int; default = 120; };
      frostWandRootTime = lib.mkOption { type = lib.types.int; default = 100; };
      frostologerHeatDrainPerTick = lib.mkOption { type = lib.types.int; default = 30; };
      packedSnowballFreezeAmount = lib.mkOption { type = lib.types.int; default = 500; };
      packedSnowballDamage = lib.mkOption { type = lib.types.float; default = 2.0; };
      packedSnowballVulnerableTypesDamage = lib.mkOption { type = lib.types.float; default = 5.0; };
      frostologerPassiveFreezingPerTick = lib.mkOption { type = lib.types.int; default = 2; };
      frostologerMaxPassiveFreezing = lib.mkOption { type = lib.types.float; default = 0.5; };
      biterFrostBiteMaxAmplifier = lib.mkOption { type = lib.types.int; default = 2; };
      chillagerFireDamageMultiplier = lib.mkOption { type = lib.types.float; default = 1.5; };
      frostologerIntolerableHeat = lib.mkOption { type = lib.types.int; default = 9; };
      furUpgradeTemplateGenerateChance = lib.mkOption { type = lib.types.float; default = 0.5; };
      skateUpgradeTemplateGenerateChance = lib.mkOption { type = lib.types.float; default = 0.33; };
    };

    freezingConfig = {
      doPassiveFreezing = lib.mkOption { type = lib.types.bool; default = true; };
      doWindSpawning = lib.mkOption { type = lib.types.bool; default = true; };
      windSpawnStrategy = lib.mkOption { type = lib.types.str; default = "POINT"; };
      spawnWindInAir = lib.mkOption { type = lib.types.bool; default = true; };
      windDestroysTorches = lib.mkOption { type = lib.types.bool; default = true; };
      doSnowPacking = lib.mkOption { type = lib.types.bool; default = true; };
      passiveFreezingTickInterval = lib.mkOption { type = lib.types.int; default = 1; };
      windSpawnCapPerSecond = lib.mkOption { type = lib.types.int; default = 15; };
      windSpawnRarity = lib.mkOption { type = lib.types.int; default = 750; };
      windSpawnRarityThunder = lib.mkOption { type = lib.types.int; default = 500; };
      maxPassiveFreezingPercent = lib.mkOption { type = lib.types.float; default = 1.0; };
      passiveFreezingWetnessScaleMultiplier = lib.mkOption { type = lib.types.float; default = 2.1; };
      soakPercentFromWaterPotion = lib.mkOption { type = lib.types.float; default = 0.5; };
      sunLichenHeatPerLevel = lib.mkOption { type = lib.types.int; default = 500; };
      sunLichenBurnTime = lib.mkOption { type = lib.types.int; default = 60; };
      campfireWarmthSearchRadius = lib.mkOption { type = lib.types.float; default = 10.0; };
      campfireWarmthTime = lib.mkOption { type = lib.types.int; default = 1200; };
      freezingWindFrost = lib.mkOption { type = lib.types.int; default = 160; };
      conduitPowerWarmthPerTick = lib.mkOption { type = lib.types.int; default = 12; };
      heatFromHotFloor = lib.mkOption { type = lib.types.int; default = 12; };
      shiverBelow = lib.mkOption { type = lib.types.float; default = -0.51; };
      shiverWarmth = lib.mkOption { type = lib.types.int; default = 1; };
      stopShiverWarmingBelowFoodLevel = lib.mkOption { type = lib.types.int; default = 10; };
      warmFoodWarmthTime = lib.mkOption { type = lib.types.int; default = 1200; };
      netheriteFrostResistance = lib.mkOption { type = lib.types.float; default = 0.5; };
    };

    icicleConfig = {
      iciclesFormInWeather = lib.mkOption { type = lib.types.bool; default = true; };
      becomeUnstableChance = lib.mkOption { type = lib.types.float; default = 0.05; };
      growChance = lib.mkOption { type = lib.types.float; default = 0.02; };
      growChanceDuringRain = lib.mkOption { type = lib.types.float; default = 0.09; };
      growChanceDuringThunder = lib.mkOption { type = lib.types.float; default = 0.15; };
      frostArrowFreezeAmount = lib.mkOption { type = lib.types.int; default = 1000; };
      thrownIcicleFreezeAmount = lib.mkOption { type = lib.types.int; default = 1500; };
      icicleCollisionFreezeAmount = lib.mkOption { type = lib.types.int; default = 3000; };
      maxLightLevelToForm = lib.mkOption { type = lib.types.int; default = 8; };
      minSkylightLevelToForm = lib.mkOption { type = lib.types.int; default = 11; };
      thrownIcicleDamage = lib.mkOption { type = lib.types.float; default = 1.0; };
      thrownIcicleExtraDamage = lib.mkOption { type = lib.types.float; default = 3.0; };
      thrownIcicleCooldown = lib.mkOption { type = lib.types.int; default = 10; };
    };

    extraConfig = lib.mkOption { type = lib.types.attrs; default = {}; };
  };

  config.files = lib.mkIf cfg.enable {
    "frostiful.json" = fmt.generate "frostiful.json"
      (lib.recursiveUpdate {
        clientConfig = { inherit (cfg.clientConfig)
          frostOverlayStart doColdHeartOverlay renderDripParticles
          disableFrostOverlayWhenWearingFrostologyCloak shakeHandWhenShivering handShakeIntensity; };
        updateConfig = { inherit (cfg.updateConfig) currentConfigVersion enableConfigUpdates; };
        environmentConfig = { inherit (cfg.environmentConfig)
          doDryBiomeNightFreezing nightTemperatureShift coldBiomeTemperatureChange
          freezingBiomeTemperatureChange rainWetnessIncrease touchingWaterWetnessIncrease
          dryRate onFireDryDate onFireWarmRate powderSnowFreezeRate warmthPerLightLevel
          minLightForWarmth ultrawarmWarmRate winterTemperatureShift isNightColdInSummer; };
        combatConfig = { inherit (cfg.combatConfig)
          doChillagerPatrols straysCarryFrostArrows heatDrainPerLevel heatDrainEfficiency
          iceBreakerDamagePerLevel iceBreakerBaseDamage maxFrostSpellDistance frostWandCooldown
          frostWandRootTime frostologerHeatDrainPerTick packedSnowballFreezeAmount
          packedSnowballDamage packedSnowballVulnerableTypesDamage frostologerPassiveFreezingPerTick
          frostologerMaxPassiveFreezing biterFrostBiteMaxAmplifier chillagerFireDamageMultiplier
          frostologerIntolerableHeat furUpgradeTemplateGenerateChance skateUpgradeTemplateGenerateChance; };
        freezingConfig = { inherit (cfg.freezingConfig)
          doPassiveFreezing doWindSpawning windSpawnStrategy spawnWindInAir windDestroysTorches
          doSnowPacking passiveFreezingTickInterval windSpawnCapPerSecond windSpawnRarity
          windSpawnRarityThunder maxPassiveFreezingPercent passiveFreezingWetnessScaleMultiplier
          soakPercentFromWaterPotion sunLichenHeatPerLevel sunLichenBurnTime campfireWarmthSearchRadius
          campfireWarmthTime freezingWindFrost conduitPowerWarmthPerTick heatFromHotFloor
          shiverBelow shiverWarmth stopShiverWarmingBelowFoodLevel warmFoodWarmthTime netheriteFrostResistance; };
        icicleConfig = { inherit (cfg.icicleConfig)
          iciclesFormInWeather becomeUnstableChance growChance growChanceDuringRain
          growChanceDuringThunder frostArrowFreezeAmount thrownIcicleFreezeAmount
          icicleCollisionFreezeAmount maxLightLevelToForm minSkylightLevelToForm
          thrownIcicleDamage thrownIcicleExtraDamage thrownIcicleCooldown; };
      } cfg.extraConfig);
  };
}
```

- [ ] **Write test in checks.nix**

Add to `checks.nix`:

```nix
  frostiful-overrides = checkConfig "frostiful-overrides"
    (evalWith { mods.frostiful = { enable = true; freezingConfig.doPassiveFreezing = false; freezingConfig.windSpawnRarity = 100000; }; }).files."frostiful.json"
    [ "\"doPassiveFreezing\": false" "\"windSpawnRarity\": 100000" ];
```

- [ ] **Step 2: Run check** `nix flake check` — Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add modules/mods/frostiful.nix checks.nix
git commit -m "Add frostiful mod config module"
```

---

## Task 20: scorchful module

Same approach as frostiful. One option per key, organized by section. Defaults are ns1010301 values.

**Files:**
- Create: `modules/mods/scorchful.nix`

- [ ] **Step 1: Create modules/mods/scorchful.nix**

```nix
{ pkgs, lib, config, ... }:
let
  cfg = config.mods.scorchful;
  fmt = pkgs.formats.json {};
in {
  options.mods.scorchful = {
    enable = lib.mkEnableOption "scorchful mod config management";

    updateConfig = {
      currentConfigVersion = lib.mkOption { type = lib.types.int; default = 4; };
      enableConfigUpdates = lib.mkOption { type = lib.types.bool; default = true; };
    };

    clientConfig = {
      doBurningHeartOverlay = lib.mkOption { type = lib.types.bool; default = true; };
      doSoakingOverlay = lib.mkOption { type = lib.types.bool; default = true; };
      doSunHatShading = lib.mkOption { type = lib.types.bool; default = true; };
      enableSoundTemperatureEffects = lib.mkOption { type = lib.types.bool; default = true; };
      enableWetDripParticles = lib.mkOption { type = lib.types.bool; default = true; };
      enableHeatStrokePostProcessing = lib.mkOption { type = lib.types.bool; default = true; };
      sunHatShadeOpacity = lib.mkOption { type = lib.types.float; default = 0.2; };
      enableSandstormParticles = lib.mkOption { type = lib.types.bool; default = true; };
      enableSandstormFog = lib.mkOption { type = lib.types.bool; default = true; };
      enableSandstormSounds = lib.mkOption { type = lib.types.bool; default = true; };
      sandStormParticleRenderDistance = lib.mkOption { type = lib.types.int; default = 20; };
      sandStormParticleRarity = lib.mkOption { type = lib.types.int; default = 60; };
      sandStormParticleVelocity = lib.mkOption { type = lib.types.float; default = -1.0; };
      sandStormFogStart = lib.mkOption { type = lib.types.float; default = 16.0; };
      sandStormFogEnd = lib.mkOption { type = lib.types.float; default = 64.0; };
    };

    heatingConfig = {
      doPassiveHeating = lib.mkOption { type = lib.types.bool; default = true; };
      passiveHeatingTickInterval = lib.mkOption { type = lib.types.int; default = 1; };
      maxPassiveHeatingScale = lib.mkOption { type = lib.types.float; default = 1.0; };
      enableTurtleArmorEffects = lib.mkOption { type = lib.types.bool; default = true; };
      coolingFromIce = lib.mkOption { type = lib.types.int; default = 12; };
      minSkyLightLevelForHeat = lib.mkOption { type = lib.types.int; default = 13; };
      heatFromSun = lib.mkOption { type = lib.types.int; default = 1; };
      scorchingBiomeHeatIncrease = lib.mkOption { type = lib.types.int; default = 1; };
      sunHatShadeTemperatureChange = lib.mkOption { type = lib.types.int; default = -1; };
      onFireWarmRate = lib.mkOption { type = lib.types.int; default = 24; };
      onFireWarmRateWithFireResistance = lib.mkOption { type = lib.types.int; default = 6; };
      inLavaWarmRate = lib.mkOption { type = lib.types.int; default = 24; };
      striderOutOfLavaCoolRate = lib.mkOption { type = lib.types.int; default = 24; };
      powderSnowCoolRate = lib.mkOption { type = lib.types.int; default = 24; };
      fireballHeat = lib.mkOption { type = lib.types.int; default = 1000; };
      defaultArmorHeatResistance = lib.mkOption { type = lib.types.float; default = -0.5; };
      veryHarmfulArmorHeatResistance = lib.mkOption { type = lib.types.float; default = -1.0; };
      protectiveArmorHeatResistance = lib.mkOption { type = lib.types.float; default = 0.5; };
      veryProtectiveArmorHeatResistance = lib.mkOption { type = lib.types.float; default = 1.0; };
      waterBreathingDurationPerTurtleArmorPieceSeconds = lib.mkOption { type = lib.types.int; default = 10; };
      lightLevelPerHeatInNether = lib.mkOption { type = lib.types.int; default = 4; };
      minLightLevelForHeatInNether = lib.mkOption { type = lib.types.int; default = 11; };
      blocksAboveLavaOceanPerHeatInNether = lib.mkOption { type = lib.types.int; default = 5; };
      maxHeatFromLavaOceanInNether = lib.mkOption { type = lib.types.int; default = 3; };
    };

    combatConfig = {
      fireBallThrownType = lib.mkOption { type = lib.types.str; default = "SMALL"; };
    };

    weatherConfig = {
      doSandPileAccumulation = lib.mkOption { type = lib.types.bool; default = true; };
      sandPileAccumulationHeight = lib.mkOption { type = lib.types.int; default = 1; };
      sandstormSlownessAmountPercent = lib.mkOption { type = lib.types.float; default = -0.3; };
    };

    thirstConfig = {
      temperatureFromWetness = lib.mkOption { type = lib.types.int; default = -6; };
      waterFromRefreshingFood = lib.mkOption { type = lib.types.int; default = 60; };
      waterFromSustainingFood = lib.mkOption { type = lib.types.int; default = 120; };
      waterFromHydratingFood = lib.mkOption { type = lib.types.int; default = 300; };
      waterFromParchingFood = lib.mkOption { type = lib.types.int; default = -120; };
      rehydrationDrinkSize = lib.mkOption { type = lib.types.int; default = 120; };
      soakingFromSplashPotions = lib.mkOption { type = lib.types.int; default = 300; };
      touchingWaterWetnessIncrease = lib.mkOption { type = lib.types.int; default = 1; };
      dryRate = lib.mkOption { type = lib.types.int; default = 1; };
      onFireDryDate = lib.mkOption { type = lib.types.int; default = 3; };
      humidBiomeSweatEfficiency = lib.mkOption { type = lib.types.float; default = 0.16666667; };
      maxRehydrationEfficiency = lib.mkOption { type = lib.types.float; default = 0.75; };
    };

    integrationConfig = lib.mkOption {
      type = lib.types.attrs;
      default = {
        dehydrationConfig = {
          minWaterLevelForSweat = 16;
          maxRehydrationWaterAddedPerLevel = 1;
        };
      };
    };

    extraConfig = lib.mkOption { type = lib.types.attrs; default = {}; };
  };

  config.files = lib.mkIf cfg.enable {
    "scorchful.json" = fmt.generate "scorchful.json"
      (lib.recursiveUpdate {
        updateConfig = { inherit (cfg.updateConfig) currentConfigVersion enableConfigUpdates; };
        clientConfig = { inherit (cfg.clientConfig)
          doBurningHeartOverlay doSoakingOverlay doSunHatShading enableSoundTemperatureEffects
          enableWetDripParticles enableHeatStrokePostProcessing sunHatShadeOpacity
          enableSandstormParticles enableSandstormFog enableSandstormSounds
          sandStormParticleRenderDistance sandStormParticleRarity sandStormParticleVelocity
          sandStormFogStart sandStormFogEnd; };
        heatingConfig = { inherit (cfg.heatingConfig)
          doPassiveHeating passiveHeatingTickInterval maxPassiveHeatingScale enableTurtleArmorEffects
          coolingFromIce minSkyLightLevelForHeat heatFromSun scorchingBiomeHeatIncrease
          sunHatShadeTemperatureChange onFireWarmRate onFireWarmRateWithFireResistance inLavaWarmRate
          striderOutOfLavaCoolRate powderSnowCoolRate fireballHeat defaultArmorHeatResistance
          veryHarmfulArmorHeatResistance protectiveArmorHeatResistance veryProtectiveArmorHeatResistance
          waterBreathingDurationPerTurtleArmorPieceSeconds lightLevelPerHeatInNether
          minLightLevelForHeatInNether blocksAboveLavaOceanPerHeatInNether maxHeatFromLavaOceanInNether; };
        combatConfig = { inherit (cfg.combatConfig) fireBallThrownType; };
        weatherConfig = { inherit (cfg.weatherConfig)
          doSandPileAccumulation sandPileAccumulationHeight sandstormSlownessAmountPercent; };
        thirstConfig = { inherit (cfg.thirstConfig)
          temperatureFromWetness waterFromRefreshingFood waterFromSustainingFood waterFromHydratingFood
          waterFromParchingFood rehydrationDrinkSize soakingFromSplashPotions touchingWaterWetnessIncrease
          dryRate onFireDryDate humidBiomeSweatEfficiency maxRehydrationEfficiency; };
        integrationConfig = cfg.integrationConfig;
      } cfg.extraConfig);
  };
}
```

- [ ] **Write test in checks.nix**

Add to `checks.nix`:

```nix
  scorchful-overrides = checkConfig "scorchful-overrides"
    (evalWith { mods.scorchful = { enable = true; heatingConfig.doPassiveHeating = false; weatherConfig.doSandPileAccumulation = false; }; }).files."scorchful.json"
    [ "\"doPassiveHeating\": false" "\"doSandPileAccumulation\": false" ];
```

- [ ] **Step 2: Run check** `nix flake check` — Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add modules/mods/scorchful.nix checks.nix
git commit -m "Add scorchful mod config module"
```

---

## Task 21: supplementaries module

Same approach. One option per key, organized by nested section. Defaults are ns1010301 values.

**Files:**
- Create: `modules/mods/supplementaries.nix`

- [ ] **Step 1: Create modules/mods/supplementaries.nix**

```nix
{ pkgs, lib, config, ... }:
let
  cfg = config.mods.supplementaries;
  fmt = pkgs.formats.json {};
in {
  options.mods.supplementaries = {
    enable = lib.mkEnableOption "supplementaries mod config management";

    redstone = {
      speakerBlock = lib.mkOption { type = lib.types.attrs; default = { enabled = true; narrator_enabled = true; max_text = 32; range = 64; }; };
      bellows = lib.mkOption { type = lib.types.attrs; default = { enabled = true; base_period = 78; power_scaling = 2.0; base_velocity_scaling = 5.0; range = 5; }; };
      springLauncher = lib.mkOption { type = lib.types.attrs; default = { enabled = true; velocity = 1.5; fall_height_required = 5; }; };
      endermanHead = lib.mkOption { type = lib.types.attrs; default = { enabled = true; drop_head = true; ticks_to_increase_power = 15; work_from_any_side = false; }; };
      turnTable = lib.mkOption { type = lib.types.attrs; default = { enabled = true; rotate_entities = true; shuffle_containers = true; }; };
      pulleyBlock = lib.mkOption { type = lib.types.attrs; default = { enabled = true; mineshaft_elevator = 0.035; }; };
      dispenserMinecart = lib.mkOption { type = lib.types.attrs; default = { enabled = true; adjust_projectile_angle = true; }; };
      faucet = lib.mkOption { type = lib.types.attrs; default = { enabled = true; spill_items = true; fill_entities_below = false; }; };
      crystalDisplay = lib.mkOption { type = lib.types.attrs; default = { enabled = true; chaining = true; }; };
      windVane = lib.mkOption { type = lib.types.bool; default = true; };
      clockBlock = lib.mkOption { type = lib.types.bool; default = true; };
      redstoneIlluminator = lib.mkOption { type = lib.types.bool; default = true; };
      crank = lib.mkOption { type = lib.types.bool; default = true; };
      cogBlock = lib.mkOption { type = lib.types.bool; default = true; };
      goldDoor = lib.mkOption { type = lib.types.bool; default = true; };
      goldTrapdoor = lib.mkOption { type = lib.types.bool; default = true; };
      lockBlock = lib.mkOption { type = lib.types.bool; default = true; };
      relayer = lib.mkOption { type = lib.types.bool; default = true; };
    };

    functional = {
      rope = lib.mkOption { type = lib.types.attrs; default = { block_side_attachment = true; slide_on_fall = true; rope_override = "supplementaries:rope"; horizontal_ropes = true; }; };
      jar = lib.mkOption { type = lib.types.attrs; default = { enabled = true; capacity = 12; drink_from_jar = false; drink_from_jar_item = false; jar_auto_detect = false; jar_capture = true; jar_cookies = true; jar_liquids = true; }; };
      cage = {
        enabled = lib.mkOption { type = lib.types.bool; default = true; };
        allowAllMobs = lib.mkOption { type = lib.types.bool; default = false; };
        cageAllowAllBabies = lib.mkOption { type = lib.types.bool; default = false; };
        cageAutoDetect = lib.mkOption { type = lib.types.bool; default = false; };
        persistentMobs = lib.mkOption { type = lib.types.bool; default = false; };
        healthThreshold = lib.mkOption { type = lib.types.int; default = 100; };
        requireTaming = lib.mkOption { type = lib.types.bool; default = true; };
      };
      safe = {
        enabled = lib.mkOption { type = lib.types.bool; default = true; };
        preventBreaking = lib.mkOption { type = lib.types.bool; default = false; };
        simpleSafes = lib.mkOption { type = lib.types.bool; default = false; };
      };
      sack = lib.mkOption { type = lib.types.attrs; default = { enabled = true; sack_penalty = true; sack_increment = 2; slots = 9; }; };
      bambooSpikes = lib.mkOption { type = lib.types.attrs; default = { enabled = true; tipped_spikes = true; player_loot = false; only_allow_harmful_effects = true; populate_creative_tab = true; }; };
      urn = {
        enabled = lib.mkOption { type = lib.types.bool; default = true; };
        critterSpawnChance = lib.mkOption { type = lib.types.float; default = 0.01; };
      };
      soap = lib.mkOption { type = lib.types.attrs; default = { enabled = true; clean_blacklist = [ "minecraft:glazed_terracotta" "botania:mystical_flower" "mna:chimerite_crystal" "botania:floating_flower" ",minecraft:mushroom" "botania:mushroom" "botania:tall_mystical_flower" "botania:petal_block" "morered:network_cable" "xycraft_world:glowing_shiny_aurey_block" "xycraft_world:shiny_aurey_block" "xycraft_world:rgb_lamp" "xycraft_world:glowing_rgb_viewer" "xycraft_world:glowing_matte_rgb_block" "xycraft_world:rgb_lamp_pole" ]; special_blocks = { "#alexscaves:cave_paintings" = "alexscaves:smooth_limestone"; "quark:dirty_glass_pane" = "minecraft:glass_pane"; "quark:dirty_glass" = "minecraft:glass"; }; }; };
      cannon = lib.mkOption { type = lib.types.attrs; default = { enabled = true; explode_tnt = "IGNITE"; fire_power = 0.6; fuse_time = 40; cooldown = 60; cannonball = { enabled = true; power_scaling = 3.5; break_radius = 1.1; }; music_disc_heave_ho = true; }; };
      present = lib.mkOption { type = lib.types.attrs; default = { enabled = true; trapped_present = true; }; };
      flax = lib.mkOption { type = lib.types.attrs; default = { enabled = true; }; };
      lumisene = lib.mkOption { type = lib.types.attrs; default = { enabled = true; lumisene_bottle = { enabled = true; flammable_duration = 300; glowing_duration = 200; }; flammable_from_lumisene_block_duration = 50; }; };
      fodder = lib.mkOption { type = lib.types.bool; default = true; };
      hourglass = lib.mkOption { type = lib.types.bool; default = true; };
    };

    building = {
      blackboard = lib.mkOption { type = lib.types.attrs; default = { enabled = true; colored_blackboard = false; interaction_mode = "BOTH"; }; };
      gravelBricks = lib.mkOption { type = lib.types.attrs; default = { enabled = true; }; };
      slidyBlock = lib.mkOption { type = lib.types.attrs; default = { enabled = true; speed = 0.125; }; };
      timberFrame = lib.mkOption { type = lib.types.attrs; default = { enabled = true; swap_on_shift = false; axes_strip = true; replace_daub = true; }; };
      ironGate = lib.mkOption { type = lib.types.attrs; default = { enabled = true; double_opening = true; "door-like_gates" = false; }; };
      itemShelf = lib.mkOption { type = lib.types.attrs; default = { enabled = true; climbable_shelves = false; }; };
      sugarCube = lib.mkOption { type = lib.types.attrs; default = { enabled = true; dissolve_in_rain = true; horse_speed_duration = 10; }; };
      planter = lib.mkOption { type = lib.types.attrs; default = { enabled = true; broken_by_sapling = false; rich_soil_planter = true; }; };
      noticeBoard = lib.mkOption { type = lib.types.attrs; default = { enabled = true; allow_any_item = false; gui = true; }; };
      pedestal = lib.mkOption { type = lib.types.attrs; default = { enabled = true; }; };
      ash = lib.mkOption { type = lib.types.attrs; default = { enabled = true; ash_from_fire_chance = 1.0; rain_wash_ash = true; }; };
      flag = lib.mkOption { type = lib.types.attrs; default = { enabled = true; stick_pole = true; pole_length = 16; }; };
      goblet = lib.mkOption { type = lib.types.attrs; default = { enabled = true; allow_drinking = true; }; };
      globe = lib.mkOption { type = lib.types.attrs; default = { enabled = true; sepia_globe = true; }; };
      signPost = lib.mkOption { type = lib.types.attrs; default = { enabled = true; way_sign = { show_distance_text = true; }; }; };
      daub = lib.mkOption { type = lib.types.attrs; default = { enabled = true; wattle_and_daub = true; }; };
      ashBricks = lib.mkOption { type = lib.types.attrs; default = { enabled = true; }; };
      hatStand = {
        enabled = lib.mkOption { type = lib.types.bool; default = true; };
        unrestricted = lib.mkOption { type = lib.types.bool; default = false; };
      };
      awning = lib.mkOption { type = lib.types.attrs; default = { enabled = true; slant = true; shift_through = true; angle = 69.44395478041653; }; };
      flowerBox = lib.mkOption { type = lib.types.attrs; default = { enabled = true; simple_mode = true; }; };
      netheriteDoors = lib.mkOption { type = lib.types.attrs; default = { door = true; trapdoor = true; }; };
      lapisBricks = lib.mkOption { type = lib.types.bool; default = true; };
      deepslateLamp = lib.mkOption { type = lib.types.bool; default = true; };
      endStoneLamp = lib.mkOption { type = lib.types.bool; default = true; };
      blackstoneLamp = lib.mkOption { type = lib.types.bool; default = true; };
      stoneLamp = lib.mkOption { type = lib.types.bool; default = true; };
      stoneTile = lib.mkOption { type = lib.types.bool; default = true; };
      blackstoneTile = lib.mkOption { type = lib.types.bool; default = true; };
      bunting = lib.mkOption { type = lib.types.bool; default = true; };
      sconce = lib.mkOption { type = lib.types.bool; default = true; };
      sconceLever = lib.mkOption { type = lib.types.bool; default = true; };
      pancake = lib.mkOption { type = lib.types.bool; default = true; };
      checkerBlock = lib.mkOption { type = lib.types.bool; default = true; };
      rakedGravel = lib.mkOption { type = lib.types.bool; default = true; };
      featherBlock = lib.mkOption { type = lib.types.bool; default = true; };
      statue = lib.mkOption { type = lib.types.bool; default = true; };
      doormat = lib.mkOption { type = lib.types.bool; default = true; };
      flintBlock = lib.mkOption { type = lib.types.bool; default = true; };
      fineWood = lib.mkOption { type = lib.types.bool; default = true; };
      candleHolder = lib.mkOption { type = lib.types.bool; default = true; };
      firePit = lib.mkOption { type = lib.types.bool; default = true; };
      wickerFence = lib.mkOption { type = lib.types.bool; default = true; };
    };

    tools = {
      quiver = {
        enabled = lib.mkOption { type = lib.types.bool; default = true; };
        useWithoutSlow = lib.mkOption { type = lib.types.bool; default = true; };
        slots = lib.mkOption { type = lib.types.int; default = 6; };
        quiverSkeletonSpawnChance = lib.mkOption { type = lib.types.float; default = 0.025; };
        quiverSkeletonSpawnAffectedByLocalDifficulty = lib.mkOption { type = lib.types.bool; default = true; };
        onlyWorksInCurio = lib.mkOption { type = lib.types.bool; default = false; };
        quiverPickup = lib.mkOption { type = lib.types.bool; default = true; };
      };
      lunchBasket = lib.mkOption { type = lib.types.attrs; default = { enabled = true; placeable = true; slots = 6; }; };
      sliceMap = lib.mkOption { type = lib.types.attrs; default = { enabled = true; range_multiplier = 0.25; }; };
      bubbleBlower = lib.mkOption { type = lib.types.attrs; default = { enabled = true; stasis_cost = 5; bubble_block = { lifetime = 1200; break_when_touched = true; feather_falling_prevents_breaking = true; }; }; };
      wrench = lib.mkOption { type = lib.types.attrs; default = { enabled = true; bypass_when_on = "MAIN_HAND"; }; };
      ropeArrow = lib.mkOption { type = lib.types.attrs; default = { enabled = true; capacity = 32; exclusive_to_crossbows = false; }; };
      flute = lib.mkOption { type = lib.types.attrs; default = { enabled = true; unbound_radius = 64; bound_distance = 64; }; };
      bomb = lib.mkOption { type = lib.types.attrs; default = { enabled = true; explosion_radius = 2.0; break_blocks = "WEAK"; bomb_fuse = 0; cooldown = true; blue_bomb = { explosion_radius = 5.15; break_blocks = "WEAK"; }; }; };
      slingshot = {
        enabled = lib.mkOption { type = lib.types.bool; default = true; };
        rangeMultiplier = lib.mkOption { type = lib.types.float; default = 1.0; };
        chargeTime = lib.mkOption { type = lib.types.int; default = 20; };
        stasisDeceleration = lib.mkOption { type = lib.types.float; default = 0.9625; };
        unrestrictedEndermanIntercept = lib.mkOption { type = lib.types.bool; default = true; };
        allowBuckets = lib.mkOption { type = lib.types.bool; default = true; };
        damageableDamage = lib.mkOption { type = lib.types.float; default = 0.5; };
        allowSplashPotions = lib.mkOption { type = lib.types.bool; default = false; };
        allowBombs = lib.mkOption { type = lib.types.bool; default = false; };
        allowFireCharges = lib.mkOption { type = lib.types.bool; default = false; };
        allowSnowballs = lib.mkOption { type = lib.types.bool; default = false; };
        allowEnderpearls = lib.mkOption { type = lib.types.bool; default = false; };
      };
      antiqueInk = lib.mkOption { type = lib.types.attrs; default = { enabled = true; }; };
      candy = lib.mkOption { type = lib.types.bool; default = true; };
      stasis = lib.mkOption { type = lib.types.bool; default = true; };
      altimeter = lib.mkOption { type = lib.types.bool; default = true; };
      confettiPopper = lib.mkOption { type = lib.types.bool; default = true; };
    };

    tweaks = {
      dragonBannerPattern = lib.mkOption { type = lib.types.attrs; default = { enabled = true; }; };
      shulkerHelmet = lib.mkOption { type = lib.types.attrs; default = { enabled = true; }; };
      goldenAppleDisenchant = {
        enabled = lib.mkOption { type = lib.types.bool; default = true; };
      };
      tradersOpenDoors = {
        enabled = lib.mkOption { type = lib.types.bool; default = true; };
      };
      dispenserTweaks = lib.mkOption { type = lib.types.attrs; default = { axe_strip = true; shoot_ender_pearls = true; extract_from_bundles = true; }; };
      throwableBricks = {
        enabled = lib.mkOption { type = lib.types.bool; default = true; };
      };
      placeableSticks = {
        sticks = lib.mkOption { type = lib.types.bool; default = true; };
        blazeRods = lib.mkOption { type = lib.types.bool; default = true; };
      };
      placeableGunpowder = lib.mkOption { type = lib.types.attrs; default = { enabled = true; speed = 2; spread_age = 2; }; };
      rakedGravel = lib.mkOption { type = lib.types.attrs; default = { enabled = true; }; };
      bottleXp = {
        enabled = lib.mkOption { type = lib.types.bool; default = false; };
        cost = lib.mkOption { type = lib.types.int; default = 2; };
        targetBlock = lib.mkOption { type = lib.types.str; default = ""; };
      };
      mapTweaks = lib.mkOption { type = lib.types.attrs; default = { random_adventurer_maps = true; random_adventurer_maps_select_random_structure = true; block_map_markers = true; death_marker = "WITH_COMPASS"; tinted_blocks_on_maps = true; }; };
      placeableBooks = {
        writtenBooks = lib.mkOption { type = lib.types.bool; default = true; };
        enabled = lib.mkOption { type = lib.types.bool; default = true; };
        mixedBooks = lib.mkOption { type = lib.types.bool; default = false; };
      };
      zombieHorse = lib.mkOption { type = lib.types.attrs; default = { zombie_horse_conversion = true; rotten_flesh = 64; rideable_underwater = true; zombie_horse_inverse_conversion = true; }; };
      noteblocksScaring = lib.mkOption { type = lib.types.attrs; default = { enabled = true; }; };
      badLuckTweaks = lib.mkOption { type = lib.types.attrs; default = { lightning_unluck = true; }; };
      itemLore = lib.mkOption { type = lib.types.attrs; default = { enabled = true; }; };
      susRecipes = lib.mkOption { type = lib.types.attrs; default = { enabled = true; }; };
      slimedEffect = lib.mkOption { type = lib.types.attrs; default = { enabled = true; throwable_slimeballs = true; hinders_jump = "NORMAL_DIFFICULTY"; duration = 300; chance_per_slime_size = 0.15; }; };
    };

    extraConfig = lib.mkOption { type = lib.types.attrs; default = {}; };
  };

  config.files = lib.mkIf cfg.enable {
    "supplementaries-common.json" = fmt.generate "supplementaries-common.json"
      (lib.recursiveUpdate {
        "#README" = "This config file does not support comments. To see them configure it in-game using YACL or Cloth Config";
        redstone = {
          speaker_block = cfg.redstone.speakerBlock;
          bellows = cfg.redstone.bellows;
          spring_launcher = cfg.redstone.springLauncher;
          enderman_head = cfg.redstone.endermanHead;
          turn_table = cfg.redstone.turnTable;
          pulley_block = cfg.redstone.pulleyBlock;
          dispenser_minecart = cfg.redstone.dispenserMinecart;
          faucet = cfg.redstone.faucet;
          crystal_display = cfg.redstone.crystalDisplay;
          wind_vane = cfg.redstone.windVane;
          clock_block = cfg.redstone.clockBlock;
          redstone_illuminator = cfg.redstone.redstoneIlluminator;
          crank = cfg.redstone.crank;
          cog_block = cfg.redstone.cogBlock;
          gold_door = cfg.redstone.goldDoor;
          gold_trapdoor = cfg.redstone.goldTrapdoor;
          lock_block = cfg.redstone.lockBlock;
          relayer = cfg.redstone.relayer;
        };
        functional = {
          rope = cfg.functional.rope;
          jar = cfg.functional.jar;
          cage = {
            enabled = cfg.functional.cage.enabled;
            allow_all_mobs = cfg.functional.cage.allowAllMobs;
            cage_allow_all_babies = cfg.functional.cage.cageAllowAllBabies;
            cage_auto_detect = cfg.functional.cage.cageAutoDetect;
            persistent_mobs = cfg.functional.cage.persistentMobs;
            health_threshold = cfg.functional.cage.healthThreshold;
            require_taming = cfg.functional.cage.requireTaming;
          };
          safe = {
            enabled = cfg.functional.safe.enabled;
            prevent_breaking = cfg.functional.safe.preventBreaking;
            simple_safes = cfg.functional.safe.simpleSafes;
          };
          sack = cfg.functional.sack;
          bamboo_spikes = cfg.functional.bambooSpikes;
          urn = {
            enabled = cfg.functional.urn.enabled;
            critter_spawn_chance = cfg.functional.urn.critterSpawnChance;
          };
          soap = cfg.functional.soap;
          cannon = cfg.functional.cannon;
          present = cfg.functional.present;
          flax = cfg.functional.flax;
          lumisene = cfg.functional.lumisene;
          fodder = cfg.functional.fodder;
          hourglass = cfg.functional.hourglass;
        };
        building = {
          blackboard = cfg.building.blackboard;
          gravel_bricks = cfg.building.gravelBricks;
          slidy_block = cfg.building.slidyBlock;
          timber_frame = cfg.building.timberFrame;
          iron_gate = cfg.building.ironGate;
          item_shelf = cfg.building.itemShelf;
          sugar_cube = cfg.building.sugarCube;
          planter = cfg.building.planter;
          notice_board = cfg.building.noticeBoard;
          pedestal = cfg.building.pedestal;
          ash = cfg.building.ash;
          flag = cfg.building.flag;
          goblet = cfg.building.goblet;
          globe = cfg.building.globe;
          sign_post = cfg.building.signPost;
          daub = cfg.building.daub;
          ash_bricks = cfg.building.ashBricks;
          hat_stand = {
            enabled = cfg.building.hatStand.enabled;
            unrestricted = cfg.building.hatStand.unrestricted;
          };
          awning = cfg.building.awning;
          flower_box = cfg.building.flowerBox;
          netherite_doors = cfg.building.netheriteDoors;
          lapis_bricks = cfg.building.lapisBricks;
          deepslate_lamp = cfg.building.deepslateLamp;
          end_stone_lamp = cfg.building.endStoneLamp;
          blackstone_lamp = cfg.building.blackstoneLamp;
          stone_lamp = cfg.building.stoneLamp;
          stone_tile = cfg.building.stoneTile;
          blackstone_tile = cfg.building.blackstoneTile;
          bunting = cfg.building.bunting;
          sconce = cfg.building.sconce;
          sconce_lever = cfg.building.sconceLever;
          pancake = cfg.building.pancake;
          checker_block = cfg.building.checkerBlock;
          raked_gravel = cfg.building.rakedGravel;
          feather_block = cfg.building.featherBlock;
          statue = cfg.building.statue;
          doormat = cfg.building.doormat;
          flint_block = cfg.building.flintBlock;
          fine_wood = cfg.building.fineWood;
          candle_holder = cfg.building.candleHolder;
          fire_pit = cfg.building.firePit;
          wicker_fence = cfg.building.wickerFence;
        };
        tools = {
          quiver = {
            enabled = cfg.tools.quiver.enabled;
            use_without_slow = cfg.tools.quiver.useWithoutSlow;
            slots = cfg.tools.quiver.slots;
            quiver_skeleton_spawn_chance = cfg.tools.quiver.quiverSkeletonSpawnChance;
            quiver_skeleton_spawn_affected_by_local_difficulty = cfg.tools.quiver.quiverSkeletonSpawnAffectedByLocalDifficulty;
            only_works_in_curio = cfg.tools.quiver.onlyWorksInCurio;
            quiver_pickup = cfg.tools.quiver.quiverPickup;
          };
          lunch_basket = cfg.tools.lunchBasket;
          slice_map = cfg.tools.sliceMap;
          bubble_blower = cfg.tools.bubbleBlower;
          wrench = cfg.tools.wrench;
          rope_arrow = cfg.tools.ropeArrow;
          flute = cfg.tools.flute;
          bomb = cfg.tools.bomb;
          slingshot = {
            enabled = cfg.tools.slingshot.enabled;
            range_multiplier = cfg.tools.slingshot.rangeMultiplier;
            charge_time = cfg.tools.slingshot.chargeTime;
            stasis_deceleration = cfg.tools.slingshot.stasisDeceleration;
            unrestricted_enderman_intercept = cfg.tools.slingshot.unrestrictedEndermanIntercept;
            allow_buckets = cfg.tools.slingshot.allowBuckets;
            damageable_damage = cfg.tools.slingshot.damageableDamage;
            allow_splash_potions = cfg.tools.slingshot.allowSplashPotions;
            allow_bombs = cfg.tools.slingshot.allowBombs;
            allow_fire_charges = cfg.tools.slingshot.allowFireCharges;
            allow_snowballs = cfg.tools.slingshot.allowSnowballs;
            allow_enderpearls = cfg.tools.slingshot.allowEnderpearls;
          };
          antique_ink = cfg.tools.antiqueInk;
          candy = cfg.tools.candy;
          stasis = cfg.tools.stasis;
          altimeter = cfg.tools.altimeter;
          confetti_popper = cfg.tools.confettiPopper;
        };
        tweaks = {
          dragon_banner_pattern = cfg.tweaks.dragonBannerPattern;
          shulker_helmet = cfg.tweaks.shulkerHelmet;
          golden_apple_disenchant = {
            enabled = cfg.tweaks.goldenAppleDisenchant.enabled;
          };
          traders_open_doors = {
            enabled = cfg.tweaks.tradersOpenDoors.enabled;
          };
          dispenser_tweaks = cfg.tweaks.dispenserTweaks;
          throwable_bricks = {
            enabled = cfg.tweaks.throwableBricks.enabled;
          };
          placeable_sticks = {
            sticks = cfg.tweaks.placeableSticks.sticks;
            blaze_rods = cfg.tweaks.placeableSticks.blazeRods;
          };
          placeable_gunpowder = cfg.tweaks.placeableGunpowder;
          raked_gravel = cfg.tweaks.rakedGravel;
          bottle_xp = {
            enabled = cfg.tweaks.bottleXp.enabled;
            cost = cfg.tweaks.bottleXp.cost;
            target_block = cfg.tweaks.bottleXp.targetBlock;
          };
          map_tweaks = cfg.tweaks.mapTweaks;
          placeable_books = {
            written_books = cfg.tweaks.placeableBooks.writtenBooks;
            enabled = cfg.tweaks.placeableBooks.enabled;
            mixed_books = cfg.tweaks.placeableBooks.mixedBooks;
          };
          zombie_horse = cfg.tweaks.zombieHorse;
          noteblocks_scare = cfg.tweaks.noteblocksScaring;
          bad_luck_tweaks = cfg.tweaks.badLuckTweaks;
          item_lore = cfg.tweaks.itemLore;
          sus_recipes = cfg.tweaks.susRecipes;
          slimed_effect = cfg.tweaks.slimedEffect;
        };
      } cfg.extraConfig);
  };
}
```

- [ ] **Write test in checks.nix**

Add to `checks.nix`:

```nix
  supplementaries-overrides = checkConfig "supplementaries-overrides"
    (evalWith { mods.supplementaries = { enable = true; functional.cage.allowAllMobs = true; building.hatStand.unrestricted = true; tweaks.bottleXp.enabled = true; }; }).files."supplementaries-common.json"
    [ "\"allow_all_mobs\": true" "\"unrestricted\": true" "\"bottle_xp\"" ];
```

- [ ] **Step 2: Run check** `nix flake check` — Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add modules/mods/supplementaries.nix checks.nix
git commit -m "Add supplementaries mod config module"
```

---

## Task 22: deeperdarker module

Explicit options for all keys in the `server` and `client` sections. No defaults/ file needed.

**Files:**
- Create: `modules/mods/deeperdarker.nix`

- [ ] **Step 1: Create modules/mods/deeperdarker.nix**

```nix
{ pkgs, lib, config, ... }:
let
  cfg = config.mods.deeperdarker;
  fmt = pkgs.formats.json {};
in {
  options.mods.deeperdarker = {
    enable = lib.mkEnableOption "deeper darker mod config management";

    server = {
      spawnSomethingFromAncientVaseChance = lib.mkOption { type = lib.types.float; default = 0.1599999964237213; };
      sculkLeechesFromAncientVaseChance = lib.mkOption { type = lib.types.float; default = 0.7; };
      geysersApplySlowFalling = lib.mkOption { type = lib.types.bool; default = false; };
      geyserLaunchVelocity = lib.mkOption { type = lib.types.float; default = 2.5; };
      portalMinWidth = lib.mkOption { type = lib.types.int; default = 2; };
      portalMinHeight = lib.mkOption { type = lib.types.int; default = 2; };
      portalMaxWidth = lib.mkOption { type = lib.types.int; default = 48; };
      portalMaxHeight = lib.mkOption { type = lib.types.int; default = 24; };
      portalMinSearchHeight = lib.mkOption { type = lib.types.int; default = 2; };
      portalMaxSearchHeight = lib.mkOption { type = lib.types.int; default = 122; };
      generatedPortalWidth = lib.mkOption { type = lib.types.int; default = 8; };
      generatedPortalHeight = lib.mkOption { type = lib.types.int; default = 4; };
      sonorousStaffDamage = lib.mkOption { type = lib.types.float; default = 50.0; };
      sonorousStaffKnockback = lib.mkOption { type = lib.types.float; default = 1.0; };
      sonorousStaffCooldown = lib.mkOption { type = lib.types.int; default = 20; };
      sonorousStaffRange = lib.mkOption { type = lib.types.int; default = 40; };
      soulElytraCooldown = lib.mkOption { type = lib.types.int; default = 600; };
      soulElytraBoostStrength = lib.mkOption { type = lib.types.float; default = 2.0; };
      snapperDropLimit = lib.mkOption { type = lib.types.int; default = 8; };
      createCompatibility = lib.mkOption { type = lib.types.bool; default = true; };
      showMeYourSkinCompatibility = lib.mkOption { type = lib.types.bool; default = true; };
      addWardenDrops = lib.mkOption { type = lib.types.bool; default = true; };
      addAncientCityLoot = lib.mkOption { type = lib.types.bool; default = true; };
    };

    client = {
      renderWardenHelmetHorns = lib.mkOption { type = lib.types.bool; default = true; };
      wardenHeartPulses = lib.mkOption { type = lib.types.bool; default = true; };
      changePhantomTextures = lib.mkOption { type = lib.types.bool; default = true; };
      paintingFix = lib.mkOption { type = lib.types.bool; default = true; };
      sculkTransmitterLinkCooldownSeconds = lib.mkOption { type = lib.types.int; default = 3; };
    };

    extraConfig = lib.mkOption { type = lib.types.attrs; default = {}; };
  };

  config.files = lib.mkIf cfg.enable {
    "deeperdarker.json5" = fmt.generate "deeperdarker.json5"
      (lib.recursiveUpdate {
        server = { inherit (cfg.server)
          spawnSomethingFromAncientVaseChance sculkLeechesFromAncientVaseChance
          geysersApplySlowFalling geyserLaunchVelocity portalMinWidth portalMinHeight
          portalMaxWidth portalMaxHeight portalMinSearchHeight portalMaxSearchHeight
          generatedPortalWidth generatedPortalHeight sonorousStaffDamage sonorousStaffKnockback
          sonorousStaffCooldown sonorousStaffRange soulElytraCooldown soulElytraBoostStrength
          snapperDropLimit createCompatibility showMeYourSkinCompatibility addWardenDrops addAncientCityLoot; };
        client = { inherit (cfg.client)
          renderWardenHelmetHorns wardenHeartPulses changePhantomTextures paintingFix
          sculkTransmitterLinkCooldownSeconds; };
      } cfg.extraConfig);
  };
}
```

- [ ] **Write test in checks.nix**

Add to `checks.nix`:

```nix
  deeperdarker-overrides = checkConfig "deeperdarker-overrides"
    (evalWith { mods.deeperdarker = { enable = true; server.spawnSomethingFromAncientVaseChance = 10.0; server.sonorousStaffDamage = 10.0; }; }).files."deeperdarker.json5"
    [ "\"spawnSomethingFromAncientVaseChance\": 10.0" "\"sonorousStaffDamage\": 10.0" ];
```

- [ ] **Step 2: Run check** `nix flake check` — Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add modules/mods/deeperdarker.nix checks.nix
git commit -m "Add deeperdarker mod config module"
```

---

## Task 23: origins module

The origins module uses `enableOriginsPlusPlus` to opt-in to all origins-plus-plus origins. Vanilla origins are built-in defaults. OPP origins are conditionally added via `lib.mkIf`. All origin defaults use `lib.mkDefault` so users can override any origin or power with a plain assignment.

**Files:**
- Create: `modules/mods/origins.nix`

- [ ] **Step 1: Create modules/mods/origins.nix**

```nix
{ pkgs, lib, config, ... }:
let
  cfg = config.mods.origins;
  fmt = pkgs.formats.json {};

  oppOrigins = [
    "origins-plus-plus:land_shark"
    "origins-plus-plus:dullahan"
    "origins-plus-plus:demi_god"
    "origins-plus-plus:wizard"
    "origins-plus-plus:ravager"
    "origins-plus-plus:technomancer"
    "origins-plus-plus:spirit_ram"
    "origins-plus-plus:dolphin"
    "origins-plus-plus:glacier"
    "origins-plus-plus:voidling/voidling"
    "origins-plus-plus:devine_architect"
    "origins-plus-plus:raptus"
    "origins-plus-plus:wailing_one"
    "origins-plus-plus:manipulator"
    "origins-plus-plus:sunken_sailor"
    "origins-plus-plus:blazian"
    "origins-plus-plus:alien_axolotl"
    "origins-plus-plus:binturong"
    "origins-plus-plus:withered_skeletian"
    "origins-plus-plus:panoptican"
    "origins-plus-plus:rift_mage"
    "origins-plus-plus:drakonwither"
    "origins-plus-plus:chimaera"
    "origins-plus-plus:golden_golem"
    "origins-plus-plus:ignisian"
    "origins-plus-plus:magmean"
    "origins-plus-plus:light_mage"
    "origins-plus-plus:thornling"
    "origins-plus-plus:earth_spirit"
    "origins-plus-plus:ryu"
    "origins-plus-plus:vishaichian"
    "origins-plus-plus:pixie"
    "origins-plus-plus:dark_mage"
    "origins-plus-plus:end_mage"
    "origins-plus-plus:ebon_wing"
    "origins-plus-plus:ram"
    "origins-plus-plus:deranged"
    "origins-plus-plus:shroomling"
    "origins-plus-plus:rat"
    "origins-plus-plus:beaver"
    "origins-plus-plus:half_wither"
    "origins-plus-plus:voidling/voidborne"
    "origins-plus-plus:red_panda"
    "origins-plus-plus:sporeling"
    "origins-plus-plus:witch_of_ink"
    "origins-plus-plus:boarling"
    "origins-plus-plus:insect"
    "origins-plus-plus:candyperson"
    "origins-plus-plus:spectre"
    "origins-plus-plus:sand_walker"
    "origins-plus-plus:ninetails"
    "origins-plus-plus:shadow"
    "origins-plus-plus:goolien"
    "origins-plus-plus:shifter"
    "origins-plus-plus:wandering_spirit"
    "origins-plus-plus:mountain_goat"
    "origins-plus-plus:calamitous_rogue"
    "origins-plus-plus:zero_aizawa"
    "origins-plus-plus:iceling"
    "origins-plus-plus:part_robot"
    "origins-plus-plus:enigma"
    "origins-plus-plus:illusioner/illusioner_novice"
    "origins-plus-plus:sprinter"
    "origins-plus-plus:giant"
    "origins-plus-plus:deathsworn"
    "origins-plus-plus:jellyfish"
    "origins-plus-plus:wanderer"
    "origins-plus-plus:fallen_angel"
    "origins-plus-plus:flea"
    "origins-plus-plus:felvaxian"
    "origins-plus-plus:voidling/supreme_voidborne"
    "origins-plus-plus:soul_seer"
    "origins-plus-plus:mothling"
    "origins-plus-plus:earth_spirit_two"
    "origins-plus-plus:lost_draconian"
    "origins-plus-plus:kelperet"
    "origins-plus-plus:kirin"
    "origins-plus-plus:lunar_path"
    "origins-plus-plus:artificial_construct"
    "origins-plus-plus:stargazer"
    "origins-plus-plus:void_samurai"
    "origins-plus-plus:illusioner/illusioner_apprentice"
    "origins-plus-plus:marshmallow"
    "origins-plus-plus:warper"
    "origins-plus-plus:wyverian"
    "origins-plus-plus:withered_fox"
    "origins-plus-plus:ice_king"
    "origins-plus-plus:ghast"
    "origins-plus-plus:reign_farmer"
    "origins-plus-plus:hellforged"
    "origins-plus-plus:war_god"
    "origins-plus-plus:child_of_cthulhu"
    "origins-plus-plus:mouse"
    "origins-plus-plus:blob"
    "origins-plus-plus:frog"
    "origins-plus-plus:automaton"
    "origins-plus-plus:illusioner/illusioner_master"
    "origins-plus-plus:ice_porcupine"
    "origins-plus-plus:bedrockean"
    "origins-plus-plus:cobra"
    "origins-plus-plus:emblazing_warrior"
    "origins-plus-plus:warforged"
    "origins-plus-plus:copper_golem"
    "origins-plus-plus:shadow_crawler"
    "origins-plus-plus:gnoll"
    "origins-plus-plus:warden"
    "origins-plus-plus:corrupted_wither"
    "origins-plus-plus:craftsman"
    "origins-plus-plus:moth"
    "origins-plus-plus:broodmother"
    "origins-plus-plus:snake"
  ];
in {
  options.mods.origins = {
    enable = lib.mkEnableOption "origins mod config management";

    performVersionCheck = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };

    enableOriginsPlusPlus = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        When true, adds all origins-plus-plus origins with enabled = true (via lib.mkDefault).
        Individual origins can still be disabled: origins."origins-plus-plus:land_shark".enabled = false;
      '';
    };

    origins = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        freeformType = lib.types.attrsOf lib.types.bool;
        options.enabled = lib.mkOption {
          type = lib.types.bool;
          default = true;
        };
      });
      default = {};
      description = ''
        Per-origin configuration keyed by origin ID (e.g. "origins:merling").
        Defaults include all 10 vanilla origins with all powers enabled.
        Only specify entries you want to change.
        To disable an origin: origins."origins:merling".enabled = false;
        To disable a single power: origins."origins:enderian"."origins:throw_ender_pearl" = false;
      '';
    };

    extraConfig = lib.mkOption { type = lib.types.attrs; default = {}; };
  };

  config = lib.mkMerge [
    # Vanilla origins defaults
    {
      mods.origins.origins = {
        "origins:elytrian" = lib.mapAttrs (_: lib.mkDefault) {
          enabled = true;
          "origins:elytra" = true;
          "origins:launch_into_air" = true;
          "origins:aerial_combatant" = true;
          "origins:light_armor" = true;
          "origins:claustrophobia" = true;
          "origins:more_kinetic_damage" = true;
        };
        "origins:blazeborn" = lib.mapAttrs (_: lib.mkDefault) {
          enabled = true;
          "origins:fire_immunity" = true;
          "origins:nether_spawn" = true;
          "origins:burning_wrath" = true;
          "origins:hotblooded" = true;
          "origins:water_vulnerability" = true;
          "origins:flame_particles" = true;
          "origins:damage_from_snowballs" = true;
          "origins:damage_from_potions" = true;
          "thermoo-patches:heat_immune" = true;
          "thermoo-patches:cold_vulnerability" = true;
        };
        "origins:enderian" = lib.mapAttrs (_: lib.mkDefault) {
          enabled = true;
          "origins:throw_ender_pearl" = true;
          "origins:water_vulnerability" = true;
          "origins:pumpkin_hate" = true;
          "origins:extra_reach" = true;
          "origins:ender_particles" = true;
          "origins:damage_from_potions" = true;
        };
        "origins:phantom" = lib.mapAttrs (_: lib.mkDefault) {
          enabled = true;
          "origins:phantomize" = true;
          "origins:translucent" = true;
          "origins:phasing" = true;
          "origins:invisibility" = true;
          "origins:burn_in_daylight" = true;
          "origins:hunger_over_time" = true;
          "origins:fragile" = true;
          "origins:phantomize_overlay" = true;
        };
        "origins:avian" = lib.mapAttrs (_: lib.mkDefault) {
          enabled = true;
          "origins:slow_falling" = true;
          "origins:fresh_air" = true;
          "origins:like_air" = true;
          "origins:tailwind" = true;
          "origins:lay_eggs" = true;
          "origins:vegetarian" = true;
        };
        "origins:shulk" = lib.mapAttrs (_: lib.mkDefault) {
          enabled = true;
          "origins:shulker_inventory" = true;
          "origins:natural_armor" = true;
          "origins:strong_arms" = true;
          "origins:strong_arms_break_speed" = true;
          "origins:no_shield" = true;
          "origins:more_exhaustion" = true;
        };
        "origins:merling" = lib.mapAttrs (_: lib.mkDefault) {
          enabled = true;
          "origins:water_breathing" = true;
          "origins:water_vision" = true;
          "origins:aqua_affinity" = true;
          "origins:swim_speed" = true;
          "origins:like_water" = true;
          "origins:aquatic" = true;
          "origins:conduit_power_on_land" = true;
          "origins:air_from_potions" = true;
          "mermod:fabulous_fins" = true;
        };
        "origins:feline" = lib.mapAttrs (_: lib.mkDefault) {
          enabled = true;
          "origins:fall_immunity" = true;
          "origins:sprint_jump" = true;
          "origins:velvet_paws" = true;
          "origins:nine_lives" = true;
          "origins:weak_arms" = true;
          "origins:scare_creepers" = true;
          "origins:cat_vision" = true;
        };
        "origins:human" = lib.mapAttrs (_: lib.mkDefault) {
          enabled = true;
        };
        "origins:arachnid" = lib.mapAttrs (_: lib.mkDefault) {
          enabled = true;
          "origins:climbing" = true;
          "origins:master_of_webs" = true;
          "origins:carnivore" = true;
          "origins:fragile" = true;
          "origins:arthropod" = true;
        };
      };
    }
    # Origins-plus-plus origins (when enabled)
    (lib.mkIf cfg.enableOriginsPlusPlus {
      mods.origins.origins = lib.genAttrs oppOrigins (_: {
        enabled = lib.mkDefault true;
      });
    })
    # File generation
    (lib.mkIf cfg.enable {
      files."origins/origins_server.json" = fmt.generate "origins_server.json"
        (lib.recursiveUpdate {
          performVersionCheck = cfg.performVersionCheck;
          origins = cfg.origins;
        } cfg.extraConfig);
    })
  ];
}
```

- [ ] **Step 2: Write tests in checks.nix**

Add to `checks.nix` (using `checkJsonPath` for robust JSON assertions):

```nix
  origins-disable = checkJsonPath "origins-disable-merling"
    (evalWith { mods.origins = { enable = true; origins."origins:merling".enabled = false; }; }).files."origins/origins_server.json"
    '.origins["origins:merling"].enabled'
    "false";

  origins-power-disable = checkJsonPath "origins-power-disable"
    (evalWith { mods.origins = { enable = true; origins."origins:enderian"."origins:throw_ender_pearl" = false; }; }).files."origins/origins_server.json"
    '.origins["origins:enderian"]["origins:throw_ender_pearl"]'
    "false";

  origins-opp-enabled = checkJsonPath "origins-opp-enabled"
    (evalWith { mods.origins = { enable = true; enableOriginsPlusPlus = true; }; }).files."origins/origins_server.json"
    '.origins["origins-plus-plus:land_shark"].enabled'
    "true";

  origins-opp-disabled-by-default = checkJsonPath "origins-opp-disabled-by-default"
    (evalWith { mods.origins = { enable = true; }; }).files."origins/origins_server.json"
    '.origins | has("origins-plus-plus:land_shark")'
    "false";
```

- [ ] **Step 3: Run check** `nix flake check` — Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add modules/mods/origins.nix checks.nix
git commit -m "Add origins mod config module with vanilla defaults and origins-plus-plus support"
```

---

## Task 24: archers module

One module per RPG Series mod. Each manages all config files for that mod. Items/weapons/armor use `attrsOf lib.types.attrs` with `lib.mkDefault` defaults populated from the source config files. Only archers and wizards have pebblehost overrides; the other RPG mods are identical between installs.

Default source: `/tmp/mellowcatfe-config-20260325/archers/`
Pebblehost overrides: `archers/items_v2.json` — armor buffed (3→6), armor_toughness added (0→3.0), knockback_resistance added (0→0.1)

**Files:**
- Create: `modules/mods/archers.nix`

- [ ] **Step 1: Read default and pebblehost config files**

```bash
# Read all archers config files
cat /tmp/mellowcatfe-config-20260325/archers/items_v2.json | jq -S .
cat /tmp/mellowcatfe-config-20260325/archers/tweaks.json | jq -S .
cat /tmp/mellowcatfe-config-20260325/archers/villages.json | jq -S .
# Compare items_v2.json (the only file with real diffs)
diff <(jq -S . /tmp/mellowcatfe-config-20260325/archers/items_v2.json) <(jq -S . /tmp/pebblehost-config/config/archers/items_v2.json)
```

- [ ] **Step 2: Create modules/mods/archers.nix**

Follow this pattern — adapt the exact options/defaults from the config files read in Step 1.

The module should:
- Have `enable` option
- Have `rangedWeapons`, `meleeWeapons`, `armorSets` options (all `attrsOf lib.types.attrs`)
- Have `tweaks` and `villages` options (`lib.types.attrs`)
- Have `extraConfig` escape hatches per file
- Set defaults via `lib.mkDefault` in a `config = lib.mkMerge [...]` block, populated from the mellowcatfe config files
- Generate `archers/items_v2.json`, `archers/tweaks.json`, `archers/villages.json` when enabled

Example structure (do NOT inline the full weapon data — read it from config files):

```nix
{ pkgs, lib, config, ... }:
let
  cfg = config.mods.archers;
  fmt = pkgs.formats.json {};
in {
  options.mods.archers = {
    enable = lib.mkEnableOption "archers mod config management";
    rangedWeapons = lib.mkOption { type = lib.types.attrsOf lib.types.attrs; default = {}; };
    meleeWeapons = lib.mkOption { type = lib.types.attrsOf lib.types.attrs; default = {}; };
    armorSets = lib.mkOption { type = lib.types.attrsOf lib.types.attrs; default = {}; };
    tweaks = lib.mkOption { type = lib.types.attrs; default = {}; };
    villages = lib.mkOption { type = lib.types.attrs; default = {}; };
    itemsExtraConfig = lib.mkOption { type = lib.types.attrs; default = {}; };
  };

  config = lib.mkMerge [
    {
      # Populate from /tmp/mellowcatfe-config-20260325/archers/items_v2.json
      mods.archers.rangedWeapons = lib.mapAttrs (_: lib.mkDefault) {
        # ... one entry per weapon from ranged_weapons in items_v2.json
      };
      mods.archers.meleeWeapons = lib.mapAttrs (_: lib.mkDefault) {
        # ... one entry per weapon from melee_weapons in items_v2.json
      };
      mods.archers.armorSets = lib.mapAttrs (_: lib.mkDefault) {
        # ... one entry per armor set from armor_sets in items_v2.json
      };
      # Populate from tweaks.json and villages.json
      mods.archers.tweaks = lib.mkDefault { /* ... from tweaks.json */ };
      mods.archers.villages = lib.mkDefault { /* ... from villages.json */ };
    }
    (lib.mkIf cfg.enable {
      files = {
        "archers/items_v2.json" = fmt.generate "archers-items_v2.json"
          (lib.recursiveUpdate {
            ranged_weapons = cfg.rangedWeapons;
            melee_weapons = cfg.meleeWeapons;
            armor_sets = cfg.armorSets;
          } cfg.itemsExtraConfig);
        "archers/tweaks.json" = fmt.generate "archers-tweaks.json" cfg.tweaks;
        "archers/villages.json" = fmt.generate "archers-villages.json" cfg.villages;
      };
    })
  ];
}
```

- [ ] **Step 3: Write test in checks.nix**

Add to `checks.nix`:

```nix
  archers-generates = checkConfig "archers-generates"
    (evalWith { mods.archers = { enable = true; }; }).files."archers/items_v2.json"
    [ "\"ranged_weapons\"" "\"armor_sets\"" ];
```

- [ ] **Step 4: Run check** `nix flake check` — Expected: PASS

- [ ] **Step 5: Commit** `git add modules/mods/archers.nix checks.nix && git commit -m "Add archers mod config module"`

---

## Task 25: wizards module

Default source: `/tmp/mellowcatfe-config-20260325/wizards/`
Pebblehost overrides: `wizards/items_v4.json` — significant balance overhaul across ~40 values (knockback resistance, armor toughness, armor values, attack speed, attack damage)

**Files:**
- Create: `modules/mods/wizards.nix`

- [ ] **Step 1: Read default and pebblehost config files**

```bash
cat /tmp/mellowcatfe-config-20260325/wizards/items_v4.json | jq -S .
cat /tmp/mellowcatfe-config-20260325/wizards/tweaks.json | jq -S .
cat /tmp/mellowcatfe-config-20260325/wizards/villages.json | jq -S .
diff <(jq -S . /tmp/mellowcatfe-config-20260325/wizards/items_v4.json) <(jq -S . /tmp/pebblehost-config/config/wizards/items_v4.json)
```

- [ ] **Step 2: Create modules/mods/wizards.nix**

Same pattern as archers.nix. Options: `weapons`, `armorSets` (both `attrsOf lib.types.attrs`), `tweaks`, `villages` (both `lib.types.attrs`), `itemsExtraConfig`. Generates `wizards/items_v4.json`, `wizards/tweaks.json`, `wizards/villages.json`. Defaults from mellowcatfe config files.

- [ ] **Step 3: Write test in checks.nix**

```nix
  wizards-generates = checkConfig "wizards-generates"
    (evalWith { mods.wizards = { enable = true; }; }).files."wizards/items_v4.json"
    [ "\"weapons\"" "\"armor_sets\"" ];
```

- [ ] **Step 4: Run check** `nix flake check` — Expected: PASS

- [ ] **Step 5: Commit** `git add modules/mods/wizards.nix checks.nix && git commit -m "Add wizards mod config module"`

---

## Task 26: paladins module

Default source: `/tmp/mellowcatfe-config-20260325/paladins/`
Pebblehost overrides: none (all 4 files identical between installs)

**Files:**
- Create: `modules/mods/paladins.nix`

- [ ] **Step 1: Read config files**

```bash
for f in items_v5.json shields.json tweaks.json villages.json; do
  echo "=== $f ===" && cat /tmp/mellowcatfe-config-20260325/paladins/$f | jq -S .
done
```

- [ ] **Step 2: Create modules/mods/paladins.nix**

Options: `weapons`, `armorSets`, `shields` (all `attrsOf lib.types.attrs`), `tweaks`, `villages` (`lib.types.attrs`), `itemsExtraConfig`, `shieldsExtraConfig`. Generates `paladins/items_v5.json`, `paladins/shields.json`, `paladins/tweaks.json`, `paladins/villages.json`. Defaults from mellowcatfe config files.

- [ ] **Step 3: Write test in checks.nix**

```nix
  paladins-generates = checkConfig "paladins-generates"
    (evalWith { mods.paladins = { enable = true; }; }).files."paladins/items_v5.json"
    [ "\"weapons\"" "\"armor_sets\"" ];
```

- [ ] **Step 4: Run check** `nix flake check` — Expected: PASS

- [ ] **Step 5: Commit** `git add modules/mods/paladins.nix checks.nix && git commit -m "Add paladins mod config module"`

---

## Task 27: rogues module

Default source: `/tmp/mellowcatfe-config-20260325/rogues/`
Pebblehost overrides: none (all 3 files identical between installs)

**Files:**
- Create: `modules/mods/rogues.nix`

- [ ] **Step 1: Read config files**

```bash
for f in items_v2.json tweaks.json villages.json; do
  echo "=== $f ===" && cat /tmp/mellowcatfe-config-20260325/rogues/$f | jq -S .
done
```

- [ ] **Step 2: Create modules/mods/rogues.nix**

Same pattern as archers.nix. Options: `weapons`, `armorSets` (both `attrsOf lib.types.attrs`), `tweaks`, `villages` (`lib.types.attrs`), `itemsExtraConfig`. Generates `rogues/items_v2.json`, `rogues/tweaks.json`, `rogues/villages.json`. Defaults from mellowcatfe config files.

- [ ] **Step 3: Write test in checks.nix**

```nix
  rogues-generates = checkConfig "rogues-generates"
    (evalWith { mods.rogues = { enable = true; }; }).files."rogues/items_v2.json"
    [ "\"weapons\"" "\"armor_sets\"" ];
```

- [ ] **Step 4: Run check** `nix flake check` — Expected: PASS

- [ ] **Step 5: Commit** `git add modules/mods/rogues.nix checks.nix && git commit -m "Add rogues mod config module"`

---

## Task 28: rpgseries module

Default source: `/tmp/mellowcatfe-config-20260325/rpg_series/`
Pebblehost overrides: `rpg_series/loot_v2.json` — loot tier changes (tier_0 → tier_2)
Note: `tag_cache.json` is auto-generated cache — excluded from management.

**Files:**
- Create: `modules/mods/rpgseries.nix`

- [ ] **Step 1: Read config files**

```bash
cat /tmp/mellowcatfe-config-20260325/rpg_series/loot_v2.json | jq -S .
diff <(jq -S . /tmp/mellowcatfe-config-20260325/rpg_series/loot_v2.json) <(jq -S . /tmp/pebblehost-config/config/rpg_series/loot_v2.json)
```

- [ ] **Step 2: Create modules/mods/rpgseries.nix**

Options: `injectors`, `regexInjectors` (both `attrsOf lib.types.attrs`), `extraConfig`. Generates `rpg_series/loot_v2.json`. Defaults from mellowcatfe config.

- [ ] **Step 3: Write test in checks.nix**

```nix
  rpgseries-generates = checkConfig "rpgseries-generates"
    (evalWith { mods.rpgseries = { enable = true; }; }).files."rpg_series/loot_v2.json"
    [ "\"injectors\"" ];
```

- [ ] **Step 4: Run check** `nix flake check` — Expected: PASS

- [ ] **Step 5: Commit** `git add modules/mods/rpgseries.nix checks.nix && git commit -m "Add rpgseries mod config module"`

---

## Task 29: spellengine module

Default source: `/tmp/mellowcatfe-config-20260325/spell_engine/`
Pebblehost overrides: none (both files identical between installs)

**Files:**
- Create: `modules/mods/spellengine.nix`

- [ ] **Step 1: Read config files**

```bash
cat /tmp/mellowcatfe-config-20260325/spell_engine/enchantments.json | jq -S .
cat /tmp/mellowcatfe-config-20260325/spell_engine/server.json5 | jq -S .
```

- [ ] **Step 2: Create modules/mods/spellengine.nix**

Options: `enchantments`, `server` (both `lib.types.attrs`), `enchantmentsExtraConfig`, `serverExtraConfig`. Generates `spell_engine/enchantments.json` and `spell_engine/server.json5` (JSON5 is a superset of JSON — generate as plain JSON). Defaults from mellowcatfe config.

- [ ] **Step 3: Write test in checks.nix**

```nix
  spellengine-generates = checkConfig "spellengine-generates"
    (evalWith { mods.spellengine = { enable = true; }; }).files."spell_engine/enchantments.json"
    [ "\"enchantments\"" ];
```

- [ ] **Step 4: Run check** `nix flake check` — Expected: PASS

- [ ] **Step 5: Commit** `git add modules/mods/spellengine.nix checks.nix && git commit -m "Add spellengine mod config module"`

---

## Task 30: spellpower module

Default source: `/tmp/mellowcatfe-config-20260325/spell_power/`
Pebblehost overrides: none (both files identical between installs)

**Files:**
- Create: `modules/mods/spellpower.nix`

- [ ] **Step 1: Read config files**

```bash
cat /tmp/mellowcatfe-config-20260325/spell_power/attributes.json | jq -S .
cat /tmp/mellowcatfe-config-20260325/spell_power/enchantments.json | jq -S .
```

- [ ] **Step 2: Create modules/mods/spellpower.nix**

Options: `attributes`, `enchantments` (both `lib.types.attrs`), `attributesExtraConfig`, `enchantmentsExtraConfig`. Generates `spell_power/attributes.json` and `spell_power/enchantments.json`. Defaults from mellowcatfe config.

- [ ] **Step 3: Write test in checks.nix**

```nix
  spellpower-generates = checkConfig "spellpower-generates"
    (evalWith { mods.spellpower = { enable = true; }; }).files."spell_power/attributes.json"
    [ "\"base_value\"" ];
```

- [ ] **Step 4: Run check** `nix flake check` — Expected: PASS

- [ ] **Step 5: Commit** `git add modules/mods/spellpower.nix checks.nix && git commit -m "Add spellpower mod config module"`

---

## Task 31: easymobfarm module

Format: `.cfg` (Java properties). Use `pkgs.writeText`.
Default source: `/tmp/mellowcatfe-config-20260325/easy_mob_farm/mob_farm.cfg`
Pebblehost override: `tier3progressionUpgradeSpeed=8` (default: 6)

**Files:**
- Create: `modules/mods/easymobfarm.nix`

- [ ] **Step 1: Create modules/mods/easymobfarm.nix**

```nix
{ pkgs, lib, config, ... }:
let
  cfg = config.mods.easymobfarm;
in {
  options.mods.easymobfarm = {
    enable = lib.mkEnableOption "easy mob farm mod config management";

    tier3progressionUpgradeSpeed = lib.mkOption {
      type = lib.types.int;
      default = 6;
    };

    extraLines = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = ''
        Additional key=value lines appended to mob_farm.cfg.
        Use for config keys not modeled as explicit options.
      '';
    };
  };

  config.files = lib.mkIf cfg.enable {
    "easy_mob_farm/mob_farm.cfg" = pkgs.writeText "mob_farm.cfg" (''
      #Mob Farm Configuration
      enforceLogicalTierProgression=false
      experienceDropChance=5
      farmProgressingTime=6000
      luckyDropFarmLuckPercentage=95
      progressingRequiresOwnerToBeOnline=false
      speedEnhancementUpgradeSpeed=6
      tier0progressionUpgradeSpeed=0
      tier1progressionUpgradeSpeed=2
      tier2progressionUpgradeSpeed=4
      tier3progressionUpgradeSpeed=${toString cfg.tier3progressionUpgradeSpeed}
    '' + lib.optionalString (cfg.extraLines != "") (cfg.extraLines + "\n"));
  };
}
```

- [ ] **Step 2: Write test in checks.nix**

Add to `checks.nix`:

```nix
  easymobfarm-overrides = checkConfig "easymobfarm-overrides"
    (evalWith { mods.easymobfarm = { enable = true; tier3progressionUpgradeSpeed = 8; }; }).files."easy_mob_farm/mob_farm.cfg"
    [ "tier3progressionUpgradeSpeed=8" ];
```

- [ ] **Step 3: Run check** `nix flake check` — Expected: PASS

- [ ] **Step 4: Commit** `git add modules/mods/easymobfarm.nix checks.nix && git commit -m "Add easymobfarm mod config module"`

---

## Task 32: Create mod-config.nix user module

Create the user module in `nix-configurations` with all pebblehost overrides applied.

**Files:**
- Create: `packages/minecraft/mod-config.nix` in `~/worktrees/cjlarose/nix-configurations/default`

- [ ] **Step 1: Create packages/minecraft/mod-config.nix**

```nix
{ lib, ... }: {
  mods.waystones = {
    enable = true;
    dimensionalWarp = "GLOBAL_ONLY";
    restrictRenameToOwner = true;
    minimumBaseXpCost = 1.0;
    waystoneXpCostMultiplier = 5.0;
    xpCostPerLeashed = 10;
  };

  mods.aether = {
    enable = true;
    showPatreonMessage = false;
  };

  mods.betterendisland = {
    enable = true;
    resummonedDragonDropsEgg = true;
  };

  mods.biomesoplenty = {
    enable = true;
    bopPrimaryOverworldRegionWeight = 8;
    bopOverworldRareRegionWeight = 4;
    bopSecondaryOverworldRegionWeight = 6;
  };

  mods.farmersdelight = {
    enable = true;
    cuttingBoardFortuneBonus = 0.2;
    richSoilBoostChance = 0.4;
  };

  mods.goblintraders = {
    enable = true;
    gruntNoiseInterval = 160;
  };

  mods.magnumtorch = {
    enable = true;
    diamondTorchVerticalRange = 64;
    diamondTorchShapeType = "CUBOID";
    amethystTorchShapeType = "CUBOID";
  };

  mods.perfectplushie = {
    enable = true;
    villageLootTableChance = 0.5;
  };

  mods.endsdelight = {
    enable = true;
  };

  mods.amendments = {
    enable = true;
    # Overrides populated from pebblehost diff — fill in after reading config files in Task 12
  };

  mods.bewitchment = {
    enable = true;
    enableCurses = false;
    altarDistributionRadius = 36;
  };

  mods.explorerscompass = {
    enable = true;
    allowTeleport = false;
    structureBlacklist = [ "minecraft:stronghold" "minecraft:buried_treasure" ];
  };

  mods.lootr = {
    enable = true;
    reportInvalidTables = false;
    blastResistant = true;
  };

  mods.mysticsbiomes = {
    enable = true;
    biomeRegionWeight = 6;
    rainbowChickenSpawnChance = 10;
  };

  mods.plushiebuddies = {
    enable = true;
    plushieCost = 5;
  };

  mods.ubesdelight = {
    enable = true;
    bakingMatFortuneBonus = 0.2;
  };

  mods.universalgraves = {
    enable = true;
    interactions.enableUseDeathCompassToOpenGui = false;
    storage."experience_percent:setting_value" = 50.0;
    storage.alternativeExperienceEntity = false;
    placement.generateOnTopOfFluids = true;
  };

  mods.frostiful = {
    enable = true;
    clientConfig.handShakeIntensity = 0.5;
    updateConfig.enableConfigUpdates = false;
    environmentConfig.doDryBiomeNightFreezing = false;
    environmentConfig.nightTemperatureShift = 0;
    environmentConfig.rainWetnessIncrease = 0;
    environmentConfig.touchingWaterWetnessIncrease = 3;
    combatConfig.iceBreakerBaseDamage = 1.0;
    combatConfig.frostologerHeatDrainPerTick = 20;
    combatConfig.packedSnowballFreezeAmount = 100;
    freezingConfig.doPassiveFreezing = false;
    freezingConfig.doWindSpawning = false;
    freezingConfig.windSpawnStrategy = "NONE";
    freezingConfig.spawnWindInAir = false;
    freezingConfig.windDestroysTorches = false;
    freezingConfig.doSnowPacking = false;
    freezingConfig.passiveFreezingTickInterval = 60;
    freezingConfig.windSpawnCapPerSecond = 1;
    freezingConfig.windSpawnRarity = 100000;
    freezingConfig.windSpawnRarityThunder = 1000;
    freezingConfig.campfireWarmthSearchRadius = 16.0;
    freezingConfig.campfireWarmthTime = 3600;
    freezingConfig.conduitPowerWarmthPerTick = 20;
    freezingConfig.shiverWarmth = 2;
    freezingConfig.warmFoodWarmthTime = 3600;
    freezingConfig.netheriteFrostResistance = 3.0;
    icicleConfig.becomeUnstableChance = 0.01;
  };

  mods.scorchful = {
    enable = true;
    updateConfig.enableConfigUpdates = false;
    clientConfig.enableSandstormFog = false;
    heatingConfig.doPassiveHeating = false;
    heatingConfig.passiveHeatingTickInterval = 60;
    heatingConfig.maxPassiveHeatingScale = 0.5;
    heatingConfig.defaultArmorHeatResistance = 1.0;
    heatingConfig.veryHarmfulArmorHeatResistance = -0.5;
    heatingConfig.protectiveArmorHeatResistance = 1.5;
    heatingConfig.veryProtectiveArmorHeatResistance = 3.0;
    heatingConfig.blocksAboveLavaOceanPerHeatInNether = 10;
    weatherConfig.doSandPileAccumulation = false;
    weatherConfig.sandstormSlownessAmountPercent = -0.1;
    thirstConfig.temperatureFromWetness = -10;
    thirstConfig.waterFromParchingFood = -100;
    thirstConfig.touchingWaterWetnessIncrease = 5;
  };

  mods.supplementaries = {
    enable = true;
    building.hatStand.unrestricted = true;
    functional.cage.allowAllMobs = true;
    functional.cage.cageAllowAllBabies = true;
    functional.cage.requireTaming = false;
    functional.safe.preventBreaking = true;
    functional.urn.critterSpawnChance = 0.05;
    tools.quiver.quiverSkeletonSpawnAffectedByLocalDifficulty = false;
    tools.slingshot.allowBuckets = false;
    tools.slingshot.allowEnderpearls = true;
    tools.slingshot.allowSplashPotions = true;
    tweaks.bottleXp.enabled = true;
    tweaks.goldenAppleDisenchant.enabled = false;
    tweaks.placeableBooks.mixedBooks = true;
    tweaks.placeableSticks.blazeRods = false;
    tweaks.placeableSticks.sticks = false;
    tweaks.throwableBricks.enabled = false;
    tweaks.tradersOpenDoors.enabled = false;
  };

  mods.deeperdarker = {
    enable = true;
    server.spawnSomethingFromAncientVaseChance = 10.0;
    server.sculkLeechesFromAncientVaseChance = 1.0;
    server.sonorousStaffDamage = 10.0;
    server.sonorousStaffCooldown = 40;
  };

  mods.origins = {
    enable = true;
    enableOriginsPlusPlus = true;
    origins = lib.genAttrs [
      # Disabled vanilla origins
      "origins:enderian"
      "origins:arachnid"
      "origins:blazeborn"
      "origins:elytrian"
      # Non-vanilla non-OPP origins
      "extraorigins:piglin"
      "moborigins:snowgolem"
    ] (_: { enabled = false; })
    // lib.genAttrs [
      # All OPP origins disabled on pebblehost
      "origins-plus-plus:land_shark"
      "origins-plus-plus:dullahan"
      "origins-plus-plus:demi_god"
      "origins-plus-plus:wizard"
      "origins-plus-plus:ravager"
      "origins-plus-plus:technomancer"
      "origins-plus-plus:spirit_ram"
      "origins-plus-plus:dolphin"
      "origins-plus-plus:glacier"
      "origins-plus-plus:voidling/voidling"
      "origins-plus-plus:devine_architect"
      "origins-plus-plus:raptus"
      "origins-plus-plus:wailing_one"
      "origins-plus-plus:manipulator"
      "origins-plus-plus:sunken_sailor"
      "origins-plus-plus:blazian"
      "origins-plus-plus:alien_axolotl"
      "origins-plus-plus:binturong"
      "origins-plus-plus:withered_skeletian"
      "origins-plus-plus:panoptican"
      "origins-plus-plus:rift_mage"
      "origins-plus-plus:drakonwither"
      "origins-plus-plus:chimaera"
      "origins-plus-plus:golden_golem"
      "origins-plus-plus:ignisian"
      "origins-plus-plus:magmean"
      "origins-plus-plus:light_mage"
      "origins-plus-plus:thornling"
      "origins-plus-plus:earth_spirit"
      "origins-plus-plus:ryu"
      "origins-plus-plus:vishaichian"
      "origins-plus-plus:pixie"
      "origins-plus-plus:dark_mage"
      "origins-plus-plus:end_mage"
      "origins-plus-plus:ebon_wing"
      "origins-plus-plus:ram"
      "origins-plus-plus:deranged"
      "origins-plus-plus:shroomling"
      "origins-plus-plus:rat"
      "origins-plus-plus:beaver"
      "origins-plus-plus:half_wither"
      "origins-plus-plus:voidling/voidborne"
      "origins-plus-plus:red_panda"
      "origins-plus-plus:sporeling"
      "origins-plus-plus:witch_of_ink"
      "origins-plus-plus:boarling"
      "origins-plus-plus:insect"
      "origins-plus-plus:candyperson"
      "origins-plus-plus:spectre"
      "origins-plus-plus:sand_walker"
      "origins-plus-plus:ninetails"
      "origins-plus-plus:shadow"
      "origins-plus-plus:goolien"
      "origins-plus-plus:shifter"
      "origins-plus-plus:wandering_spirit"
      "origins-plus-plus:mountain_goat"
      "origins-plus-plus:calamitous_rogue"
      "origins-plus-plus:zero_aizawa"
      "origins-plus-plus:iceling"
      "origins-plus-plus:part_robot"
      "origins-plus-plus:enigma"
      "origins-plus-plus:illusioner/illusioner_novice"
      "origins-plus-plus:sprinter"
      "origins-plus-plus:giant"
      "origins-plus-plus:deathsworn"
      "origins-plus-plus:jellyfish"
      "origins-plus-plus:wanderer"
      "origins-plus-plus:fallen_angel"
      "origins-plus-plus:flea"
      "origins-plus-plus:felvaxian"
      "origins-plus-plus:voidling/supreme_voidborne"
      "origins-plus-plus:soul_seer"
      "origins-plus-plus:mothling"
      "origins-plus-plus:earth_spirit_two"
      "origins-plus-plus:lost_draconian"
      "origins-plus-plus:kelperet"
      "origins-plus-plus:kirin"
      "origins-plus-plus:lunar_path"
      "origins-plus-plus:artificial_construct"
      "origins-plus-plus:stargazer"
      "origins-plus-plus:void_samurai"
      "origins-plus-plus:illusioner/illusioner_apprentice"
      "origins-plus-plus:marshmallow"
      "origins-plus-plus:warper"
      "origins-plus-plus:wyverian"
      "origins-plus-plus:withered_fox"
      "origins-plus-plus:ice_king"
      "origins-plus-plus:ghast"
      "origins-plus-plus:reign_farmer"
      "origins-plus-plus:hellforged"
      "origins-plus-plus:war_god"
      "origins-plus-plus:child_of_cthulhu"
      "origins-plus-plus:mouse"
      "origins-plus-plus:blob"
      "origins-plus-plus:frog"
      "origins-plus-plus:automaton"
      "origins-plus-plus:illusioner/illusioner_master"
      "origins-plus-plus:ice_porcupine"
      "origins-plus-plus:bedrockean"
      "origins-plus-plus:cobra"
      "origins-plus-plus:emblazing_warrior"
      "origins-plus-plus:warforged"
      "origins-plus-plus:copper_golem"
      "origins-plus-plus:shadow_crawler"
      "origins-plus-plus:gnoll"
      "origins-plus-plus:warden"
      "origins-plus-plus:corrupted_wither"
      "origins-plus-plus:craftsman"
      "origins-plus-plus:moth"
      "origins-plus-plus:broodmother"
      "origins-plus-plus:snake"
    ] (_: { enabled = false; });
  };

  mods.archers = {
    enable = true;
    # Pebblehost overrides: armor buffed, toughness/knockback_resistance added
    # Populate exact override values from diff in Task 24 Step 1
  };

  mods.wizards = {
    enable = true;
    # Pebblehost overrides: significant balance changes across ~40 values
    # Populate exact override values from diff in Task 25 Step 1
  };

  mods.paladins.enable = true;   # No overrides — identical between installs
  mods.rogues.enable = true;     # No overrides — identical between installs
  mods.rpgseries = {
    enable = true;
    # Pebblehost overrides: loot tier changes (tier_0 → tier_2)
    # Populate exact override values from diff in Task 28 Step 1
  };
  mods.spellengine.enable = true;  # No overrides — identical between installs
  mods.spellpower.enable = true;   # No overrides — identical between installs

  mods.easymobfarm = {
    enable = true;
    tier3progressionUpgradeSpeed = 8;
  };
}
```

- [ ] **Step 2: Commit** (in nix-configurations repo)

```bash
cd ~/worktrees/cjlarose/nix-configurations/default
git add packages/minecraft/mod-config.nix
git commit -m "Add mellowcatfe mod-config.nix user module with pebblehost overrides"
```

---

## Task 33: Wire modConfigs into ns1010301 configuration.nix

**Context:** The flake wiring is already done in `nix-configurations`. `nix-minecraft-mod-config` is already declared as a `path:` input in `flake.nix`, passed through `nixos-configurations/default.nix`, threaded into `ns1010301/default.nix`, and forwarded to `configuration.nix` via the outer function call. You only need to modify the inner `{ pkgs, config, ... }:` block.

Read current file first: `nixos-configurations/ns1010301/configuration.nix`

Add a nested `let` block inside `{ pkgs, config, ... }:` to evaluate the module and build the configSymlinks attrset.

**Files:**
- Modify: `nixos-configurations/ns1010301/configuration.nix`

- [ ] **Step 1: Add modConfigs let binding and wire into symlinks**

In the inner `{ pkgs, config, ... }:` block, add after the existing `let`:

```nix
{ nixpkgs, sharedOverlays, stateVersion, system, additionalPackages, nix-minecraft, nix-minecraft-mod-config, ... }:
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
  # ... existing config ...
  services.minecraft-servers.servers.mellowcatfe.symlinks =
    { mods = "${additionalPackages.${system}.minecraft-modpack}/mods"; }
    // configSymlinks;
}
```

- [ ] **Step 2: Commit**

```bash
cd ~/worktrees/cjlarose/nix-configurations/default
git add nixos-configurations/ns1010301/configuration.nix
git commit -m "Wire mod config symlinks into ns1010301 mellowcatfe server"
```

---

## Task 34: Integration test — verify generated configs match pebblehost

- [ ] **Step 1: Copy pebblehost reference configs**

Copy the pebblehost config files into a test fixtures directory in `nix-configurations`:

```bash
mkdir -p ~/worktrees/cjlarose/nix-configurations/default/packages/minecraft/test-fixtures/pebblehost
```

For each config file generated by the mod modules, copy the corresponding pebblehost version:

```bash
cd ~/worktrees/cjlarose/nix-configurations/default/packages/minecraft/test-fixtures/pebblehost
# Copy from /tmp/pebblehost-config/config/ — one file per managed config
cp /tmp/pebblehost-config/config/waystones-common.toml .
cp /tmp/pebblehost-config/config/aether-common.toml .
# ... repeat for all managed config files
# For nested paths, preserve directory structure:
mkdir -p aether easy_mob_farm universal-graves origins biomesoplenty archers rpg_series wizards
cp /tmp/pebblehost-config/config/aether/aether_customizations.txt aether/
cp /tmp/pebblehost-config/config/easy_mob_farm/mob_farm.cfg easy_mob_farm/
# ... etc.
```

- [ ] **Step 2: Update nix-minecraft-mod-config lock in nix-configurations**

```bash
cd ~/worktrees/cjlarose/nix-configurations/default
nix flake update nix-minecraft-mod-config
```

- [ ] **Step 3: Dry-run build ns1010301**

```bash
nix build .#nixosConfigurations.ns1010301.config.system.build.toplevel --dry-run 2>&1 | tail -20
```
Expected: resolves derivations without errors, no "undefined variable" or type errors

- [ ] **Step 4: Build and compare generated configs against pebblehost reference**

Build the mod configs using the actual user module:

```bash
cd ~/worktrees/cjlarose/nix-configurations/default
nix build .#nixosConfigurations.ns1010301.config.services.minecraft-servers.servers.mellowcatfe.symlinks --no-link --print-out-paths
```

Or evaluate the mod configs directly in a nix repl/expression and compare each file:

```bash
# For each JSON config file, normalize with jq -S and diff:
diff <(jq -S . /path/to/generated/waystones-common.toml) <(jq -S . packages/minecraft/test-fixtures/pebblehost/waystones-common.toml)
```

For JSON files: normalize key ordering with `jq -S` before comparing.
For TOML files: use `remarshal` or `yj` (available in nixpkgs) to convert both to sorted JSON, then diff.
For cfg/txt files: direct diff (exact content match expected).

Any differences indicate either:
- A missing/incorrect option default in the mod module
- A missing override in mod-config.nix
- A formatting difference that needs investigation

Fix any discrepancies before proceeding.

- [ ] **Step 5: Commit**

```bash
cd ~/worktrees/cjlarose/nix-configurations/default
git add packages/minecraft/test-fixtures/ flake.lock
git commit -m "Add pebblehost reference configs and update nix-minecraft-mod-config lock"
```
