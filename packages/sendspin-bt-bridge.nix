{
  lib,
  fetchFromGitHub,
  python3Packages,
  gobject-introspection,
  gst_all_1,
  wrapGAppsNoGuiHook,
}:
python3Packages.buildPythonApplication {
  pname = "sendspin-bt-bridge";
  version = "2.76.4";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "trudenboy";
    repo = "sendspin-bt-bridge";
    tag = "v2.76.4";
    # GitHub's release archive excludes the upstream tests.
    forceFetchGit = true;
    hash = "sha256-95WXZQXJx/rfEnT1kgiBmu7UTrgHPWGRLTDlM78113U=";
  };

  build-system = [ python3Packages.hatchling ];
  nativeBuildInputs = [
    gobject-introspection
    wrapGAppsNoGuiHook
  ];
  buildInputs = with gst_all_1; [
    gstreamer
    gst-plugins-base
    gst-plugins-good
  ];
  dependencies = with python3Packages; [
    aiohttp
    aiomqtt
    aiosendspin
    av
    bluetooth-auto-recovery
    btsocket
    cryptography
    dbus-fast
    flask
    music-assistant-client
    pillow
    pulsectl-asyncio
    pygments
    pygobject3
    pyjwt
    requests
    waitress
    websockets
    zeroconf
  ];
  pythonRelaxDeps = [
    "aiohttp"
    "cryptography"
    "dbus-fast"
    "music-assistant-client"
    "pillow"
    "pygments"
    "PyJWT"
    "requests"
    "websockets"
    "zeroconf"
  ];

  postPatch = ''
    cat >> pyproject.toml <<'EOF'
    [project.scripts]
    sendspin-bt-bridge = "sendspin_bridge.__main__:main"
    EOF
  '';

  dontWrapGApps = true;
  preFixup = ''
    makeWrapperArgs+=("''${gappsWrapperArgs[@]}")
  '';

  nativeCheckInputs = with python3Packages; [
    pytestCheckHook
    pytest-asyncio
    pytest-timeout
  ];
  pytestFlags = [
    "-o"
    "addopts="
    "tests/unit/config/test_config_store.py"
    "tests/unit/bridge/test_sendspin_client_runtime.py"
  ];
  preCheck = ''
    export CONFIG_DIR="$TMPDIR/sendspin-config"
  '';
  postCheck = ''
    python scripts/check_sendspin_compat.py --expect-aiosendspin 9.1.1
  '';

  pythonImportsCheck = [
    "sendspin_bridge.bridge.client"
    "sendspin_bridge.web"
  ];

  meta = {
    description = "Bridge Music Assistant Sendspin audio to Bluetooth speakers";
    homepage = "https://github.com/trudenboy/sendspin-bt-bridge";
    license = lib.licenses.mit;
    mainProgram = "sendspin-bt-bridge";
    platforms = lib.platforms.linux;
  };
}
