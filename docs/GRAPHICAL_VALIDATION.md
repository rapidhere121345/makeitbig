# Graphical Acceptance Environment

Windowed rendering and headless regression are separate acceptance paths. Paseo manages agents/workspaces; project scripts do not start Docker. A discrete GPU is not required for UI, collision, sorting, or authored-reveal acceptance: the devbox may use CPU software rendering.

## Execution Paths

| Path | Entry | Renderer | Purpose |
| --- | --- | --- | --- |
| CPU virtual display | Xvfb plus `LIBGL_ALWAYS_SOFTWARE=1` | Mesa llvmpipe | UI, input, screenshots, sorting, reveal pixels |
| Connected window | `"$GODOT_BIN" --editor --path .` | Actual configured renderer | Interactive debugging and graphical review |
| Optional hardware path | Verified integrated/discrete GPU | Actual driver | Hardware-specific behavior/performance only |
| Headless | `./scripts/container_build.sh` | No rendered window | Regressions, exports, empty-directory Linux smoke |

Use `GODOT_BIN` resolved by `project_env.sh` for every path.

llvmpipe renders actual pixels and is valid for visual correctness, focus, input, and shader regression. Its frame rate, latency, and resource use are not integrated/discrete GPU performance evidence. An integrated GPU is optional and distinct from CPU software rendering. Always identify the renderer actually used.

## Window Acceptance

Run at most one graphical Godot instance at a time. Check for existing instances, reuse one window throughout a review, and exit normally.

With a connected display:

```bash
cd /data/claude/workspace/makeitbig
source /data/claude/workspace/.tools/make-it-big/portable-cpu/env.sh
source scripts/project_env.sh
test -n "${DISPLAY:-}"
"$GODOT_BIN" --display-driver x11 --rendering-method gl_compatibility --editor --path "$MIB_PROJECT_ROOT"
```

The operator manages the display service. Record the actual `DISPLAY` and authentication setup for Xvfb; do not expose authorization contents. A virtual display is not physical-desktop or hardware-performance evidence.

A nonempty `DISPLAY` does not prove connectivity: use `xdpyinfo`. If the display cannot connect, keep graphics acceptance pending and continue headless testing.

Check project loading, scene-tree visibility, and major screens. Run the game in the same environment:

```bash
"$GODOT_BIN" --display-driver x11 --rendering-method gl_compatibility --path "$MIB_PROJECT_ROOT"
```

Use `tools/play_session.gd` and `tools/play_session.py` for input and captures. Set `MIB_PLAY_SESSION_DIR` to an ignored `build/current/` directory first. Window checks do not replace `./scripts/container_build.sh`: require headless regression, both exports, and empty-directory Linux smoke too.

## CPU Rendering in the Devbox

The approved prefix already supplies Xvfb, X11 utilities, and Mesa/GL libraries.
Connect an owned, authenticated display with TCP disabled, then run:

```bash
source /data/claude/workspace/.tools/make-it-big/portable-cpu/env.sh
source scripts/project_env.sh
test -n "${DISPLAY:-}"
xdpyinfo -display "$DISPLAY" >/dev/null
LIBGL_ALWAYS_SOFTWARE=1 __GLX_VENDOR_LIBRARY_NAME=mesa \
  "$GODOT_BIN" --display-driver x11 --rendering-method gl_compatibility \
  --audio-driver Dummy --path "$MIB_PROJECT_ROOT"
```

Require Godot's startup output to identify llvmpipe/software rendering; do not assume these variables succeeded. Validate English layout at 1280x720 and 1600x900, keyboard focus, scrolling, integer pixel scaling, animations, collisions, and reveal transitions.

`python3 scripts/devbox_preflight.py --profile visual --software-ok --json`
accepts software rendering as a prerequisite. It is not a screenshot review.
`tests/test_scene_atmosphere.gd -- --gpu` is a historical flag name for rendered
pixel checks: it may use software GL, but an explicitly skipped headless run
must not be counted as rendered acceptance.

## Private Display Authentication

Portable wrappers restore the prefix's private Xauthority path:
`/data/claude/workspace/.tools/make-it-big/portable-cpu/run/Xauthority`.
Align the owned server and clients with that path without logging or copying
its contents. Start Xvfb with private authentication and `-nolisten tcp`;
never use `-ac` or `xhost +`. Clean only owned processes and their temporary
IPC/authentication files. File mode `0600` does not isolate mutually untrusted
processes sharing the same UID.

## Retained Acceptance

See [acceptance records](playtest/README.md) for the devbox migration,
modular-town foundation, and historical gaps to recheck. Historical host
commands and screenshots are not instructions to resume work in the rollback
checkout or expose the host desktop.

## Delivery Records

For each review, record the date, display path, Godot version, renderer, checked scenes, input sequence, and exit code. Keep current screenshots/temporary recordings in ignored `build/`; long-lived visual-direction references belong in `docs/art-production/concepts/` with provenance.
