extends RefCounted
## Canonical source for colour values that more than one presentation module
## uses. Values used under the same meaning are defined once here; values that
## two modules define differently stay separate under SHELL_/COMBAT_ names so
## the disagreement is explicit rather than hidden behind a shared token.
## ShellTheme, CombatPalette and the talent/motion widgets alias these names.

## Cold-slate ramp shared by the shell, combat skin and widgets.
const SLATE_INK := Color("111820")
const SLATE_GROUND := Color("2d3943")
const BONE := Color("e9ddc3")
## Brightened bone used for hovered button copy.
const BONE_HOVER := Color("fff1ce")
## Old-copper idle edge (shell COPPER_DULL, talent board COPPER).
const COPPER_EDGE := Color("ad7950")
## Cold teal reserved for motion and proxy-ally state (combat COLD, motion overlay COLD).
const COLD_TEAL := Color("61a6a5")

## Deliberate disagreements between the shell and the combat skin. Neither value
## is a typo of the other; they were approved in separate passes and the screens
## that use them are pinned by their own tests.
const COMBAT_INK := Color("090c10")
const COMBAT_SLATE_1 := Color("1d2730")
const COMBAT_COPPER_DULL := Color("896043")
const SHELL_DEEP_BLUE := Color("1d2731")
