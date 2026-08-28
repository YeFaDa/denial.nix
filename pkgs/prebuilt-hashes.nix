let
  version = import ./version.nix;
in
{
  denial = {
    url = "https://github.com/denialwm/denial/releases/download/v${version}/denial-${version}-1-x86_64.pkg.tar.zst";
    hash = "sha256-xJ3eYDtVqUvSCZQ6h9GG265azOnEHTdB+oB2Wo3D/Bg=";
  };
  engine = {
    url = "https://github.com/denialwm/denial/releases/download/v${version}/denial-flutter-engine-1.${version}-1-x86_64.pkg.tar.zst";
    hash = "sha256-sNcM8UlBeJYbfb51ehOJWQTgOnJmEHUCUYMoO+Plfw0=";
  };
  uiDevelopment = {
    url = "https://github.com/denialwm/denial/releases/download/v${version}/denial-ui-development-${version}-1-x86_64.pkg.tar.zst";
    hash = "sha256-lo8UtmkVjggWGDQAEGFi4HeEw80a3qxj1em1/v8T2zE=";
  };
}
