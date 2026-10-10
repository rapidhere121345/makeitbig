#!/usr/bin/env bash
set -euo pipefail

GODOT_BIN="${GODOT_BIN:-godot}"

RUNTIME_RESOURCE_VIOLATIONS="$(grep -R -n -E --include='*.gd' --include='*.tscn' 'preload\([[:space:]]*"res://(tools|build)/|load\([[:space:]]*"res://build/' src || true)"
if [[ -n "$RUNTIME_RESOURCE_VIOLATIONS" ]] || grep -q -E 'res://(tools|build)/' project.godot; then
  echo "Runtime code must not compile-link excluded tools/ or build/ resources:" >&2
  [[ -n "$RUNTIME_RESOURCE_VIOLATIONS" ]] && echo "$RUNTIME_RESOURCE_VIOLATIONS" >&2
  exit 1
fi

PRESET_COUNT="$(grep -Ec '^\[preset\.[0-9]+\]$' export_presets.cfg || true)"
TOOLS_EXCLUSION_COUNT="$(grep -Ec '^exclude_filter="[^"]*tools/\*' export_presets.cfg || true)"
TESTS_EXCLUSION_COUNT="$(grep -Ec '^exclude_filter="[^"]*tests/\*' export_presets.cfg || true)"
if [[ "$PRESET_COUNT" -lt 1 || "$TOOLS_EXCLUSION_COUNT" -ne "$PRESET_COUNT" || "$TESTS_EXCLUSION_COUNT" -ne "$PRESET_COUNT" ]]; then
  echo "Every export preset must exclude tools/* and tests/*." >&2
  exit 1
fi

"$GODOT_BIN" --headless --path . --import
"$GODOT_BIN" --headless --path . --script res://tests/run_all.gd
"$GODOT_BIN" --headless --path . --script res://tests/run_training_report_builder.gd
"$GODOT_BIN" --headless --path . --script res://tests/run_combat_state_codec.gd
"$GODOT_BIN" --headless --path . --script res://tests/unit/test_pixel_stage.gd
"$GODOT_BIN" --headless --path . --script res://tests/unit/test_game_root_stage.gd
"$GODOT_BIN" --headless --path . --script res://tests/test_town_exploration.gd
"$GODOT_BIN" --headless --path . --script res://tests/test_playtest_comfort.gd
"$GODOT_BIN" --headless --path . --script res://tests/test_session_menu.gd
"$GODOT_BIN" --headless --path . --script res://tests/test_character_progression.gd
"$GODOT_BIN" --headless --path . --script res://tests/test_talent_build.gd
"$GODOT_BIN" --headless --path . --script res://tests/test_talent_runtime.gd
"$GODOT_BIN" --headless --path . --script res://tests/unit/test_progression_icons.gd
"$GODOT_BIN" --headless --path . --script res://tests/unit/test_ui_style_r13.gd
"$GODOT_BIN" --headless --path . --script res://tests/test_character_screen.gd
"$GODOT_BIN" --headless --path . --script res://tests/unit/test_talent_board_refresh_r14.gd
"$GODOT_BIN" --headless --path . --script res://tests/test_story_progression.gd
"$GODOT_BIN" --headless --path . --script res://tests/test_story_evidence.gd
"$GODOT_BIN" --headless --path . --script res://tests/test_story_screen.gd
"$GODOT_BIN" --headless --path . --script res://tests/test_story_reading_flow.gd
"$GODOT_BIN" --headless --path . --script res://tests/test_character_story_integration.gd
"$GODOT_BIN" --headless --path . --script res://tests/unit/test_town_story_r14.gd
"$GODOT_BIN" --headless --path . --script res://tests/unit/test_capture_contract.gd
"$GODOT_BIN" --headless --path . --script res://tests/test_playtest_log.gd
"$GODOT_BIN" --headless --path . --script res://tests/test_early_campaign.gd
"$GODOT_BIN" --headless --path . --script res://tests/test_early_items.gd
"$GODOT_BIN" --headless --path . --script res://tests/test_early_skills.gd
"$GODOT_BIN" --headless --path . --script res://tests/test_player_readable_build.gd
"$GODOT_BIN" --headless --path . --script res://tests/test_player_facing_status.gd
"$GODOT_BIN" --headless --path . --script res://tests/test_build_resolver.gd
"$GODOT_BIN" --headless --path . --script res://tests/test_equipment_drop_generator.gd
"$GODOT_BIN" --headless --path . --script res://tests/test_combat_command_protocol.gd
"$GODOT_BIN" --headless --path . --script res://tests/test_manual_combat_input.gd
"$GODOT_BIN" --headless --path . --script res://tests/test_manual_aim_resolver.gd
"$GODOT_BIN" --headless --path . --script res://tests/test_walkable_geometry.gd
"$GODOT_BIN" --headless --path . --script res://tests/test_arena_walkable_bounds.gd
"$GODOT_BIN" --headless --path . --script res://tests/test_player_action_timeline.gd
"$GODOT_BIN" --headless --path . --script res://tests/test_enemy_tactics.gd
"$GODOT_BIN" --headless --path . --script res://tests/test_proxy_build.gd
"$GODOT_BIN" --headless --path . --script res://tests/test_proxy_decision.gd
"$GODOT_BIN" --headless --path . --script res://tests/test_combat_event_stream.gd
"$GODOT_BIN" --headless --path . --script res://tests/test_combat_presentation_events.gd
"$GODOT_BIN" --headless --path . --script res://tests/test_combat_feedback_audio.gd
"$GODOT_BIN" --headless --path . --script res://tests/test_enemy_runtime.gd
"$GODOT_BIN" --headless --path . --script res://tests/test_boss_duration.gd
"$GODOT_BIN" --headless --path . --script res://tests/unit/test_boss_action_pose.gd
"$GODOT_BIN" --headless --path . --script res://tests/unit/test_combat_marks.gd
"$GODOT_BIN" --headless --path . --script res://tests/unit/test_enemy_animation.gd
"$GODOT_BIN" --headless --path . --script res://tests/unit/test_combat_style_r13.gd
"$GODOT_BIN" --headless --path . --script res://tests/unit/test_hamlet_life_animation.gd
"$GODOT_BIN" --headless --path . --script res://tests/unit/test_hamlet_style_r13.gd
"$GODOT_BIN" --headless --path . --script res://tests/unit/test_hamlet_collision.gd
"$GODOT_BIN" --headless --path . --script res://tests/test_arena_hud.gd
"$GODOT_BIN" --headless --path . --script res://tests/test_input_feedback_transients.gd
"$GODOT_BIN" --headless --path . --script res://tests/test_ranger_combat_skills.gd
"$GODOT_BIN" --headless --path . --script res://tests/test_ranger_animation.gd
"$GODOT_BIN" --headless --path . --script res://tests/unit/test_ranger_motion_overlay.gd
"$GODOT_BIN" --headless --path . --script res://tests/test_world_occlusion.gd
"$GODOT_BIN" --headless --path . --script res://tests/test_scene_atmosphere.gd
"$GODOT_BIN" --headless --path . --script res://tests/test_defeat_presentation.gd
"$GODOT_BIN" --headless --path . --script res://tests/test_title_screen.gd
"$GODOT_BIN" --headless --path . --script res://tests/test_tutorial_screen.gd
"$GODOT_BIN" --headless --path . --script res://tests/test_tutorial_pointer_cast.gd
"$GODOT_BIN" --headless --path . --script res://tests/test_facility_screen.gd
"$GODOT_BIN" --headless --path . --script res://tests/test_inventory_flow.gd
"$GODOT_BIN" --headless --path . --script res://tests/unit/test_equipment_backpack_paging.gd
"$GODOT_BIN" --headless --path . --script res://tests/unit/test_equipment_presentation_model.gd
"$GODOT_BIN" --headless --path . --script res://tests/test_test_console.gd
"$GODOT_BIN" --headless --path . --script res://tests/unit/test_training_trace_view.gd
"$GODOT_BIN" --headless --path . --script res://tests/test_facility_art.gd
"$GODOT_BIN" --headless --path . --script res://tests/unit/test_facility_override_contract.gd
"$GODOT_BIN" --headless --path . --script res://tests/unit/test_facility_layout.gd
"$GODOT_BIN" --headless --path . --script res://tests/unit/test_facility_detail_state.gd
"$GODOT_BIN" --headless --path . --script res://tests/unit/test_pixel_grid_icon.gd
"$GODOT_BIN" --headless --path . --script res://tests/test_workbench_layout.gd
"$GODOT_BIN" --headless --path . --script res://tests/test_item_forge.gd
"$GODOT_BIN" --headless --path . --script res://tests/test_contract_screen.gd
"$GODOT_BIN" --headless --path . --script res://tests/test_result_screen.gd
"$GODOT_BIN" --headless --path . --script res://tests/test_contract_result_navigation.gd
"$GODOT_BIN" --headless --path . --script res://tests/unit/test_result_layout.gd
"$GODOT_BIN" --headless --path . --script res://tests/unit/test_result_evidence.gd
"$GODOT_BIN" --headless --path . --script res://tests/unit/test_settlement_route_view.gd
"$GODOT_BIN" --headless --path . --script res://tests/test_ending_screen.gd
"$GODOT_BIN" --headless --path . --script res://tests/test_contract_run_controller.gd
"$GODOT_BIN" --headless --path . --script res://tests/test_legacy_arena_adapter.gd
"$GODOT_BIN" --headless --path . --script res://tests/run_game_flow_smoke.gd

STATE_DIR="${MIB_TEST_STATE_DIR:-$(pwd -P)/build/test-state}"
mkdir -p "$STATE_DIR"
EXPECTED_HASH=""
for RENDER_RATE in 30 60 144; do
  HASH_PATH="$STATE_DIR/${RENDER_RATE}hz.sha256"
  "$GODOT_BIN" --headless --fixed-fps "$RENDER_RATE" --path . -- \
    --auto-smoke "--state-hash-out=$HASH_PATH"
  ACTUAL_HASH="$(tr -d '\r\n' < "$HASH_PATH")"
  if [[ -z "$EXPECTED_HASH" ]]; then
    EXPECTED_HASH="$ACTUAL_HASH"
  elif [[ "$ACTUAL_HASH" != "$EXPECTED_HASH" ]]; then
    echo "Render-rate replay mismatch: 30Hz=$EXPECTED_HASH ${RENDER_RATE}Hz=$ACTUAL_HASH" >&2
    exit 1
  fi
done
echo "PASS  30/60/144Hz full automation replay: $EXPECTED_HASH"

PRESENTATION_OFF_HASH_PATH="$STATE_DIR/presentation-off-60hz.sha256"
"$GODOT_BIN" --headless --fixed-fps 60 --path . -- \
  --auto-smoke --presentation-off "--state-hash-out=$PRESENTATION_OFF_HASH_PATH"
PRESENTATION_OFF_HASH="$(tr -d '\r\n' < "$PRESENTATION_OFF_HASH_PATH")"
if [[ "$PRESENTATION_OFF_HASH" != "$EXPECTED_HASH" ]]; then
  echo "Presentation-off replay mismatch: normal=$EXPECTED_HASH off=$PRESENTATION_OFF_HASH" >&2
  exit 1
fi
echo "PASS  presentation-off 60Hz replay: $PRESENTATION_OFF_HASH"
