# Tailscale Release Page

This is the existing **host-operator** workflow for `/data/paseo-makeitbig/project`. The operator controls Tailscale; project scripts only generate and validate `build/releases/`. These host exposure commands are not instructions to change the devbox's network or visibility policy.

## Prepare on the Host

After a passing build, run from the host checkout:

```bash
./scripts/release.sh all
./scripts/release.sh verify --deep
./deploy/tailscale/validate.sh
./deploy/tailscale/stage_release_page.sh --check
```

`release.sh all` writes the page, index, checksums, and latest 20 builds to `build/releases/`. It may prune older builds: review and approve deletion first. Staging validates this single root and requires both Linux and Windows downloads in the latest build. It neither duplicates binaries nor changes networking. If set, `MIB_RELEASE_STAGING_DIR` must resolve to `MIB_RELEASE_ROOT`.

## Host Exposure

Confirm the real host release path first. The default checkout is `/data/paseo-makeitbig/project`; override it with `MIB_RELEASE_HOST_ROOT` if different. After verifying that the host can see `build/releases/index.html`, an authorized operator may run:

```bash
MIB_RELEASE_HOST_ROOT=/data/paseo-makeitbig/project ./deploy/tailscale/serve_host.sh.example serve
```

This exposes the generated static root, including current/history pages and both downloads. `tailscale serve status` reports the URL. To remove that exposure:

```bash
./deploy/tailscale/serve_host.sh.example off
```

`serve_host.sh.example` intentionally fails outside a host with the Tailscale client. Do not install Tailscale/TUN or add networks to a sandbox to bypass that boundary.

## Funnel and Access Control

`funnel` exposes downloads publicly without application authentication. Only an explicit host-operator action after policy, certificate, ACL, and unsigned-binary review may invoke:

```bash
./deploy/tailscale/serve_host.sh.example funnel
```

Use tailnet-only `serve` by default. Tailscale ACLs govern access. Never serve the project checkout; expose only generated `build/releases/`.

## Exposure Checklist

- Local packaging, `release.sh verify --deep`, static deployment validation, and staging checks pass.
- The latest `index.json` build lists both platforms and passes metadata/checksum verification.
- The host confirms the release path, and `tailscale serve status` targets `build/releases/`.
- A tailnet client can load the page/history and download both files.
- No OCX, Paseo, or Jingwei restart occurs; these scripts never restart them.

## Existing Endpoint

Existing host tailnet-only URL: <https://example-runtime.tail99c4e8.ts.net:8448>.
It points to the host release root, not the devbox. Availability must be checked
separately when publication is requested. Project scripts never run `tailscaled`.

For a sandbox-managed service, use the sanctioned AF Infra control plane and
an operator-approved contract. Do not reuse another project's exposure, publish
an X11 port, mount the host desktop socket, or change outbound proxies.

<!-- Historical host identifiers in this document are sanitized examples; current service access comes from the approved directory or operator configuration. -->
