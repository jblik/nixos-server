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

  # Home Assistant must manage the config entry context during options reloads.
  postPatch = ''
    substituteInPlace custom_components/meteoswiss/__init__.py \
      --replace-fail 'await async_unload_entry(hass, entry)' 'await hass.config_entries.async_reload(entry.entry_id)' \
      --replace-fail '    await async_setup_entry(hass, entry)' ""
  '';

  meta = {
    description = "MeteoSwiss integration for Home Assistant";
    homepage = "https://github.com/LNKtwo/ha-meteoswiss";
    license = lib.licenses.mit;
  };
})
