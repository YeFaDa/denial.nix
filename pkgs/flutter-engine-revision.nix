# The Flutter engine revision whose published Linux artifacts this repository
# falls back to for the few files Denial's own engine build does not produce.
#
# This is the content of `bin/internal/engine.version` in the pinned
# `denialwm/flutter` checkout, i.e. the revision `flutter precache --linux`
# would download on a machine building Denial the upstream way. It is *not* the
# revision of Denial's own engine build: that one is pinned by
# `pkgs/denial-flutter-engine/gclient-deps.json` and is built from source here.
#
# The two are allowed to differ and upstream relies on that: the Arch packaging
# for `denial-ui-development` takes `icudtl.dat` from the former and the engine
# itself from the latter.
#
# Pinned as a literal rather than read out of the checkout at build time,
# because `fetchurl` needs the URL while the flake is still being evaluated --
# reading it from a derivation would make every `nix flake show` build the
# whole Flutter checkout first.
#
# Bump together with `pkgs/denial-flutter-engine/revisions.nix`; see
# `scripts/update-release-pins`.
"69c8c61792f04cc809dfef0c910414fb9afc06cd"
