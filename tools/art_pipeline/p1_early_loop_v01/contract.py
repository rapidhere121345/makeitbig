"""Frozen ID contract for the P1 early-loop icon batch."""

from __future__ import annotations

from typing import Final


CELL_SIZE: Final = 32
ANCHOR: Final = [16, 16]
PADDING: Final = 2
MAX_VISIBLE: Final = 28
MAX_COLORS: Final = 12

GROUPS: Final = (
    ("equipment_slots", "equipment_slots.png", (2, 2)),
    ("equipment_bases", "equipment_bases.png", (2, 4)),
    ("skills_actions", "skills_actions.png", (2, 2)),
    ("runes_law", "runes_law.png", (2, 2)),
    ("white_cores", "white_cores.png", (2, 2)),
)

ENTRIES: Final = {
    "equipment_slots": (
        ("equipment_slot.main_hand", "main_hand", "content/early_items.json#prototype_open_slots", "主手", "equipment_slot", "equipment_slot"),
        ("equipment_slot.off_hand", "off_hand", "content/early_items.json#prototype_open_slots", "副手", "equipment_slot", "equipment_slot"),
        ("equipment_slot.gloves", "gloves", "content/early_items.json#prototype_open_slots", "手套", "equipment_slot", "equipment_slot"),
        ("equipment_slot.ring_1", "ring_1", "content/early_items.json#prototype_open_slots", "戒指一", "equipment_slot", "equipment_slot"),
    ),
    "equipment_bases": (
        ("equipment.ashwood_longbow", "ashwood_longbow", "content/early_items.json#base_items", "白蜡长弓", "equipment_base", "item"),
        ("equipment.swift_recurve_bow", "swift_recurve_bow", "content/early_items.json#base_items", "迅弦反曲弓", "equipment_base", "item"),
        ("equipment.lineage_quiver", "lineage_quiver", "content/early_items.json#base_items", "谱系箭袋", "equipment_base", "item"),
        ("equipment.farwatch_quiver", "farwatch_quiver", "content/early_items.json#base_items", "远望箭袋", "equipment_base", "item"),
        ("equipment.turnfeather_gloves", "turnfeather_gloves", "content/early_items.json#base_items", "导羽手套", "equipment_base", "item"),
        ("equipment.piercer_gloves", "piercer_gloves", "content/early_items.json#base_items", "穿弦手套", "equipment_base", "item"),
        ("equipment.hawk_eye_ring", "hawk_eye_ring", "content/early_items.json#base_items", "鹰眼戒指", "equipment_base", "item"),
        ("equipment.vitality_ring", "vitality_ring", "content/early_items.json#base_items", "生机戒指", "equipment_base", "item"),
    ),
    "skills_actions": (
        ("action.piercing_arrow", "piercing_arrow", "src/game/main.gd#framework_active_build.skills[0]", "穿刺箭", "combat_action", "skill"),
        ("action.hunter_mark", "hunter_mark", "src/game/main.gd#framework_active_build.skills[1]", "猎人印记", "combat_action", "skill"),
        ("action.dash", "dash", "src/game/main.gd#framework_active_build.skills[2]", "突袭", "combat_action", "skill"),
        ("action.basic_dodge", None, "docs/art-production/p1-calibration-v01/NEXT_BATCH.md#skills_actions", "闪避", "combat_action", "action"),
    ),
    "runes_law": (
        ("rune.breeding_split", "breeding_split", "content/early_items.json#runes", "孳生分裂", "semantic_modifier", "rune"),
        ("rune.branch_scale", "branch_scale", "content/early_items.json#runes", "分枝刻度", "semantic_modifier", "rune"),
        ("rune.afterimage_extension", "afterimage_extension", "content/early_items.json#runes", "掠影续时", "semantic_modifier", "rune"),
        ("law.pack_hunt_mark", "pack_hunt_mark", "content/early_items.json#laws", "群猎印记", "semantic_modifier", "law"),
    ),
    "white_cores": (
        ("core.near_enemy_horizon", "near_enemy_horizon", "content/proxy_components.json#cores", "近敌视界", "white_core", "proxy_core"),
        ("core.direct_gait", "direct_gait", "content/proxy_components.json#cores", "直趋步足", "white_core", "proxy_core"),
        ("core.single_key_execution", "single_key_execution", "content/proxy_components.json#cores", "单键执行", "white_core", "proxy_core"),
        ("core.short_trace_memory", "short_trace_memory", "content/proxy_components.json#cores", "短痕记忆", "white_core", "proxy_core"),
    ),
}

ALL_IDS: Final = tuple(entry[0] for group, _, _ in GROUPS for entry in ENTRIES[group])

