$ErrorActionPreference = "Stop"
$GodotBin = if ($env:GODOT_BIN) { $env:GODOT_BIN } else { "godot" }

$RuntimeFiles = Get-ChildItem -Path src -Recurse -File -Include *.gd,*.tscn
if ($RuntimeFiles | Select-String -Pattern 'preload\(\s*"res://(tools|build)/|load\(\s*"res://build/' -Quiet) {
    throw "Runtime code must not compile-link excluded tools/ or build/ resources."
}
if (Select-String -Path project.godot -Pattern 'res://(tools|build)/' -Quiet) {
    throw "project.godot must not reference excluded tools/ or build/ resources."
}
$ExportPresets = Get-Content export_presets.cfg -Raw
$PresetCount = [regex]::Matches($ExportPresets, '(?m)^\[preset\.\d+\]$').Count
$ExportFilters = [regex]::Matches($ExportPresets, '(?m)^exclude_filter="([^"]*)"$')
if ($PresetCount -lt 1 -or $ExportFilters.Count -ne $PresetCount) {
    throw "Every export preset must declare an exclude_filter."
}
foreach ($FilterMatch in $ExportFilters) {
    $Filter = $FilterMatch.Groups[1].Value
    if ($Filter -notmatch '(^|,)tools/\*(,|$)' -or $Filter -notmatch '(^|,)tests/\*(,|$)') {
        throw "Every export preset must exclude tools/* and tests/*."
    }
}

