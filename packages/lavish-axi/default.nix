{ lib, stdenv, nodejs_22, pnpm, pnpmConfigHook, fetchPnpmDeps, makeWrapper, src, version }:

# Build the upstream lavish-axi CLI from source (kunchenguid/lavish-axi, pinned
# to a release tag as a flake=false input). scripts/build.js esbuilds
# bin/lavish-axi.js into dist/cli.mjs with `packages: external`, so the runtime
# dependencies (express, chokidar, open, axi-sdk-js, parse5, ...) resolve from a
# shipped node_modules rather than being fetched from npm at run time. The
# dependency closure is fixed-output (pnpm.fetchDeps + pinned hash), so the whole
# build is offline and reproducible — no npx / registry TOFU at run time.
#
# Telemetry: upstream ships src/telemetry.js (Umami), but it is a no-op unless a
# website ID is present. scripts/build.js bakes LAVISH_AXI_BUILD_UMAMI_WEBSITE_ID
# from $LAVISH_AXI_UMAMI_WEBSITE_ID, which is unset in this build env → an empty
# build-time ID → the runtime telemetry client resolves to NoopTelemetryClient.
# The wrapper additionally pins LAVISH_AXI_TELEMETRY=0 as a belt-and-suspenders
# runtime opt-out. Net: no telemetry beacons, matching the retired hardened fork.
stdenv.mkDerivation (finalAttrs: {
  pname = "lavish-axi";
  inherit version src;

  nativeBuildInputs = [ nodejs_22 pnpm pnpmConfigHook makeWrapper ];

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    fetcherVersion = 3;
    hash = "sha256-y4KeFqPF02TBSlP1mgyj5UFx0Q98ip890xYkBAYF4qY=";
  };

  buildPhase = ''
    runHook preBuild
    pnpm run build

    # --- Reverse-proxy patches (local; not upstream) --------------------------
    # We front lavish with a TLS-terminating nginx vhost on ns1010301
    # (lavish.ns1010301.cjlarose.dev:443 -> http://127.0.0.1:4387). Two edits to
    # the built bundle make lavish behave correctly behind that proxy:
    #
    # 1. `app.set("trust proxy", true)` — lavish's same-origin guard on the
    #    share/export and whiteboard routes compares the browser Origin against
    #    `req.protocol://host`. Without trusting the proxy, req.protocol is the
    #    upstream http connection, so it computes http:// while the browser sends
    #    https:// -> those routes 403. Trusting the proxy makes req.protocol honor
    #    nginx's X-Forwarded-Proto. The Host-allowlist guard is unaffected (it
    #    reads the Host header directly, which nginx forwards verbatim).
    #
    # 2. LAVISH_AXI_LINK_BASE — the printed session URL is hardcoded
    #    `http://<linkHost>:<port>`; there is no env for scheme/port. When set,
    #    this env makes it emit `<base>/session/<key>` so the link is a clean
    #    `https://lavish.ns1010301.cjlarose.dev/session/<key>`. Unset -> upstream
    #    behavior. --replace-fail so an upstream drift fails the build loudly.
    substituteInPlace dist/cli.mjs \
      --replace-fail 'const app = express()' \
                     'const app = express(); app.set("trust proxy", true)'
    substituteInPlace dist/cli.mjs \
      --replace-fail '`http://''${hostForUrl(linkHostName)}:''${publicPort}/session/''${key}`' \
                     '(process.env.LAVISH_AXI_LINK_BASE ? `''${process.env.LAVISH_AXI_LINK_BASE}/session/''${key}` : `http://''${hostForUrl(linkHostName)}:''${publicPort}/session/''${key}`)'

    # Drop devDependencies (esbuild + native binaries, the whiteboard build-only
    # deps like @excalidraw/mermaid/react, eslint, prettier, typescript) now that
    # dist/ is built — only the prod deps are imported at run time. Shrinks the
    # runtime closure and supply-chain footprint. Offline; no refetch.
    pnpm prune --prod --ignore-scripts
    runHook postBuild
  '';

  # Ship dist/ (the bundle + copied chrome client/css/design + vendored
  # whiteboard assets) plus node_modules for the external runtime imports. cp -a
  # preserves pnpm's relative symlink layout so requires resolve. The Claude Code
  # skill (skills/lavish/SKILL.md) is committed upstream, so it is copied as-is.
  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/lavish-axi $out/bin $out/share/lavish-axi/skill
    cp -a dist node_modules package.json $out/lib/lavish-axi/
    cp skills/lavish/SKILL.md $out/share/lavish-axi/skill/SKILL.md
    # Drive the on-PATH nix binary (pinned v0.1.43, wrapped, telemetry off), not
    # the `npx -y lavish-axi` copy the upstream skill defaults to — npx would
    # fetch the latest npm build at run time, run it outside our wrapper (so the
    # telemetry opt-out wouldn't apply), and require registry network access.
    substituteInPlace $out/share/lavish-axi/skill/SKILL.md \
      --replace-quiet 'npx -y lavish-axi' 'lavish-axi'

    makeWrapper ${nodejs_22}/bin/node $out/bin/lavish-axi \
      --add-flags $out/lib/lavish-axi/dist/cli.mjs \
      --set LAVISH_AXI_TELEMETRY 0

    runHook postInstall
  '';

  meta = {
    description = "Local HTML artifact review for coding agents (built from source, telemetry off)";
    homepage = "https://github.com/kunchenguid/lavish-axi";
    license = lib.licenses.mit;
    mainProgram = "lavish-axi";
    platforms = lib.platforms.unix;
  };
})
