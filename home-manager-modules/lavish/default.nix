{ lib, config, ... }:

let
  cfg = config.cjlarose.lavish;
in
{
  options.cjlarose.lavish = {
    enable = lib.mkEnableOption ''
      the lavish-axi CLI (upstream kunchenguid/lavish-axi, built from source with
      telemetry disabled) and its Lavish Editor Claude Code skill. lavish-axi opens
      an agent-generated HTML artifact in a sandboxed browser for human annotation
      and ships the feedback back to the driving agent over a loopback server with
      a Host-header DNS-rebinding guard. Disabled by default; opt in per host/user.
      When enabled, set cjlarose.lavish.package to the built lavish-axi package
      (threaded in from the consuming flake)
    '';

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = ''
        The lavish-axi package to install (the flake's
        additionalPackages.<system>.lavish-axi, built from source in
        packages/lavish-axi). Carries the CLI at bin/lavish-axi and the generated
        Claude Code skill at share/lavish-axi/skill/SKILL.md. Threaded from the
        consuming flake rather than referenced directly so this shared module
        needs no flake inputs of its own (mirrors cjlarose.claude.mattpocock-skills).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.package != null;
        message = ''
          cjlarose.lavish.enable is true but cjlarose.lavish.package is unset.
          Set it to the built lavish-axi package from the consuming flake (e.g.
          additionalPackages.''${system}.lavish-axi).
        '';
      }
    ];

    # CLI on PATH. Under home-manager useUserPackages this rides the system
    # profile, so the picktrace VM needs a system switch-to-configuration to pick
    # it up (an HM-only activate won't), same as tuicr / the playwright closure.
    home.packages = [ cfg.package ];

    # The skill drives the on-PATH lavish-axi binary directly (never npx), so
    # nothing is fetched from npm at runtime. Single-file SKILL.md shipped in the
    # package's share/ output; raw home.file (like the upstream lavish-axi HM
    # module) so this doesn't depend on programs.claude-code being imported.
    home.file.".claude/skills/lavish/SKILL.md".source =
      "${cfg.package}/share/lavish-axi/skill/SKILL.md";
  };
}
