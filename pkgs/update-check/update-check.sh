#!/usr/bin/env bash
# denial-update-check — YeFaDa/denial.nix
set -euo pipefail

JSON=0; FORCE=0
for arg in "$@"; do
  case "$arg" in
    --json) JSON=1 ;;
    --force) FORCE=1 ;;
    -h|--help) echo "usage: denial-update-check [--json] [--force]"; exit 0 ;;
    *) echo "unknown argument: $arg" >&2; exit 1 ;;
  esac
done
VERSION='@version@'
need() { command -v "$1" >/dev/null 2>&1 || { echo "missing dependency: $1" >&2; exit 1; }; }
need curl; need jq; need nix; need nix-prefetch-url; need timeout

latest_tag() {
  curl -fsSL --retry 2 --connect-timeout 10 --max-time 30 \
    -H 'Accept: application/vnd.github+json' \
    "https://api.github.com/repos/denialwm/denial/releases?per_page=100" \
    | jq -r 'map(select(.draft == false)) | .[0].tag_name // empty'
}

CURRENT="$VERSION"
LATEST="$(latest_tag)"
if [[ -z "$LATEST" ]]; then
  echo "could not determine the latest Denial release" >&2
  exit 1
fi
has_update=0
if [[ "$LATEST" != "v$CURRENT" ]]; then has_update=1; fi


sha256_sri() {
  local url="$1"
  local b32
  b32="$(timeout 300 nix-prefetch-url --type sha256 "$url")" || {
    echo "failed to fetch or hash: $url" >&2
    return 1
  }
  nix hash convert --hash-algo sha256 --to sri "$b32"
}



NEW_VERSION="${LATEST#v}"
NEW_DENIAL_URL=""; NEW_DENIAL_SHA256=""; NEW_ENGINE_URL=""; NEW_ENGINE_SHA256=""; NEW_UIDEV_URL=""; NEW_UIDEV_SHA256=""
if [[ "$has_update" == 1 || "$FORCE" == 1 ]]; then
  if [[ -n "$LATEST" ]]; then
    NEW_DENIAL_URL="https://github.com/denialwm/denial/releases/download/${LATEST}/denial-${NEW_VERSION}-1-x86_64.pkg.tar.zst"
    NEW_ENGINE_URL="https://github.com/denialwm/denial/releases/download/${LATEST}/denial-flutter-engine-1.${NEW_VERSION}-1-x86_64.pkg.tar.zst"
    NEW_UIDEV_URL="https://github.com/denialwm/denial/releases/download/${LATEST}/denial-ui-development-${NEW_VERSION}-1-x86_64.pkg.tar.zst"
    echo "computing sha256 for $LATEST ..." >&2
    NEW_DENIAL_SHA256="$(sha256_sri "$NEW_DENIAL_URL")"
    NEW_ENGINE_SHA256="$(sha256_sri "$NEW_ENGINE_URL")"
    NEW_UIDEV_SHA256="$(sha256_sri "$NEW_UIDEV_URL")"
  fi
fi

if [[ "$JSON" == 1 ]]; then
  jq -n --arg cur "$CURRENT" --arg latest "$LATEST" --argjson has "$has_update" \
    --arg newVer "$NEW_VERSION" --arg newDenialUrl "$NEW_DENIAL_URL" --arg newDenialSha "$NEW_DENIAL_SHA256" \
    --arg newEngineUrl "$NEW_ENGINE_URL" --arg newEngineSha "$NEW_ENGINE_SHA256" \
    --arg newUiDevUrl "$NEW_UIDEV_URL" --arg newUiDevSha "$NEW_UIDEV_SHA256" \
    '{current: $cur, latest: $latest, has_update: $has, new_version: $newVer, prebuilt: {denial: {url: $newDenialUrl, sha256: $newDenialSha}, engine: {url: $newEngineUrl, sha256: $newEngineSha}, uiDevelopment: {url: $newUiDevUrl, sha256: $newUiDevSha}}}'
  exit 0
fi

echo "== Denial update check =="
echo "current: $CURRENT"
echo "latest:  ${LATEST:-unavailable}"
if [[ "$has_update" == 0 ]]; then
  echo "Up to date."
  [[ "$FORCE" == 1 ]] || exit 0
fi
cat <<EOF
Fields to update:
  pkgs/version.nix: "$CURRENT" -> "$NEW_VERSION"
  pkgs/prebuilt-hashes.nix:
    denial.url: $NEW_DENIAL_URL
    denial.hash: $NEW_DENIAL_SHA256
    engine.url: $NEW_ENGINE_URL
    engine.hash: $NEW_ENGINE_SHA256
    uiDevelopment.url: $NEW_UIDEV_URL
    uiDevelopment.hash: $NEW_UIDEV_SHA256
  pkgs/denial/Cargo.lock: curl -o pkgs/denial/Cargo.lock https://raw.githubusercontent.com/denialwm/denial/$LATEST/compositor/Cargo.lock
  pkgs/denial-flutter-engine/gclient-deps.json: regenerate from prebuilt/flutter-engine/SOURCE_LOCK.json via gclient2nix
  pkgs/denial-flutter-engine/revisions.nix: materialFontsVersion / gradleWrapperVersion from flutter/bin/internal/*

After editing:
  nix flake check --all-systems --no-build
  NIX_BUILD_CORES=16 nix build .#denial --no-link  # prebuilt
  NIX_BUILD_CORES=16 nix build --impure --expr 'let f=builtins.getFlake (toString ./.); in f.packages.x86_64-linux.denial.override { useSource = true; }' --no-link
EOF