& $GodotBin --headless --path . --import
if ($LASTEXITCODE -ne 0) { throw "Godot import failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/run_all.gd
if ($LASTEXITCODE -ne 0) { throw "Godot tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_runtime_world.gd
if ($LASTEXITCODE -ne 0) { throw "Runtime world tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_combat_simulation.gd
if ($LASTEXITCODE -ne 0) { throw "Combat simulation tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_arena_presenter.gd
if ($LASTEXITCODE -ne 0) { throw "Arena presenter tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_arena_actor_presenter.gd
if ($LASTEXITCODE -ne 0) { throw "Arena actor presenter tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_arena_combat_presenter.gd
if ($LASTEXITCODE -ne 0) { throw "Arena combat presenter tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_actor_motor.gd
if ($LASTEXITCODE -ne 0) { throw "Actor motor tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_player_motion_system.gd
if ($LASTEXITCODE -ne 0) { throw "Player motion system tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_player_combat_state.gd
if ($LASTEXITCODE -ne 0) { throw "test_player_combat_state failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_player_combat_rules.gd
if ($LASTEXITCODE -ne 0) { throw "test_player_combat_rules failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_room_definition.gd
if ($LASTEXITCODE -ne 0) { throw "Room definition tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_room_catalog.gd
if ($LASTEXITCODE -ne 0) { throw "Room catalog tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_rebuild_samples.gd
if ($LASTEXITCODE -ne 0) { throw "Rebuild sample tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_native_concave_sample.gd
if ($LASTEXITCODE -ne 0) { throw "test_native_concave_sample failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_town_geometry_rebuild.gd
if ($LASTEXITCODE -ne 0) { throw "Town geometry rebuild tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_town_native_contract.gd
if ($LASTEXITCODE -ne 0) { throw "test_town_native_contract failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_town_runtime.gd
if ($LASTEXITCODE -ne 0) { throw "test_town_runtime failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/run_training_report_builder.gd
if ($LASTEXITCODE -ne 0) { throw "Training report builder tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/run_combat_state_codec.gd
if ($LASTEXITCODE -ne 0) { throw "Combat state codec tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/unit/test_pixel_stage.gd
if ($LASTEXITCODE -ne 0) { throw "Pixel stage tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/unit/test_game_root_stage.gd
if ($LASTEXITCODE -ne 0) { throw "GameRoot stage tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_town_exploration.gd
if ($LASTEXITCODE -ne 0) { throw "Town exploration tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_playtest_comfort.gd
if ($LASTEXITCODE -ne 0) { throw "Playtest comfort tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_session_menu.gd
if ($LASTEXITCODE -ne 0) { throw "Session menu tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_character_progression.gd
if ($LASTEXITCODE -ne 0) { throw "Character progression test failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_talent_build.gd
if ($LASTEXITCODE -ne 0) { throw "Talent build test failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_talent_runtime.gd
if ($LASTEXITCODE -ne 0) { throw "Growth/story test failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/unit/test_progression_icons.gd
if ($LASTEXITCODE -ne 0) { throw "Progression icon test failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_character_screen.gd
if ($LASTEXITCODE -ne 0) { throw "Growth/story test failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/unit/test_talent_board_refresh_r14.gd
if ($LASTEXITCODE -ne 0) { throw "Talent board refresh R14 tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_story_progression.gd
if ($LASTEXITCODE -ne 0) { throw "Story progression test failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_story_evidence.gd
if ($LASTEXITCODE -ne 0) { throw "Growth/story test failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_story_screen.gd
if ($LASTEXITCODE -ne 0) { throw "Growth/story test failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_story_reading_flow.gd
if ($LASTEXITCODE -ne 0) { throw "Story reading flow test failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_character_story_integration.gd
if ($LASTEXITCODE -ne 0) { throw "Growth/story test failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/unit/test_town_story_r14.gd
if ($LASTEXITCODE -ne 0) { throw "Town story R14 tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/unit/test_capture_contract.gd
if ($LASTEXITCODE -ne 0) { throw "Capture contract tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_playtest_log.gd
if ($LASTEXITCODE -ne 0) { throw "Playtest log tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_early_campaign.gd
if ($LASTEXITCODE -ne 0) { throw "Early campaign tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_early_items.gd
if ($LASTEXITCODE -ne 0) { throw "Early item tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_early_skills.gd
if ($LASTEXITCODE -ne 0) { throw "Early skill tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_player_readable_build.gd
if ($LASTEXITCODE -ne 0) { throw "Player-readable build tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_player_facing_status.gd
if ($LASTEXITCODE -ne 0) { throw "Player-facing status tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_build_resolver.gd
if ($LASTEXITCODE -ne 0) { throw "Build resolver tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_equipment_drop_generator.gd
if ($LASTEXITCODE -ne 0) { throw "Equipment drop generator tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_combat_command_protocol.gd
if ($LASTEXITCODE -ne 0) { throw "Combat command protocol tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_combat_command_router.gd
if ($LASTEXITCODE -ne 0) { throw "Combat command router tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_manual_combat_input.gd
if ($LASTEXITCODE -ne 0) { throw "Manual combat input tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_manual_aim_resolver.gd
if ($LASTEXITCODE -ne 0) { throw "Manual aim resolver tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_arena_geometry.gd
if ($LASTEXITCODE -ne 0) { throw "Arena geometry tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_arena_geometry_runtime.gd
if ($LASTEXITCODE -ne 0) { throw "Arena geometry runtime tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_combat_query.gd
if ($LASTEXITCODE -ne 0) { throw "Combat query tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_encounter_director.gd
if ($LASTEXITCODE -ne 0) { throw "Encounter director tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_combat_system.gd
if ($LASTEXITCODE -ne 0) { throw "Combat system tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_combat_presentation_boundary.gd
if ($LASTEXITCODE -ne 0) { throw "test_combat_presentation_boundary failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_main_player_wiring.gd
if ($LASTEXITCODE -ne 0) { throw "test_main_player_wiring failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_main_input_release.gd
if ($LASTEXITCODE -ne 0) { throw "test_main_input_release failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_main_presentation_closeout.gd
if ($LASTEXITCODE -ne 0) { throw "test_main_presentation_closeout failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_arena_walkable_bounds.gd
if ($LASTEXITCODE -ne 0) { throw "Arena walkable bounds tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_player_action_timeline.gd
if ($LASTEXITCODE -ne 0) { throw "Player action timeline tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_enemy_tactics.gd
if ($LASTEXITCODE -ne 0) { throw "Enemy tactics tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_proxy_build.gd
if ($LASTEXITCODE -ne 0) { throw "Proxy build tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_proxy_decision.gd
if ($LASTEXITCODE -ne 0) { throw "Proxy decision tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_proxy_intent_system.gd
if ($LASTEXITCODE -ne 0) { throw "Proxy intent system tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_combat_event_stream.gd
if ($LASTEXITCODE -ne 0) { throw "Combat event stream tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_combat_presentation_events.gd
if ($LASTEXITCODE -ne 0) { throw "Combat presentation event tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_combat_feedback_audio.gd
if ($LASTEXITCODE -ne 0) { throw "Combat feedback audio tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_enemy_runtime.gd
if ($LASTEXITCODE -ne 0) { throw "Enemy runtime tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_boss_duration.gd
if ($LASTEXITCODE -ne 0) { throw "Boss duration tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_boss_parts_combat.gd
if ($LASTEXITCODE -ne 0) { throw "test_boss_parts_combat failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_boss_parts_presentation.gd
if ($LASTEXITCODE -ne 0) { throw "test_boss_parts_presentation failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/unit/test_boss_action_pose.gd
if ($LASTEXITCODE -ne 0) { throw "Boss pose tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/unit/test_combat_marks.gd
if ($LASTEXITCODE -ne 0) { throw "Combat mark tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/unit/test_enemy_animation.gd
if ($LASTEXITCODE -ne 0) { throw "Enemy animation tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/unit/test_combat_style_r13.gd
if ($LASTEXITCODE -ne 0) { throw "Combat R13 style tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/unit/test_hamlet_life_animation.gd
if ($LASTEXITCODE -ne 0) { throw "Hamlet life tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/unit/test_hamlet_style_r13.gd
if ($LASTEXITCODE -ne 0) { throw "Hamlet R13 style tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/unit/test_town_geometry.gd
if ($LASTEXITCODE -ne 0) { throw "Town geometry tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/unit/test_ui_style_r13.gd
if ($LASTEXITCODE -ne 0) { throw "UI R13 style tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_arena_hud.gd
if ($LASTEXITCODE -ne 0) { throw "Arena HUD tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_input_feedback_transients.gd
if ($LASTEXITCODE -ne 0) { throw "Input feedback transient tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_ranger_combat_skills.gd
if ($LASTEXITCODE -ne 0) { throw "Ranger combat skill tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_ranger_animation.gd
if ($LASTEXITCODE -ne 0) { throw "Ranger animation tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/unit/test_ranger_motion_overlay.gd
if ($LASTEXITCODE -ne 0) { throw "Ranger motion overlay tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_world_occlusion.gd
if ($LASTEXITCODE -ne 0) { throw "World occlusion tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_scene_atmosphere.gd
if ($LASTEXITCODE -ne 0) { throw "Scene atmosphere tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_defeat_presentation.gd
if ($LASTEXITCODE -ne 0) { throw "Defeat presentation tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_title_screen.gd
if ($LASTEXITCODE -ne 0) { throw "Title screen tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_tutorial_screen.gd
if ($LASTEXITCODE -ne 0) { throw "Tutorial screen tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_tutorial_pointer_cast.gd
if ($LASTEXITCODE -ne 0) { throw "Tutorial pointer cast tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_facility_screen.gd
if ($LASTEXITCODE -ne 0) { throw "Facility screen tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_inventory_flow.gd
if ($LASTEXITCODE -ne 0) { throw "Inventory flow test failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/unit/test_equipment_backpack_paging.gd
if ($LASTEXITCODE -ne 0) { throw "Equipment backpack paging tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/unit/test_equipment_presentation_model.gd
if ($LASTEXITCODE -ne 0) { throw "Equipment presentation model tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_test_console.gd
if ($LASTEXITCODE -ne 0) { throw "Test console tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/unit/test_training_trace_view.gd
if ($LASTEXITCODE -ne 0) { throw "Training trace tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_facility_art.gd
if ($LASTEXITCODE -ne 0) { throw "Facility art tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/unit/test_facility_override_contract.gd
if ($LASTEXITCODE -ne 0) { throw "Facility override contract tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/unit/test_facility_layout.gd
if ($LASTEXITCODE -ne 0) { throw "Facility layout tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/unit/test_facility_detail_state.gd
if ($LASTEXITCODE -ne 0) { throw "Facility detail-state tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/unit/test_pixel_grid_icon.gd
if ($LASTEXITCODE -ne 0) { throw "Pixel grid icon tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_workbench_layout.gd
if ($LASTEXITCODE -ne 0) { throw "Workbench geometry tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_item_forge.gd
if ($LASTEXITCODE -ne 0) { throw "Item forge tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_contract_screen.gd
if ($LASTEXITCODE -ne 0) { throw "Contract screen tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_result_screen.gd
if ($LASTEXITCODE -ne 0) { throw "Result screen tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_contract_result_navigation.gd
if ($LASTEXITCODE -ne 0) { throw "Contract/result navigation tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/unit/test_result_layout.gd
if ($LASTEXITCODE -ne 0) { throw "Result layout tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/unit/test_result_evidence.gd
if ($LASTEXITCODE -ne 0) { throw "Result evidence tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/unit/test_settlement_route_view.gd
if ($LASTEXITCODE -ne 0) { throw "Settlement route tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_ending_screen.gd
if ($LASTEXITCODE -ne 0) { throw "Ending screen tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_contract_run_controller.gd
if ($LASTEXITCODE -ne 0) { throw "Contract run controller tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_combat_room_runtime.gd
if ($LASTEXITCODE -ne 0) { throw "Combat room runtime tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_real_combat_domains.gd
if ($LASTEXITCODE -ne 0) { throw "Real combat domain tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_real_combat_room.gd
if ($LASTEXITCODE -ne 0) { throw "Real mounted combat room tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_repeatable_encounter_matrix.gd
if ($LASTEXITCODE -ne 0) { throw "Repeatable encounter matrix failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_combat_room_rules.gd
if ($LASTEXITCODE -ne 0) { throw "test_combat_room_rules failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_smoke_input_driver.gd
if ($LASTEXITCODE -ne 0) { throw "test_smoke_input_driver failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_combat_state_snapshot_builder.gd
if ($LASTEXITCODE -ne 0) { throw "test_combat_state_snapshot_builder failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_combat_room_result.gd
if ($LASTEXITCODE -ne 0) { throw "Combat room result tests failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/test_result_roundtrip.gd
if ($LASTEXITCODE -ne 0) { throw "test_result_roundtrip failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/run_game_flow_smoke.gd
if ($LASTEXITCODE -ne 0) { throw "Game flow smoke failed with exit code $LASTEXITCODE" }

$StateDir = if ($env:MIB_TEST_STATE_DIR) { $env:MIB_TEST_STATE_DIR } else { Join-Path (Get-Location) "build/test-state" }
New-Item -ItemType Directory -Force -Path $StateDir | Out-Null
# Frozen historical automation hash, recorded before the runtime replacement.
$ExpectedHash = "5bd724ca9f69585d8b2dfce6746e615840045ab0fa0295544b0f8c8fe6e0a900"
$HistoricalReplayProfile = "historical_circle_v1"
foreach ($RenderRate in 30, 60, 144) {
    $HashPath = Join-Path $StateDir "${RenderRate}hz.sha256"
    & $GodotBin --headless --fixed-fps $RenderRate --path . -- --auto-smoke "--replay-geometry-profile=$HistoricalReplayProfile" "--state-hash-out=$HashPath"
    if ($LASTEXITCODE -ne 0) { throw "${RenderRate}Hz replay failed with exit code $LASTEXITCODE" }
    $ActualHash = (Get-Content $HashPath -Raw).Trim()
    if ($ActualHash -ne $ExpectedHash) {
        throw "Historical replay mismatch: golden=$ExpectedHash ${RenderRate}Hz=$ActualHash"
    }
}
Write-Output "PASS  30/60/144Hz full automation replay: $ExpectedHash"

$PresentationOffHashPath = Join-Path $StateDir "presentation-off-60hz.sha256"
& $GodotBin --headless --fixed-fps 60 --path . -- --auto-smoke --presentation-off "--replay-geometry-profile=$HistoricalReplayProfile" "--state-hash-out=$PresentationOffHashPath"
if ($LASTEXITCODE -ne 0) { throw "Presentation-off replay failed with exit code $LASTEXITCODE" }
$PresentationOffHash = (Get-Content $PresentationOffHashPath -Raw).Trim()
if ($PresentationOffHash -ne $ExpectedHash) {
    throw "Presentation-off replay mismatch: normal=$ExpectedHash off=$PresentationOffHash"
}
Write-Output "PASS  presentation-off 60Hz replay: $PresentationOffHash"
