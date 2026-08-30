#!/usr/bin/env python3
"""Rewrite flutter_tools' resolved package config for a packaged runtime.

Upstream does this in `build_flutter_tool_runtime` (tools/xtask/src/main.rs).
The file that `dart pub get` produces records each dependency's `rootUri` as an
absolute path into the pub cache that resolved it. Shipped as-is, those paths
point at a build directory that will not exist on the user's machine, so the
packaged copy has to be rewritten to point at the pub cache that ships
alongside it.

Only metadata travels: each dependency contributes its `pubspec.yaml` and
whichever of AUTHORS / COPYING / LICENSE / NOTICE it carries, which is what the
tool needs to resolve the graph. Source is not needed because nothing here runs
flutter_tools' own dependencies at build time.

Usage: prepare-tool-runtime.py <source package_config.json> <output pub-cache>
                               <output package_config.json> <flutter root URI>
                               <engine ABI>
"""

import json
import os
import shutil
import sys
from pathlib import Path

# Where the packaged pub cache sits relative to the packaged
# `packages/flutter_tools/.dart_tool/package_config.json`.
PUB_CACHE_URI = "../../../../pub-cache"

LEGAL_PREFIXES = ("copying.", "license.", "notice.")
LEGAL_NAMES = ("authors", "copying", "license", "notice")

# Upstream writes this marker so a toolchain can tell whether a pub cache was
# generated against the engine ABI it expects.
GENERATION_MARKER = ".denial-generation"


def is_legal_metadata(name):
    lowered = name.lower()
    return lowered in LEGAL_NAMES or lowered.startswith(LEGAL_PREFIXES)


def copy_package_metadata(source, destination):
    """Copy a package's pubspec.yaml and licence files, nothing else."""
    destination.mkdir(parents=True, exist_ok=True)
    destination.chmod(0o755)

    pubspec = source / "pubspec.yaml"
    if not pubspec.is_file():
        raise SystemExit(f"dependency has no pubspec.yaml: {source}")
    shutil.copy2(pubspec, destination / "pubspec.yaml")

    license_count = 0
    for entry in sorted(source.iterdir(), key=lambda p: p.name):
        if not entry.is_file():
            continue
        if not is_legal_metadata(entry.name):
            continue
        shutil.copy2(entry, destination / entry.name)
        if entry.name.lower().startswith("license"):
            license_count += 1

    if license_count == 0:
        raise SystemExit(f"dependency has no root license file: {source}")


def safe_relative(suffix):
    """Reject a suffix that would escape the pub cache it came from."""
    relative = Path(suffix)
    if relative.is_absolute() or os.path.isabs(suffix):
        raise SystemExit(f"dependency path is absolute: {suffix}")
    for part in relative.parts:
        if part in (".", ""):
            continue
        if part == "..":
            raise SystemExit(f"dependency path escapes the pub cache: {suffix}")
    return relative


def main():
    if len(sys.argv) != 6:
        raise SystemExit(__doc__)

    source_config = Path(sys.argv[1])
    output_pub_cache = Path(sys.argv[2])
    output_config = Path(sys.argv[3])
    flutter_root = sys.argv[4]
    engine_abi = sys.argv[5]

    document = json.loads(source_config.read_text())
    original_pub_cache = document.get("pubCache")
    if not isinstance(original_pub_cache, str):
        raise SystemExit("source package config has no pubCache string")
    if not original_pub_cache.startswith("file:///"):
        raise SystemExit(
            f"source package config pubCache is not an absolute file URI: {original_pub_cache}"
        )
    # `file:///build/...` -> `/build/...`
    pub_cache_path = Path(original_pub_cache[len("file://") :])

    output_pub_cache.mkdir(parents=True, exist_ok=True)

    packages = document.get("packages")
    if not isinstance(packages, list):
        raise SystemExit("source package config has no package list")

    resolved = pub_cache_path.resolve()
    dependency_count = 0
    for package in packages:
        if not isinstance(package, dict):
            raise SystemExit("source package config has a non-object package entry")
        root = package.get("rootUri")
        if not isinstance(root, str):
            raise SystemExit("source package entry has no rootUri")
        if root == "../":
            # The package itself, resolved in place.
            continue

        if not root.startswith("file:///"):
            raise SystemExit(f"unexpected Flutter tool package root: {root}")
        source = Path(root[len("file://") :]).resolve()

        if source != resolved and resolved not in source.parents:
            raise SystemExit(f"Flutter tool dependency escapes the pub cache: {source}")
        relative = source.relative_to(resolved)

        copy_package_metadata(source, output_pub_cache / relative)
        package["rootUri"] = f"{PUB_CACHE_URI}/{relative.as_posix()}"
        dependency_count += 1

    marker = output_pub_cache / GENERATION_MARKER
    marker.write_text(f"{engine_abi}\n")
    marker.chmod(0o644)

    document["pubCache"] = PUB_CACHE_URI
    document["flutterRoot"] = flutter_root

    output_config.parent.mkdir(parents=True, exist_ok=True)
    with output_config.open("w") as handle:
        json.dump(document, handle, indent=2)
        handle.write("\n")

    print(
        f"prepared metadata for {dependency_count} Flutter tool dependencies",
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()
