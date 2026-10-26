extends RefCounted
## Approved 2026-09-14 production skin:
## cold slate greys, bone information, old-copper accents, danger red for hostile
## telegraphs and cold teal for proxy/ally state. Presentation only: nothing here
## is read by simulation, damage, drops or AI.

const SharedPalette := preload("res://src/presentation/palette.gd")
const INK: Color = SharedPalette.COMBAT_INK
const SLATE_0: Color = SharedPalette.SLATE_INK
const SLATE_1: Color = SharedPalette.COMBAT_SLATE_1
const SLATE_2: Color = SharedPalette.SLATE_GROUND
const SLATE_3: Color = Color("71808a")
const BONE: Color = SharedPalette.BONE
const BONE_DIM: Color = Color("b8b19f")
const COPPER: Color = Color("bb713d")
const COPPER_DULL: Color = SharedPalette.COMBAT_COPPER_DULL
const COLD: Color = SharedPalette.COLD_TEAL
const PURPLE: Color = Color("70578d")
const DANGER: Color = Color("a83b3f")
const DANGER_BRIGHT: Color = Color("ed7370")
const CONTACT_SHADOW: Color = Color(0.08, 0.09, 0.11)
