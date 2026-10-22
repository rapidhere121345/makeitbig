# Devbox Readiness

## Scope and Status

The operator plans to move Make It Big into the existing local Docker sandbox,
whose writable workspace is `/data/claude/workspace`. The final checkout
destination is `/data/claude/workspace/makeitbig`. **Do not create, copy, migrate,
or activate that checkout until the operator explicitly instructs it.**
Game-source preparation and validation remain in the original checkout.
The separate `.tools/make-it-big/` directory holds approved tools, not the
future game checkout or a replacement for another project.

Initial read-only audit: 2026-10-22, container `example-devbox`, UID/GID `1000:1000`.
That initial audit performed no installation or reconfiguration. Later explicitly
approved provisioning is recorded separately below. A checker executed from stdin,
without placing a file in the target. Its output is retained on the original
host in ignored `build/current/devbox-release-prerequisites.json`.

**Current verdict: headless/export prerequisites installed; actual CPU graphics
acceptance remains pending.** A discrete GPU is not required.
The project has not been moved, so target-side project tests and exports have
not run and cannot be claimed as passed.

## Initial Facilities Before Provisioning

| Facility | Observed result | Assessment |
| --- | --- | --- |
| OS/architecture | Linux x86_64 | Matches current desktop build target |
| User | `dev`, UID/GID 1000 | Non-root requirement met |
| Writable workspace | `/data/claude/workspace` | Available; existing work untouched |
| Root filesystem | Read-only | System dependencies need operator/image provisioning |
| CPU quota | 4 CPUs | Reasonable starting point; full matrix duration unmeasured |
| Memory limit | 8 GiB | Sequential builds recommended; peak use not measured |
| Shared memory | 1 GiB | Available; graphics workload not yet exercised |
| Free workspace storage | About 798 GiB | Sufficient for current imports/builds |
| Open-file limit | 1024 | Record during testing; increase only if measured exhaustion occurs |
| GPU | RTX 4080 SUPER, driver 595.91.07, 16376 MiB | `nvidia-smi` passes; not OpenGL acceptance |
| Shell/test utilities | bash, Python 3.11.2, git, timeout, sha256sum, curl | Present |
| Release utilities | cp, date, mktemp, Node/npm | Present |
| Godot | Neither `godot` nor `godot4` found on PATH | Blocking |
| Export templates | No 4.7.2 standard install found; intended workspace path absent | Blocking |
| Display | No DISPLAY/WAYLAND_DISPLAY; no Xvfb/xvfb-run | Blocking for windowed acceptance |
| Display probes | No glxinfo/xdotool | glxinfo needed for prerequisites; input tool optional |
| Graphics libraries | GL/GLX/EGL dispatch, Xcursor, Xinerama not found by loader lookup | Operator must verify/provision; NVIDIA GLX driver library alone is insufficient |
| Other libraries | X11, Xi, Xrandr, fontconfig, ALSA found | Partial runtime support |
| Python Pillow | Missing | Needed for offline art baking and pixel validation |
| ZIP CLI | unzip/zip absent | Not a blocker if Python's zipfile is used |
| Native Windows runner | No wine/pwsh found | Neither substitutes for native Windows CI anyway |
| Image-generation tool | Reported available by operator | Not invoked or acceptance-tested during this audit |

The physical host's approximately 64 GiB RAM is **not** the container limit:
the initial Docker limit was 8 GiB, now increased to 16 GiB. Do not present host
resource figures as sandbox capacity.

## Approved Provisioning

The operator approved 8 vCPU / 16 GiB RAM and installation of the missing tools.
Resource update:

```text
docker update --cpus 8 --memory 16g --memory-swap 24g example-devbox
```

This retains an 8 GiB swap allowance. PID `2198395` and start time
`2026-10-22T04:28:00.728272595Z` were identical before/after: no restart occurred.
No disk resize was needed. The operator should sync these approved resource
limits into the authoritative container configuration so a future recreation
does not revert them; this task did not edit control-plane or Compose files.

Offline installation used a new, isolated prefix:
`/data/claude/workspace/.tools/make-it-big/`.

- `godot-4.7.2/godot`: official binary; version and pinned SHA256 verified.
- `export_templates/4.7.2.stable/`: matching Linux/Windows release templates.
- `portable-cpu/`: Xvfb, X11 utilities, an explicitly labeled `mib-gl-probe`,
  Mesa software-rendering libraries, matching glibc loader/dependencies,
  Python 3.14.4, and Pillow 12.1.1.
- Python/Pillow PNG RGBA round-trip and FreeType checks pass as UID 1000.
  The container's existing Python 3.11 remains unchanged.
- All 1,707 static runtime-file hashes pass. The bundle includes 121 upstream
  package version/copyright records, no host home/configuration files, and no
  absolute symlinks exposing host paths. System `sitecustomize` hooks are
  explicitly excluded.

The host and container have different glibc/Python versions. Scoped launchers
use the bundled matching loader instead of installing incompatible shared
libraries into the system or setting a global `LD_LIBRARY_PATH`.
`GODOT_BIN` identifies the launcher; `MIB_GODOT_BINARY_PATH` identifies the
unchanged official engine whose bytes `project_env.sh` verifies.

Activate only in the intended project shell:

```bash
source /data/claude/workspace/.tools/make-it-big/portable-cpu/env.sh
```

The current graphical result remains **unverified**: Xvfb has not started,
because creating its owned temporary X11 IPC files needs the explicit sandbox
exception discussed with the operator. The smoke launcher refuses without
approval. Installed libraries and a successful version probe are not a rendered
pixel pass.

Ignored original-host evidence:

