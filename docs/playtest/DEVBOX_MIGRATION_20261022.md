# Devbox Migration Acceptance - 2026-10-22

## Scope and Transfer

The operator authorized network/English rechecks followed by migration.
The working checkout is `/data/claude/workspace/makeitbig` in the existing
`example-devbox`; `/data/paseo-makeitbig/project` remains the unchanged rollback
checkout. No container, network, mount, or public service was created.

An offline Git bundle preserved complete reachable history. The target clone
started at `6d9c253dd57744a29f58e97fb2d01fce26d2dd68`, with source tree
`67721cf39c88ee305c4c821dddc7b15d1d5c02d9` matching the original.
Bundle SHA256:
`7ab5b5c35c45c8d45f68b281794eb2c34ba8966c6c6dceddef21771591f0c22c`.
The clone's origin is the workspace-local migration bundle, not an authenticated
upstream URL. No Git push occurred.

Private Git configuration, credentials, production saves, old build output,
and `.godot` were not copied. Imports and exports were generated anew.
Only operational documentation changes follow the tested source baseline.

## Network and English Checks

- The HTTPS proxy resolves to the approved `code-egress`; GitHub is not bypassed.
- Allowed positive checks pass: control-plane health HTTP 200; GitHub HTTPS
  HTTP 200, proxy CONNECT 200, TLS verification result 0.
- No direct-egress, prohibited-host, provider-key, or credential probes occurred.
  This is not a penetration audit or proof against every exfiltration scenario.
- The initial 697-file English audit has zero unexpected Han findings. Four
  pinned authentic license/provenance originals deliberately remain unchanged;
  neither historical Git objects nor user-generated text is claimed Han-free.
- Sixteen production-route captures scan visible control text and tooltips at
  1280x720 and 1600x900; every scan reports zero unexpected Han nodes.
- After updating entry instructions and this report, the final source audit
  checks 699 files with zero errors and the same four pinned originals.

## Actual Target Full Gate

UID 1000, PID/PGID 216293, start 2026-10-22T14:28:07-07:00, finish
14:36:28-07:00. Explicit `build/current/migration-full-gate.exit` contains 0.
The wrapper fingerprints the bytes of tracked and untracked runtime inputs;
before/after values match:
`8fefecbd859e54b1e90b9b016d5b2e34b70b30f2e342509359067fe35060b1f4`.

English/policy/preflight checks, import, aggregate tests, story reading flow,
workbench layout, room integration, and the full 600-room matrix pass.
The matrix records 600 victories, seeds 0..99, and 33,894 ticks.
There are no `SCRIPT ERROR:` lines. Fresh Linux/Windows exports and the native
Linux empty-directory launch pass, followed by `host build flow passed`.

| Game artifact | Bytes | SHA256 |
| --- | ---: | --- |
| Linux x86-64 | 123996232 | `31ffd13facee596cc510eb73ffbdd03fa0560f76a4a2e7ee8319aead088dad07` |
| Windows x86-64 | 159604504 | `a46a9b13a75cd414c7ac291e53d046c1713ec615ad48296be8cf4a9e86081fa8` |

These are fresh target exports, not expected to be byte-identical to previous
host exports. Windows export is not native Windows execution.

## Actual Target Graphical Acceptance

Godot 4.7.2 uses Mesa llvmpipe LLVM 21.1.8/OpenGL 4.5 on the owned private
display `:199`, with TCP disabled and private authentication.

`build/current/migration-graphics.z_81c3sm/report.json` reports exit 0 for
title, tutorial, Hearthside, loadout, forge, training, proxy, and contract at
both resolutions: 16 actual PNGs. Requested and actual routes agree.
The real production entry is instantiated; setup uses public capture fixtures,
not a claimed human quest playthrough or an unlocked Forge victory.
Visible text/tooltip audits all pass. Representative PNGs were inspected.

The display-backed facility concept/detail probe also passes, producing five
PNGs at 1280x720 and 1024x576, with all frame/18px-font audits clean.
The owned Xvfb PID/group 229179 is reaped, exit 0; its socket, lock, and test
cookie do not remain. No host desktop was accessed.

The earlier ignored `migration-graphics.ej3x4kjs/` attempt is retained: the
ad-hoc harness selected an authentication path that portable wrappers override.
The harness was corrected to use the toolchain's private authentication path;
no access-control, proxy, permission, or game-code workaround was introduced.

## Local Release and Resource Verification

The new ignored root `build/current/migration-release-check.QgN5c1`, build
`20261022-214356-6d9c253dd577`, passes package/index/site generation, SHA256
deep verification, Tailscale static validation, and staging `--check`.
No old releases were pruned, server exposed, or release published.

On the operator's further request, the devbox was increased from 8 CPU-equivalents
and 16 GiB RAM to 16 CPU-equivalents and 32 GiB RAM, retaining an 8 GiB swap
allowance (`MemorySwap=40 GiB`). CPU is a quota, not exclusive physical cores.
PID 2198395 and start time `2026-10-22T04:28:00.728272595Z` are unchanged.
The selected network/privilege/mount-count/IPC boundary snapshots match
before and after; no restart or isolation relaxation occurred.
Native Linux smoke is repeated successfully after the increase; the target
release-prerequisite audit reports `ready`, with no failed checks.

Sanitized network, resource, and boundary records are archived under ignored
`build/current/migration-audit/`. The operator should sync the new working path
and resource policy into the authoritative infrastructure registry/configuration
before future recreation. No registry, Compose, or unrelated-project edits were made.

Native Windows acceptance, long-run/performance certification, production town
art, legacy cold-bake drift, signing/hosting/ACL review, and publication remain
separate work. The preparation report documents those existing scope limits.

<!-- Historical host identifiers in this document are sanitized examples; current service access comes from the approved directory or operator configuration. -->
