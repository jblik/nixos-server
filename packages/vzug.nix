{
  lib,
  buildHomeAssistantComponent,
  fetchFromGitHub,
  json-repair,
}:

buildHomeAssistantComponent (finalAttrs: {
  owner = "siku2";
  domain = "vzug";
  version = "0.5.0";

  src = fetchFromGitHub {
    owner = "siku2";
    repo = "hass-vzug";
    tag = "v${finalAttrs.version}";
    hash = "sha256-ESegI0Yw1P53Pweymm4ZvcBDrhMbeXRu2OOt4KG55kM=";
  };

  dependencies = [ json-repair ];

  # Nixpkgs provides a newer json-repair; V-ZUG only uses its repair_json API.
  ignoreVersionRequirement = [ "json-repair" ];

  postPatch = ''
    substituteInPlace custom_components/vzug/manifest.json \
      --replace-fail '"version": "0.0.0"' '"version": "${finalAttrs.version}"'
  '';

  meta = {
    description = "V-ZUG appliance integration for Home Assistant";
    homepage = "https://github.com/siku2/hass-vzug";
    license = lib.licenses.mit;
  };
})