- `build/current/devbox-release-prerequisites-offline-installed.json`
- `build/current/devbox-cpu-portable/provisioning.json`
- `build/current/devbox-cpu-portable/godot-launch-contract.log`
- `build/current/devbox-scoped-release-prerequisites.json`: scoped launcher,
  raw engine SHA, both templates, and Pillow all pass.

### Actual Headless Export Proof

The installed target toolchain also ran an independent tiny English fixture,
not the Make It Big source. As UID 1000, editor import, Linux export, Windows
export, and direct native Linux launch from a fresh empty directory all exited
0. The Linux executable printed `TOOLCHAIN_FIXTURE_SMOKE_PASS`; its launch
directory remained empty. Official template hashes remained unchanged.

| Output | Size | SHA256 |
| --- | ---: | --- |
| Fixture Linux ELF | 73521624 bytes | `8ac25a97ef9b504059f772b9a404f34ed9aaead6eb0b83ede090cac359f971a4` |
| Fixture Windows PE/x86-64 | 109270696 bytes | `1d390408f6e3fb980dfb0f9ccb4f9337bcd1153c71b10d57839cba55b717decf` |

Windows evidence is export and PE-header validation only, not native execution.
These checks prove target toolchain compatibility, not that the unmoved game
passed there. No display, listener, or external download was used.
Evidence: `build/current/devbox-cpu-portable/headless-export-evidence/result.json`,
its `logs/`, and `headless-export-toolchain.log` in the parent directory.

## Security and Visibility

Read-only verification after the resource update records:

| Boundary | State |
| --- | --- |
| User | `1000:1000` |
| Privileged | false |
| Root filesystem | read-only |
| Capabilities | all dropped, no additions |
| Security option | `no-new-privileges:true` |
| IPC | private |
| Network | existing `claude_claude-net` only |
| Published port bindings | none |
| Mount count | existing 13; no additions by this task |

No proxy/DNS changes, alternate networks, new devices, privileged mounts, host
desktop sockets, or credentials were introduced. Existing projects were not
read, copied, or modified. Network access remained on sanctioned paths; no
blocked-destination probes or direct-egress bypasses were attempted. No network
download was needed for this offline installation.

Any display run must use its own authentication cookie, disable TCP listeners,
avoid `-ac`/`xhost +`, and clean only its own processes and newly created IPC.
Do not weaken isolation or visibility restrictions to make a graphics test pass.

## Provisioning Before Acceptance

The original installation gaps are now addressed by the isolated prefix.
Before declaring the target accepted:

1. Preserve the pinned Linux x86_64 Godot 4.7.2 executable. The project verifies
   SHA256 `8d106cbe6144c2dc7e881d61d2429c1a8a76e6b22ef48bd5e48dcf934953f71e`.
   A workspace-local tool directory is sufficient; no root installation is needed.
2. Preserve standard `4.7.2.stable` export templates with `version.txt`,
   `linux_release.x86_64`, and `windows_release_x86_64.exe`. Configure the
   template directory explicitly; do not copy a broken host-specific symlink.
3. Obtain only the narrowly scoped temporary X11 IPC exception, if needed,
   then verify the installed CPU stack using actual Godot-rendered pixels.
   No host driver, device access, privileged mount, root remount, or network
   change is needed for Mesa llvmpipe.
4. Use the isolated Python/Pillow toolchain for the art pipeline. Preserve font
   licenses and authentic provenance; new art still follows the modular brief.
5. Verify the actual image-generation workflow with its sanctioned tool when
   production begins. Do not search credentials or private service configuration.

Existing GitHub HTTPS proxy access is the sanctioned route for upstream Godot
downloads. Network access was not tested here. Python's `python3 -m zipfile -e`
can extract official ZIP/TPZ archives without an unzip package.

Example paths **after operator provisioning and migration**:

```bash
# Run from the moved Make It Big checkout, not another project in the workspace.
cd /data/claude/workspace/makeitbig
source /data/claude/workspace/.tools/make-it-big/portable-cpu/env.sh
python3 scripts/devbox_preflight.py --project-root /data/claude/workspace/makeitbig --profile release --json
source scripts/project_env.sh
./scripts/check.sh
./scripts/container_build.sh
```

The preflight is read-only and reports prerequisite readiness only. It does not
install, migrate, export, deploy, or assert that the game passed.

## Required Acceptance After the Move

- Regenerate imports from the moved source, preserving stable save IDs and
  keeping test/play-session data separate from production saves.
- Freeze runtime/content during `container_build.sh`; require full tests,
  Linux/Windows exports, and empty-directory Linux smoke on that environment.
- Check `python3 scripts/devbox_preflight.py --profile visual --software-ok --json`
  with an authenticated owned display. Record **Godot's** llvmpipe/renderer
  output, not only `nvidia-smi` or the preliminary GL probe.
- Re-run authored-reveal pixel tests and the mounted modular preview. Inspect
  English UI, integer scaling, collisions, sorting, and reveal transitions.
  A headless GPU request is a skip, not a visual pass.
- Run native Windows smoke and golden replay through Windows CI. Linux
  cross-export alone is insufficient; signed/public distribution is separate.
- Generate packaging in an isolated local release root, verify checksums and
  page structure, and test the operator-approved download endpoint separately.

## Publication Boundary

Generating Linux/Windows files is not publishing them. The current host's
Tailscale page does not move with the checkout, and the sandbox must not configure
host Tailscale, expose new ports, or deploy another project's contract.

Use the sandbox's sanctioned AF Infra API if a publication service is later
requested. An operator-approved project/service/exposure/deployment contract,
access control, artifact verification, and an unsigned-binary policy are needed.
No registry entry, service, exposure, or deploy path was changed in this task.

<!-- Historical host identifiers in this document are sanitized examples; current service access comes from the approved directory or operator configuration. -->
