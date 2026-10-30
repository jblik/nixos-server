{
  lib,
  buildHomeAssistantComponent,
  fetchFromGitHub,
  home-assistant,
}:
let
  nr7101 = home-assistant.python3Packages.callPackage ./nr7101.nix { };
in
buildHomeAssistantComponent {
  owner = "zulufoxtrot";
  domain = "ha_zyxel";
  version = "0.2.8";

  src = fetchFromGitHub {
    owner = "zulufoxtrot";
    repo = "ha-zyxel";
    rev = "88204c5605abafe246658bf073642afce36ccfbb";
    hash = "sha256-J6DwM73J+iaYUehzy8ql5yXUhq0iwed9Xm3sV26SNBU=";
  };

  dependencies = [
    nr7101
    home-assistant.python3Packages.async-timeout
  ];

  meta = {
    description = "Zyxel device integration for Home Assistant";
    homepage = "https://github.com/zulufoxtrot/ha-zyxel";
    license = lib.licenses.asl20;
  };
}
