# GitHub Release Workflow

[GitHub Releases](https://github.com/rapidhere121345/makeitbig/releases) is the
download destination. The former HTTP page and serving scripts are retired;
the operator stopped the server. The old `release-online/` folder was moved intact to ignored
`build/archive/release-online-20261028/`; that binary history is never pruned.

## Downloads

Each versioned release contains:

- `make-it-big-linux-x86_64.tar.gz`: Linux executable with its execute bit intact.
- `make-it-big-windows-x86_64.zip`: Windows executable.
- `make-it-big-macos-universal.zip`: the exact app ZIP checked on ARM64 and Intel Macs.
- `build.json`: tag, full source commit, timestamp, asset sizes, and SHA256 hashes.
- `RELEASE_NOTES.md`: player-facing notes and source commit.
- `SHA256SUMS`: hashes for every archive, metadata, and notes file.

Windows/Linux binaries are unsigned; the Mac app is ad-hoc signed without Apple
notarization. See [Mac launch instructions](MACOS.md). Native smoke/replay checks
do not establish graphical, audio, or sustained GPU performance acceptance.

## Local Validation

After the [build gate](HOST_WORKFLOW.md) and all three exports:

```bash
./scripts/with_env.sh ./scripts/release.sh package vX.Y.Z
./scripts/with_env.sh ./scripts/release.sh verify build/releases/vX.Y.Z
./deploy/tailscale/validate.sh # retired-page compatibility check; no networking
```

`verify` without a directory checks every local `v*` package. Packaging refuses
to replace an existing output folder and fails if a platform is missing. Use
`MIB_RELEASE_ROOT` for a fresh validation root. Configuration lives in
`release/config/release.conf`; generated deliverables must not be committed.
The former `all`, `site`, `index`, and `prune` commands are removed.

## Publication

Review and commit the release sources and `release/notes.md`, then create and
push a new version tag:

```bash
git tag -a vX.Y.Z -m 'Make It Big vX.Y.Z'
git push origin vX.Y.Z
```

The `desktop-build` workflow runs the full Linux build/test/export/smoke gate,
Windows native boot/replay, and ARM64/Intel Mac signature/boot/replay. The release
job depends on every one of those jobs; ordinary branch/PR builds do not publish.
Only the release job receives `contents: write`. No permanent GitHub credential
is stored in the repository or devbox.

The publisher requires the existing tag to match the package's source commit.
It verifies all hashes, creates a draft with all six assets, then publishes it.
An upload failure leaves a draft rather than publishing partial downloads.
An existing GitHub Release is never overwritten or deleted automatically; inspect
any partial draft before retrying. Prerelease tag suffixes produce prereleases
without replacing the latest stable release. A stable tag becomes latest.

Direct downloads have durable GitHub Release URLs and do not depend on expiring
Actions artifacts. Release tags/assets are not moved, replaced, or automatically
pruned. Project scripts do not start an HTTP server, change host exposure, or
restart OCX, Paseo, or Jingwei.
