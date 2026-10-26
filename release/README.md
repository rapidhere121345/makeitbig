# Release Page and Build Conventions

This directory contains release-page templates and configuration. Generated output lives in the ignored live publish root `release-online/`, not in source control.

## Quick Start

After the full test gate and both platform exports, run from the project root:

    ./scripts/release.sh all
    ./scripts/release.sh verify --deep

Subcommands are `package`, `index`, `prune`, `site`, `verify`, and `all`. `package` reads `build/current/linux/make-it-big.x86_64` and `build/current/windows/make-it-big.exe`, generating metadata and `SHA256SUMS`. `prune` retains the 3 newest valid builds by default; `site` produces the static site in `release-online/`. Because `all` invokes `prune`, review and approve any deletion of existing release history first.

Defaults live in `release/config/release.conf` (`MIB_RELEASE_ROOT=release-online`, `MIB_RELEASE_KEEP_BUILDS=3`; `scripts/release.sh` keeps matching fallbacks if the file is absent). Set `MIB_RELEASE_ROOT` to override the output root. It must be inside the checkout unless `MIB_RELEASE_ALLOW_OUTSIDE=1` explicitly permits an external test directory.

## Layout

The default build ID is `YYYYMMDD-HHMMSS-<short-git-SHA>`; override it with `package --id`:

    release-online/
      index.html
      index.json
      app.js
      style.css
      builds/<build-id>/
        build.json
        SHA256SUMS
        linux/make-it-big.x86_64
        windows/make-it-big.exe

`build.json` is the metadata source of truth for a build: revision, timestamp, platform paths, sizes, and SHA256 hashes. Missing platforms remain explicit; packaging with no exported files requires `--allow-empty`.

`prune` considers only direct children of `builds/` with valid build IDs and metadata, excluding symlinks. It does not recursively clean unrelated directories.

## Boundaries

`release/site/` is committed page source; `release-online/` is generated output. Release scripts read current exports and write the configured release root. They do not run Docker, configure Tailscale, or restart services. Windows/Linux binaries are unsigned; the operator must review signing and access control before public distribution.
