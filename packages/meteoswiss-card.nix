{
  lib,
  stdenvNoCC,
  fetchurl,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "meteoswiss-card";
  version = "2.4.8";

  src = fetchurl {
    url = "https://raw.githubusercontent.com/LNKtwo/ha-meteoswiss-card/v${finalAttrs.version}/meteoswiss-weather-card.js";
    hash = "sha256-25m1K03O6Q7f7J9jzPIDQmSD9yHPGGdUdK7lTqkd0Bk=";
  };

  dontUnpack = true;
  installPhase = ''
    runHook preInstall

    install -Dm444 $src $out/meteoswiss-weather-card.js

    runHook postInstall
  '';

  passthru.entrypoint = "meteoswiss-weather-card.js";

  meta = {
    description = "MeteoSwiss weather dashboard card for Home Assistant";
    homepage = "https://github.com/LNKtwo/ha-meteoswiss-card";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };
})
