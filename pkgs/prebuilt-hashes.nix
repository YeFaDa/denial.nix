let
  version = import ./version.nix;
in
{
  denial = {
    url = "https://github.com/denialwm/denial/releases/download/v${version}/denial-${version}-1-x86_64.pkg.tar.zst";
    hash = "sha256-oKI+C4UIIe9pd3nkLzDYpTeF1OwPV29LHV+CXwRCbQM=";
  };
  engine = {
    url = "https://github.com/denialwm/denial/releases/download/v${version}/denial-flutter-engine-1.${version}-1-x86_64.pkg.tar.zst";
    hash = "sha256-moyDvDyzMUTaxIHtBwSlYDzjiqBNczyElRzkSCM058w=";
  };
  uiDevelopment = {
    url = "https://github.com/denialwm/denial/releases/download/v${version}/denial-ui-development-${version}-1-x86_64.pkg.tar.zst";
    hash = "sha256-v35GRv9JYPbnzG6LsZFMkNzpdo7aL3x4MzTh1Vt86yw=";
  };
}
