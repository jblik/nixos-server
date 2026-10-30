{
  lib,
  buildPythonPackage,
  fetchFromGitHub,
  setuptools,
  pycryptodome,
  requests,
  urllib3,
}:

buildPythonPackage (finalAttrs: {
  pname = "nr7101";
  version = "2.0.2";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "zulufoxtrot";
    repo = "nr7101";
    tag = "v${finalAttrs.version}";
    hash = "sha256-9wysByebktT01XB3heMLOYTdN3ZIzQA3dmowa5N44GA=";
  };

  build-system = [ setuptools ];
  dependencies = [
    pycryptodome
    requests
    urllib3
  ];
  pythonImportsCheck = [ "nr7101" ];

  meta = {
    description = "Zyxel NR7101 router client";
    homepage = "https://github.com/zulufoxtrot/nr7101";
    license = lib.licenses.mit;
  };
})
