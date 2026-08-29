let
  version = import ./version.nix;
in
{
  denial = {
    url = "https://github.com/denialwm/denial/releases/download/v${version}/denial-${version}-1-x86_64.pkg.tar.zst";
    hash = "sha256-t2/BOuGrkNYi6w9mLSHhIGtKcXaRv+KHklzr2Jne5VY=";
  };
  engine = {
    url = "https://github.com/denialwm/denial/releases/download/v${version}/denial-flutter-engine-1.${version}-1-x86_64.pkg.tar.zst";
    hash = "sha256-V/PzHmD3e3XN3bQRghITkqTHb9m9YtJVcLSkijG0kUg=";
  };
  uiDevelopment = {
    url = "https://github.com/denialwm/denial/releases/download/v${version}/denial-ui-development-${version}-1-x86_64.pkg.tar.zst";
    hash = "sha256-1p300E0Stlr2P5Wp9eKohMOeIzt/J1TdSkj/SXL6siU=";
  };
}
