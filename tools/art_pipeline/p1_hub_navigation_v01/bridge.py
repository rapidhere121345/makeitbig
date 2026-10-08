"""Load the reviewed early-loop pipeline modules explicitly, by file path.

The sibling pipeline at ``tools/art_pipeline/p1_early_loop_v01`` resolves its own
imports by bare name: it does ``from contract import ...`` and its verifier does
``import build``. Loading it naively from this package would bind whichever
``build`` or ``contract`` module happened to win the import path -- another
pipeline's, or this package's own ``build`` -- so the reusable routines are
loaded from explicit file paths instead.

The bare names the sibling modules expect are staged only for the duration of
their own import and then restored to exactly what they were, so no other
package (including this one) can observe a substitution. The sibling ID
contract is loaded under a private namespace name of its own, never as a bare
``contract``, because this package has its own frozen contract.

Two reviewed routines come back through :func:`prepare_sprite` and
:func:`verify_rgba_cell`:

* ``prepare_sprite`` -- crop, colour key, alpha normalisation, nearest-neighbour
  downscale into the visible bound, palette mapping and fixed 32x32 cell
  placement.
* ``_verify_rgba_cell`` -- the shipped 2px four-edge padding, 28x28 visible
  bound, binary-alpha, transparent-RGB and cell colour-cap gate.

Nothing here draws, completes, repairs or re-authors a pixel. Both routines are
the already-reviewed implementations, reached without copying them, so this
package cannot silently drift from the accepted early-loop behaviour.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path
from types import ModuleType
from typing import Any, Callable

SOURCE_PACKAGE: Path = Path(__file__).resolve().parents[1] / "p1_early_loop_v01"
NAMESPACE: str = "p1_early_loop_reuse"

# Bare names the sibling modules resolve for themselves, all captured and put
# back so nothing outside this module observes a staged substitution.
STAGED_NAMES: tuple[str, ...] = ("contract", "build", "verify")

_MODULES: dict[str, ModuleType] | None = None


def _load_module(name: str) -> ModuleType:
    full_name = f"{NAMESPACE}.{name}"
    existing = sys.modules.get(full_name)
    if existing is not None:
        return existing
    path = SOURCE_PACKAGE / f"{name}.py"
    spec = importlib.util.spec_from_file_location(full_name, path)
    if spec is None or spec.loader is None:
        raise ModuleNotFoundError(f"reviewed pipeline module is missing: {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[full_name] = module
    try:
        spec.loader.exec_module(module)
    except BaseException:
        if sys.modules.get(full_name) is module:
            del sys.modules[full_name]
        raise
    return module


def _modules() -> dict[str, ModuleType]:
    global _MODULES
    if _MODULES is not None:
        return _MODULES
    if not SOURCE_PACKAGE.is_dir():
        raise ModuleNotFoundError(f"reviewed pipeline package is missing: {SOURCE_PACKAGE}")

    _missing = object()
    saved = {name: sys.modules.get(name, _missing) for name in STAGED_NAMES}
    inserted = str(SOURCE_PACKAGE) not in sys.path
    if inserted:
        sys.path.insert(0, str(SOURCE_PACKAGE))
    try:
        # The sibling contract is deliberately namespaced and never staged: this
        # package has its own contract module and must not shadow it. The sibling
        # build resolves bare "contract" and bare "build" for itself, which is
        # what the staging below is for.
        sibling_contract = _load_module("contract")
        loaded: dict[str, ModuleType] = {"contract": sibling_contract}
        for name in ("build", "verify"):
            sys.modules["contract"] = sibling_contract
            if "build" in loaded:
                sys.modules["build"] = loaded["build"]
            loaded[name] = _load_module(name)
        loaded["contract"] = sys.modules[f"{NAMESPACE}.contract"]
    finally:
        for name, previous in saved.items():
            if previous is _missing:
                sys.modules.pop(name, None)
            else:
                sys.modules[name] = previous
        if inserted:
            try:
                sys.path.remove(str(SOURCE_PACKAGE))
            except ValueError:  # pragma: no cover - reordered by another thread
                pass
    _MODULES = loaded
    return _MODULES


def contract_error_type() -> type[BaseException]:
    """The sibling pipeline's ``ContractError``, so failures share one type."""
    return _modules()["build"].ContractError


def prepare_sprite() -> Callable[[Any, dict[str, Any]], Any]:
    """The reviewed early-loop ``prepare_sprite`` implementation."""
    return _modules()["build"].prepare_sprite


def verify_rgba_cell() -> Callable[[Any, str, list[str]], None]:
    """The reviewed early-loop cell gate, ``_verify_rgba_cell``."""
    return _modules()["verify"]._verify_rgba_cell
