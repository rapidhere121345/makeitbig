# Graphical Acceptance Environment

Windowed rendering and headless regression are separate acceptance paths. Paseo manages agents/workspaces; project scripts do not start Docker. A discrete GPU is not required for UI, collision, sorting, or authored-reveal acceptance: the devbox may use CPU software rendering.

## Execution Paths

| Path | Entry | Renderer | Purpose |
| --- | --- | --- | --- |
| CPU virtual display | Xvfb plus `LIBGL_ALWAYS_SOFTWARE=1` | Mesa llvmpipe | UI, input, screenshots, sorting, reveal pixels |
| Connected window | `"$GODOT_BIN" --editor --path .` | Actual configured renderer | Interactive debugging and graphical review |
| Optional hardware path | Verified integrated/discrete GPU | Actual driver | Hardware-specific behavior/performance only |
| Headless | `./scripts/container_build.sh` | No rendered window | Regressions, exports, empty-directory Linux smoke |

Use `GODOT_BIN` resolved by `project_env.sh` for every path. A previous host hardware run recorded:

```text
OpenGL 3.3 NVIDIA 595.91.07
NVIDIA GeForce RTX 4080 SUPER
exitCode=0
```

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

## Historical NVIDIA Probe: 2026-10-17

The original host has AMD and NVIDIA RTX 4080 SUPER GPUs. Its default X11/zink path could use AMD or crash a play-session process; those launches were not RTX evidence. A working optional NVIDIA PRIME path was:

```bash
cd /data/paseo-makeitbig/project
source scripts/project_env.sh
test -n "${DISPLAY:-}"
__NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia \
  "$GODOT_BIN" --display-driver x11 --rendering-method gl_compatibility --path "$MIB_PROJECT_ROOT"
```

This path reported `OpenGL 3.3 NVIDIA` and `NVIDIA GeForce RTX 4080 SUPER`, with stable play-session startup. The same variables worked for the editor.

Record renderer/GPU strings, exit code, and actual DISPLAY for windowed tests. Non-RTX results remain valid for their actual renderer but must not be called RTX validation. For hardware-specific review, window tests such as `test_combat_room_runtime.gd` and `test_presentation_production_assembly.gd` can use:

```bash
__NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia \
  "$GODOT_BIN" --display-driver x11 --rendering-method gl_compatibility --path . \
  --script res://tests/test_presentation_production_assembly.gd
```

If this optional hardware path fails, use the CPU path for visual correctness and keep hardware-specific checks pending. Never relabel software output as RTX evidence.

## Historical Movement and Projectile Review

Record display, Godot version, renderer/GPU, audio backend, and exit code. Headless outcomes cannot replace window review. The following records predate English migration; quoted UI is translated here, not a claim that historical screenshots were English.

From an isolated playtest save, the player entered Hearthside, walked to the Contract Board with WASD, pressed E, and departed for the Shattered Outpost in Manual mode. The combat HUD rendered at 1280x720 and 1600x900, with readable sans-serif Chinese text, health, controls, and outlines, without clipping or panel overlap. Four leftward walking samples showed alternating legs and changing cloth silhouettes without decoration covering the legs. Space fired an arrow, reducing enemy health from 720 to 488.116; Shift+A dodge and cooldown display worked. This proved software-rendered pixels and input, not a physical desktop, NVIDIA performance, or native Windows behavior.

Evidence lives in ignored `build/current/play-session-review/`: `engine.log`, `input.jsonl`, `west-walk-strip.png`, and `hud-1600x900.png`. The four-frame strip crops consecutive screenshots around the character and enlarges pixels for inspection. An earlier pre-hit projectile frame remains at `build/current/play-session/projectile-flight.png`; a post-hit image is not new in-flight evidence.

## Historical Town Retest: 2026-10-10

Acceptance windows ran sequentially on one Xvfb display. The player walked from the saved spawn across every bridge waypoint and back using WASD, without teleporting. After a visual correction to the south bridge boundary, 55 frames of down-left input from `(1299.696, 772.9811)` stopped at `(1277.329, 774.9442)`, feet remaining inside the bridge rather than entering water. Both directions around the entrance lamp and through the central passage remained traversable. The source is 1536x1024 and the world 1536x960; collision points and routes require UV conversion.

Approaching Iven showed "[E] Talk to Iven"; pressing E opened three dialogue lines and focused Continue. Esc returned to town. Sustained movement into the Contract Board wall was blocked. Targeted town regressions also covered roof/tower samples, all facility routes, and occlusion stacks.

Screenshots were used to move forge fire back into the hearth and remove an incorrect yellow glow beside the anvil, retaining small sparks and subtle flicker. Two fixed-camera hearth samples 36 rendered frames apart differed at 952 pixels; animation did not depend on player movement. The window exited 0 using Dummy audio. Evidence in the same ignored directory: `bridge-final-rail.png`, `npc-prompt.png`, `npc-dialogue.png`, `forge-final-0.png`, `forge-final-1.png`, `forge-flicker-pair.png`, and `final-town-engine.log`.

## Delivery Records

For each review, record the date, display path, Godot version, renderer, checked scenes, input sequence, and exit code. Keep current screenshots/temporary recordings in ignored `build/`; long-lived visual-direction references belong in `docs/art-production/concepts/` with provenance.
