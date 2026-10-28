# Release Workflow

Release sources and page templates live in `release/`; `scripts/release.sh` generates ignored output in the live publish root `release-online/` (defaults in `release/config/release.conf`: `MIB_RELEASE_ROOT=release-online`, `MIB_RELEASE_KEEP_BUILDS=3`). Do not commit generated deliverables.

## Layout and Naming

`release.sh package` reads the Linux/Windows executables and `build/current/macos/make-it-big-macos-universal.zip` and creates a timestamped build directory. IDs default to `YYYYMMDD-HHMMSS-<short-git-SHA>` and can be set with `--id`. A complete desktop build contains:

- `build.json`: ID, revision, timestamp, platform files, sizes, and SHA256.
- `linux/make-it-big.x86_64`: Linux x86_64 download.
- `windows/make-it-big.exe`: Windows x86_64 download.
- `macos/make-it-big-macos-universal.zip`: Apple Silicon ARM64 and Intel app download.
- `SHA256SUMS`: download checksums.

`index` writes newest-first metadata to `release-online/index.json`; `site` writes the page, stylesheet, script, and embedded index to the same root. Serve this directory directly as a static site. Metadata and UI explicitly distinguish missing platform files instead of offering broken downloads.

## Standard Commands

```bash
./scripts/build.sh
# Review and commit after the passing build so release metadata names its source.
git diff --check
git status --short
# git add <reviewed-files> && git commit -m '<change-description>'
# Review retention candidates and approve any deletion before invoking all.
./scripts/release.sh all --note 'Change description'
./scripts/release.sh verify --deep
./deploy/tailscale/validate.sh
./deploy/tailscale/stage_release_page.sh --check
```

`all` runs package → prune → index → site → verify. Against the live `release-online/` root, `all` and `prune` delete every build older than the 3 newest, so list the candidates and obtain explicit approval first. `prune` defaults to retaining the 3 newest direct child directories with valid IDs and `build.json`, and never cleans other paths. Set `MIB_RELEASE_ROOT` explicitly for an isolated validation root and inspect its contents first. To validate new packaging without pruning existing history, run `package`, `index`, `site`, and `verify --deep` separately in that fresh root.

Do not publish exports after changing runtime code or assets without rebuilding. After publication, compare the served `/index.json` build ID with local metadata and verify HTTP status, size, and SHA256 for every available download. Cross-exports are not native acceptance; see [macOS validation](MACOS.md).

## Tailscale Exposure

The project validates generated files locally:

```bash
./deploy/tailscale/stage_release_page.sh
```

Staging validates the single `release-online/` root and requires both downloads in the latest build. History, index, and page assets share that root; there is no separate single-build page. The operator owns Tailscale/TUN and must confirm that the host can see the release root before running `deploy/tailscale/serve_host.sh.example serve`. The default is tailnet-only HTTPS; public `funnel` exposure requires a separate policy/ACL/unsigned-binary review.

Before exposure, pass both validation commands, ensure the release root contains no source checkout, confirm `tailscale serve status` targets it, and test the home page and both downloads from the tailnet. The page does not implement account authentication; Tailscale ACLs control access.

## Existing Host Endpoint

The current publish URL, supplied by the operator, is <http://192.0.2.10:18080/>. It supersedes the former HTTPS endpoint. No endpoint check was performed, as requested by the operator. Project scripts never run `tailscaled`.

For a sandbox managed by AF Infra, use the sanctioned control plane and an operator-approved deployment contract rather than configuring host networking from the sandbox. Moving the checkout alone does not provision a publication endpoint.

<!-- Historical host identifiers in this document are sanitized examples; current service access comes from the approved directory or operator configuration. -->
