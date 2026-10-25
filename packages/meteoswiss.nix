{
  lib,
  buildHomeAssistantComponent,
  fetchFromGitHub,
}:

buildHomeAssistantComponent (finalAttrs: {
  owner = "LNKtwo";
  domain = "meteoswiss";
  version = "8.1.2";

  src = fetchFromGitHub {
    owner = "LNKtwo";
    repo = "ha-meteoswiss";
    tag = "v${finalAttrs.version}";
    hash = "sha256-8txPb5wfbUzxeUa4unu5fME4osPTa3MmRdKOOkiPBqM=";
  };

  meta = {
    description = "MeteoSwiss integration for Home Assistant";
    homepage = "https://github.com/LNKtwo/ha-meteoswiss";
    license = lib.licenses.mit;
  };
})
