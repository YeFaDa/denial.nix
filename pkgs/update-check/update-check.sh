#!/usr/bin/env bash
# Report every pin belonging to one immutable Denial release.
set -euo pipefail

json=0
force=0
source_check=1
for arg in "$@"; do
  case "$arg" in
    --json) json=1 ;;
    --force) force=1 ;;
    --source) source_check=1 ;;
    --no-source) source_check=0 ;;
    -h|--help)
      echo "usage: denial-update-check [--json] [--force] [--source] [--no-source]"
      echo "  --source     inspect release-pinned source inputs (default)"
      echo "  --no-source  skip source lock inspection"
      echo "  --force      compute prebuilt archive hashes even without a new release"
      exit 0
      ;;
    *) echo "unknown argument: $arg" >&2; exit 1 ;;
  esac
done

current_version='@version@'
current_dart_version='@dart_version@'
current_flutter_revision='@flutter_revision@'
current_dart_revision='@dart_revision@'
current_skia_revision='@skia_revision@'
current_material_fonts_version='@material_fonts_path@'
current_gradle_wrapper_version='@gradle_wrapper_path@'

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing dependency: $1" >&2
    exit 1
  }
}
need curl
need jq
need nix
need timeout
need sed
need tr

curl_get() {
  curl -fsSL --retry 2 --connect-timeout 10 --max-time 30 "$@"
}

latest_release_tag() {
  curl -fsSL --retry 2 --connect-timeout 10 --max-time 30 \
    -H 'Accept: application/vnd.github+json' \
    'https://api.github.com/repos/denialwm/denial/releases?per_page=100' \
    | jq -er 'map(select(.draft == false)) | .[0].tag_name'
}

current="$current_version"
latest="$(latest_release_tag)"
[[ -n "$latest" ]] || {
  echo "could not determine the latest Denial release" >&2
  exit 1
}
release_update=0
[[ "$latest" != "v$current" ]] && release_update=1

source_update=0
source_lock_url=''
source_lock_sha256=''
new_flutter_revision=''
new_dart_revision=''
new_skia_revision=''
new_dart_version=''
new_material_fonts_path=''
new_gradle_wrapper_path=''
if [[ "$source_check" == 1 ]]; then
  source_lock_url="https://raw.githubusercontent.com/denialwm/denial/${latest}/prebuilt/flutter-engine/SOURCE_LOCK.json"
  source_lock_json="$(curl_get "$source_lock_url")" || {
    echo "could not read SOURCE_LOCK.json for ${latest}" >&2
    exit 1
  }
  new_flutter_revision="$(jq -er '.flutter.revision' <<<"$source_lock_json")"
  new_skia_revision="$(jq -er '.skia.revision' <<<"$source_lock_json")"

  flutter_raw_base="https://raw.githubusercontent.com/denialwm/flutter/${new_flutter_revision}/bin/internal"
  new_material_fonts_path="$(curl_get "$flutter_raw_base/material_fonts.version" | tr -d '\r\n')"
  new_gradle_wrapper_path="$(curl_get "$flutter_raw_base/gradle_wrapper.version" | tr -d '\r\n')"

  deps_url="https://raw.githubusercontent.com/denialwm/flutter/${new_flutter_revision}/DEPS"
  new_dart_revision="$(curl_get "$deps_url" \
    | sed -nE "s/^[[:space:]]*'dart_revision':[[:space:]]*'([0-9a-f]{40})'.*/\1/p" \
    | sed -n '1p')"
  [[ "$new_dart_revision" =~ ^[0-9a-f]{40}$ ]] || {
    echo "could not read dart_revision from $deps_url" >&2
    exit 1
  }

  manifest_url="https://raw.githubusercontent.com/denialwm/denial/${latest}/packaging/arch/ui-development/manifest.json"
  new_dart_version="$(curl_get "$manifest_url" | jq -er '.sources.dart_version')" || {
    echo "could not read Dart SDK version from $manifest_url" >&2
    exit 1
  }

  if [[ "$release_update" == 1 || "$force" == 1 ]]; then
    source_lock_sha256="$(nix store prefetch-file --json --hash-type sha256 "$source_lock_url" | jq -er '.hash')"
  fi

  if [[ "$new_flutter_revision" != "$current_flutter_revision" || \
        "$new_dart_revision" != "$current_dart_revision" || \
        "$new_skia_revision" != "$current_skia_revision" || \
        "$new_dart_version" != "$current_dart_version" || \
        "$new_material_fonts_path" != "$current_material_fonts_version" || \
        "$new_gradle_wrapper_path" != "$current_gradle_wrapper_version" ]]; then
    source_update=1
  fi
fi

has_update=0
[[ "$release_update" == 1 || "$source_update" == 1 ]] && has_update=1

sha256_sri() {
  local url="$1"
  local result
  result="$(timeout 300 nix store prefetch-file --json --hash-type sha256 "$url")" || {
    echo "failed to fetch or hash: $url" >&2
    return 1
  }
  jq -er '.hash' <<<"$result"
}

new_version="${latest#v}"
new_denial_url="https://github.com/denialwm/denial/releases/download/${latest}/denial-${new_version}-1-x86_64.pkg.tar.zst"
new_engine_url="https://github.com/denialwm/denial/releases/download/${latest}/denial-flutter-engine-1.${new_version}-1-x86_64.pkg.tar.zst"
new_ui_dev_url="https://github.com/denialwm/denial/releases/download/${latest}/denial-ui-development-${new_version}-1-x86_64.pkg.tar.zst"
new_denial_sha256=''
new_engine_sha256=''
new_ui_dev_sha256=''
if [[ "$release_update" == 1 || "$force" == 1 ]]; then
  echo "computing release hashes for ${latest} ..." >&2
  new_denial_sha256="$(sha256_sri "$new_denial_url")"
  new_engine_sha256="$(sha256_sri "$new_engine_url")"
  new_ui_dev_sha256="$(sha256_sri "$new_ui_dev_url")"
