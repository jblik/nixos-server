{
  lib,
  stdenvNoCC,
  fetchurl,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "mass-player-card";
  version = "2.8.0";

  src = fetchurl {
    url = "https://github.com/droans/mass-player-card/releases/download/v${finalAttrs.version}/mass-player-card.js";
    hash = "sha256-MrnxXxguoe2tOFP022IYxhc9kSupXwRnLHsPESWtofE=";
  };

  dontUnpack = true;
  installPhase = ''
    runHook preInstall

    install -Dm444 $src $out/mass-player-card.js

    runHook postInstall
  '';

  passthru.entrypoint = "mass-player-card.js";

  meta = {
    description = "Music Assistant player card with queue controls and media browser";
    homepage = "https://github.com/droans/mass-player-card";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };
})
