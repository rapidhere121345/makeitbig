"""Review derivatives for the packaged hub-navigation icons.

Review images exist so a human can judge the published pack without opening the
pack itself. They are mechanically derived from the exact atlas that was just
written -- a nearest-neighbour 2x, a nearest-neighbour quarter scale, a greyscale
copy and a silhouette -- and they are never part of the published pack.

The five derivatives are written only into the separate, explicitly requested
directory passed as ``--review``. The pack directory keeps exactly three files,
so no review asset can be mistaken for production content or shipped to the
runtime. Derivatives are sized from the atlas itself rather than from a second
guess at the intended dimensions, and greyscale and silhouette touch RGB only:
alpha is carried through untouched.
"""

from __future__ import annotations

from collections.abc import Callable
from pathlib import Path
from typing import Any

from PIL import Image, ImageOps

import contract

# Review labels, matching the sibling packages' contact-sheet vocabulary so a
# reviewer sees the same names across the P1 batches.
DERIVATIVE_LABELS: dict[str, str] = {
    "native": contract.REVIEW_NATIVE,
    "2x": contract.REVIEW_2X,
    "25pct": contract.REVIEW_25PCT,
    "gray": contract.REVIEW_GRAY,
    "silhouette": contract.REVIEW_SILHOUETTE,
}
_LABEL_BY_FILE: dict[str, str] = {name: label for label, name in DERIVATIVE_LABELS.items()}


def derivative_label(name: str) -> str:
    """The manifest label for a derivative file name."""
    return _LABEL_BY_FILE[name]


def derivative_dimensions(atlas_size: tuple[int, int]) -> dict[str, list[int]]:
    """The exact size each derivative must have for a given atlas size."""
    width, height = atlas_size
    return {
        contract.REVIEW_NATIVE: [width, height],
        contract.REVIEW_2X: [width * 2, height * 2],
        contract.REVIEW_25PCT: [max(1, width // 4), max(1, height // 4)],
        contract.REVIEW_GRAY: [width, height],
        contract.REVIEW_SILHOUETTE: [width, height],
    }


def load_source(path: Path) -> Image.Image:
    """Read a source sheet once, detached from the file handle."""
    with Image.open(path) as image:
        image.load()
        return image.copy()


def grayscale(image: Image.Image) -> Image.Image:
    """Greyscale copy that keeps the alpha channel exact."""
    alpha = image.getchannel("A")
    gray = ImageOps.grayscale(image.convert("RGB"))
    return Image.merge("RGBA", (gray, gray, gray, alpha))


def silhouette(image: Image.Image) -> Image.Image:
    """Flat white shape behind the exact alpha channel."""
    alpha = image.getchannel("A")
    white = Image.new("L", image.size, 255)
    return Image.merge("RGBA", (white, white, white, alpha))


def derivatives(atlas: Image.Image) -> dict[str, Image.Image]:
    sizes = derivative_dimensions(atlas.size)
    two_x = atlas.resize(tuple(sizes[contract.REVIEW_2X]), Image.Resampling.NEAREST)
    quarter = atlas.resize(tuple(sizes[contract.REVIEW_25PCT]), Image.Resampling.NEAREST)
    return {
        contract.REVIEW_NATIVE: atlas.copy(),
        contract.REVIEW_2X: two_x,
        contract.REVIEW_25PCT: quarter,
        contract.REVIEW_GRAY: grayscale(atlas),
        contract.REVIEW_SILHOUETTE: silhouette(atlas),
    }


def write_review(
    atlas: Image.Image,
    review_directory: Path,
    *,
    write_png: Callable[[Image.Image, Path], None],
    sha256_file: Callable[[Path], str],
) -> dict[str, Any]:
    """Write the five derivatives and return their manifest record."""
    review_directory = review_directory.resolve()
    try:
        review_directory.mkdir(parents=True, exist_ok=False)
    except FileExistsError as exc:
        raise ValueError(f"refusing to overwrite: review directory appeared: {review_directory}") from exc
    images = derivatives(atlas)
    records: dict[str, Any] = {}
    for name in contract.REVIEW_ORDER:
        image = images[name]
        path = review_directory / name
        write_png(image, path)
        records[derivative_label(name)] = {
            "file": name,
            "sha256": sha256_file(path),
            "bytes": path.stat().st_size,
            "dimensions": [image.width, image.height],
        }
    return {"directory": str(review_directory), "derivatives": records}