fi

if [[ "$json" == 1 ]]; then
  jq -n \
    --arg current "$current" --arg latest "$latest" \
    --argjson has_update "$has_update" --argjson release_update "$release_update" --argjson source_update "$source_update" \
    --arg new_version "$new_version" \
    --arg denial_url "$new_denial_url" --arg denial_hash "$new_denial_sha256" \
    --arg engine_url "$new_engine_url" --arg engine_hash "$new_engine_sha256" \
    --arg ui_dev_url "$new_ui_dev_url" --arg ui_dev_hash "$new_ui_dev_sha256" \
    --arg source_lock_url "$source_lock_url" --arg source_lock_hash "$source_lock_sha256" \
    --arg current_flutter "$current_flutter_revision" --arg current_dart "$current_dart_revision" --arg current_skia "$current_skia_revision" \
    --arg current_dart_version "$current_dart_version" --arg current_material "$current_material_fonts_version" --arg current_gradle "$current_gradle_wrapper_version" \
    --arg new_flutter "$new_flutter_revision" --arg new_dart "$new_dart_revision" --arg new_skia "$new_skia_revision" \
    --arg new_dart_version "$new_dart_version" --arg new_material "$new_material_fonts_path" --arg new_gradle "$new_gradle_wrapper_path" \
    '{current: $current, latest: $latest, has_update: $has_update, release_update: $release_update, source_update: $source_update, new_version: $new_version,
      prebuilt: {denial: {url: $denial_url, sha256: $denial_hash}, engine: {url: $engine_url, sha256: $engine_hash}, uiDevelopment: {url: $ui_dev_url, sha256: $ui_dev_hash}},
      source: {pinned: true, source_lock: {url: $source_lock_url, sha256: $source_lock_hash},
        current: {flutter_revision: $current_flutter, dart_revision: $current_dart, dart_version: $current_dart_version, skia_revision: $current_skia, material_fonts_version: $current_material, gradle_wrapper_version: $current_gradle},
        release: {flutter_revision: $new_flutter, dart_revision: $new_dart, dart_version: $new_dart_version, skia_revision: $new_skia, material_fonts_version: $new_material, gradle_wrapper_version: $new_gradle}},
      lock_files: {engine_tools: "pkgs/denial-flutter-engine/flutter-tools-pubspec.lock.json", shell: "pkgs/denial-flutter-shell/pubspec.lock.json"},
      actions: {cargo_lock: ("https://raw.githubusercontent.com/denialwm/denial/" + $latest + "/compositor/Cargo.lock"), gclient_deps: "regenerate from SOURCE_LOCK.json with gclient2nix", flutter_tools_lock: "regenerate from packages/flutter_tools/pubspec.yaml", shell_lock: "regenerate from dart_shell/pubspec.yaml", flake_lock: "nix flake lock --update-input nixpkgs-dart"}}'
  exit 0
fi

echo "== Denial release update check =="
echo "current release: $current"
echo "latest release:  $latest"
echo "release update:  $release_update"
echo "prebuilt hashes: $(if [[ "$release_update" == 1 || "$force" == 1 ]]; then echo computed; else echo not computed; fi)"
if [[ "$source_check" == 1 ]]; then
  echo "SOURCE_LOCK.json: $source_lock_url"
  echo "source Flutter: $current_flutter_revision -> ${new_flutter_revision:-unavailable}"
  echo "source Dart:    $current_dart_version ($current_dart_revision) -> ${new_dart_version:-unavailable} ($new_dart_revision)"
  echo "source Skia:    $current_skia_revision -> ${new_skia_revision:-unavailable}"
  echo "material fonts: $current_material_fonts_version -> ${new_material_fonts_path:-unavailable}"
  echo "gradle wrapper: $current_gradle_wrapper_version -> ${new_gradle_wrapper_path:-unavailable}"
fi
if [[ "$has_update" == 0 ]]; then
  echo "Up to date: all checked pins match ${latest}."
  exit 0
fi
cat <<EOF

Update all fields from the same immutable release tag ${latest}.

Prebuilt:
  pkgs/version.nix: ${current} -> ${new_version}
  pkgs/prebuilt-hashes.nix: copy the three reported archive URLs and hashes
  pkgs/denial/Cargo.lock: ${latest}/compositor/Cargo.lock

Source:
  SOURCE_LOCK.json: ${source_lock_url}
  SOURCE_LOCK hash: ${source_lock_sha256:-computed when release hashes are requested}
  Flutter revision: ${new_flutter_revision}
  Skia revision: ${new_skia_revision}
  Dart SDK: ${new_dart_version} (${new_dart_revision})
  material_fonts.version: ${new_material_fonts_path}
  gradle_wrapper.version: ${new_gradle_wrapper_path}
  gclient-deps.json: regenerate from SOURCE_LOCK.json with gclient2nix
  flutter-tools-pubspec.lock.json: regenerate from packages/flutter_tools/pubspec.yaml
  denial-flutter-shell/pubspec.lock.json: regenerate from dart_shell/pubspec.yaml
  flake.lock: nix flake lock --update-input nixpkgs-dart

Verify:
  nix flake check --all-systems --no-build --no-write-lock-file
  nix build .#denial --no-link --fallback
  nix build .#denial-source --no-link --fallback
EOF
