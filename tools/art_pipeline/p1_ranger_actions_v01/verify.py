#!/usr/bin/env python3
"""Mechanically verify packed P1 ranger action atlas artifacts.

This is a read-only technical check. It rejects empty frames, source or cell
bounds violations, non-binary alpha, colors outside the recipe palette,
neighbor-cell leakage, missing or renamed animations, and duplicate frames that
pretend to be animation. It also re-checks every recorded provenance hash, so a
changed source file or a hand-edited atlas cannot pass silently.

Technical verification is not visual approval and says nothing about art
quality.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path
from typing import Any

from PIL import Image, ImageChops

import build


def _difference_count(left: Image.Image, right: Image.Image) -> int:
    """Count pixels where any channel differs."""
    difference = ImageChops.difference(left, right)
    union = difference.getchannel("R")
    for band in ("G", "B", "A"):
        union = ImageChops.lighter(union, difference.getchannel(band))
    return sum(union.histogram()[1:])


def _extra_visible_pixels(actual: Image.Image, expected: Image.Image) -> int:
    """Count pixels that are visible in the artifact but not in the derived cell."""
    return sum(ImageChops.subtract(actual.getchannel("A"), expected.getchannel("A")).histogram()[1:])


def _read(path: Path, label: str, errors: list[str]) -> dict[str, Any] | None:
    try:
        return build.load_json(path)
    except build.ConfigError as exc:
        errors.append(f"cannot read {label}: {exc}")
        return None


def _cell_rect(index: int, columns: int) -> tuple[int, int, int, int]:
    row, column = divmod(index, columns)
    return (column * build.CELL_SIZE[0], row * build.CELL_SIZE[1], build.CELL_SIZE[0], build.CELL_SIZE[1])


def _alpha_violation(image: Image.Image) -> tuple[int, int, int] | None:
    alpha = image.getchannel("A")
    histogram = alpha.histogram()
    if sum(histogram[1:build.ALPHA_THRESHOLD]) + sum(histogram[build.ALPHA_THRESHOLD + 1:255]) == 0:
        return None
    for y in range(image.height):
        for x in range(image.width):
            value = alpha.getpixel((x, y))
            if value not in (0, 255):
                return x, y, value
    return None


def _palette_violation(
    image: Image.Image, palette: set[tuple[int, int, int, int]]
) -> tuple[int, int, tuple[int, int, int]] | None:
    palette_rgb = {(color[0], color[1], color[2]) for color in palette}
    pixels = image.load()
    for y in range(image.height):
        for x in range(image.width):
            pixel = pixels[x, y]
            if pixel[3] == 0:
                continue
            if (pixel[0], pixel[1], pixel[2]) not in palette_rgb:
                return x, y, (pixel[0], pixel[1], pixel[2])
    return None


def verify_output(
    output: Path, config_path: Path | None = None, update_manifest: bool = False
) -> tuple[list[str], list[str], dict[str, Any]]:
    errors: list[str] = []
    infos: list[str] = []
    summary: dict[str, Any] = {}
    output = output.resolve()
    manifest = _read(output / "manifest.json", "manifest.json", errors)
    atlas = _read(output / "atlas.json", "atlas.json", errors)
    if manifest is None or atlas is None:
        return errors, infos, summary

    if manifest.get("pipeline") not in (None, build.PIPELINE):
        errors.append(f"manifest pipeline is {manifest.get('pipeline')!r}, not {build.PIPELINE!r}")
    if config_path is None:
        recorded = manifest.get("config_path")
        if not isinstance(recorded, str):
            errors.append("manifest config_path is missing; pass --config")
            return errors, infos, summary
        config_path = Path(recorded)
    config_path = config_path.resolve()
    config = _read(config_path, f"recipe {config_path}", errors)
    if config is None:
        return errors, infos, summary
    if manifest.get("config_sha256") != build.sha256_file(config_path):
        errors.append("recipe file changed since the build (config_sha256 mismatch)")

    try:
        build.validate_config(config)
    except build.ConfigError as exc:
        errors.append(f"recipe is invalid: {exc}")
        return errors, infos, summary
    palette_tuple = build.parse_palette(config)
    palette = set(palette_tuple)
    try:
        frames = build.validate_frames(config)
        animations = build.validate_animations(config, frames)
    except build.ConfigError as exc:
        errors.append(f"recipe is invalid: {exc}")
        return errors, infos, summary

    try:
        sources = build.load_sources(config)
    except build.ConfigError as exc:
        errors.append(f"sources cannot be loaded: {exc}")
        sources = {}

    external = build.external_sources(config, sources, config_path) if sources else []
    for key in external:
        recorded = manifest.get("external_sources")
        if not isinstance(recorded, list) or key not in recorded:
            errors.append(f"source {key} is outside the recipe directory but is not recorded as external")
        if not config.get("disclosure", {}).get(key):
            errors.append(f"reused external source {key} has no disclosure entry in the recipe")
    recorded_external = manifest.get("external_sources")
    if isinstance(recorded_external, list):
        for key in recorded_external:
            if key not in external:
                errors.append(f"manifest lists source {key} as external but the recipe disagrees")

    recorded_sources = manifest.get("sources")
    if not isinstance(recorded_sources, dict):
        errors.append("manifest sources section is missing")
    else:
        for key, source in sources.items():
            entry = recorded_sources.get(key)
            if not isinstance(entry, dict):
                errors.append(f"manifest is missing source {key}")
                continue
            if entry.get("sha256") != source.sha256:
                errors.append(f"source {key} content changed since the build ({source.path})")
            if entry.get("width") != source.width or entry.get("height") != source.height:
                errors.append(f"source {key} recorded size does not match the file")
            recorded_background = entry.get("background", {})
            if recorded_background.get("mode") != source.mode:
                errors.append(f"source {key} recorded background mode does not match the recipe")
            if source.mode == "color_key":
                if recorded_background.get("tolerance") != source.tolerance:
                    errors.append(f"source {key} recorded color-key tolerance does not match the recipe")
                if "matched_ratio" not in recorded_background:
                    infos.append(f"source {key}: manifest has no color-key matched_ratio (older build)")

    if atlas.get("schema_version") != build.SCHEMA_VERSION:
        errors.append("atlas schema_version must be 1")
    if list(atlas.get("native_view", [])) != list(build.NATIVE_VIEW):
        errors.append(f"atlas native_view must be {list(build.NATIVE_VIEW)}")
    if list(atlas.get("cell_size", [])) != list(build.CELL_SIZE):
        errors.append(f"atlas cell_size must be {list(build.CELL_SIZE)}")

    columns = config["columns"]
    rows = -(-len(frames) // columns)
    # The texture identity belongs to the recipe: a non-default texture_key
    # (for example 'enemies') names both the atlas entry and <key>.png. An
    # unreadable key is already reported by validate_config above.
    try:
        texture_key, texture_filename = build.texture_spec(config)
    except build.ConfigError:
        texture_key, texture_filename = build.TEXTURE_ID, build.TEXTURE_FILENAME
    atlas_textures = atlas.get("textures") if isinstance(atlas.get("textures"), dict) else {}
    texture_meta = atlas_textures.get(texture_key)
    prefix = config["resource_prefix"].rstrip("/")
    expected_texture_path = f"{prefix}/{texture_filename}"
    if not isinstance(texture_meta, dict):
        errors.append(f"atlas textures.{texture_key} is missing")
    else:
        if texture_meta.get("path") != expected_texture_path:
            errors.append(
                f"atlas textures.{texture_key}.path is {texture_meta.get('path')!r}, "
                f"expected {expected_texture_path!r}"
            )
        if texture_meta.get("width") != columns * build.CELL_SIZE[0]:
            errors.append("atlas texture width does not match columns * cell width")
        if texture_meta.get("height") != rows * build.CELL_SIZE[1]:
            errors.append("atlas texture height does not match the packed rows")
    extra_textures = sorted(key for key in atlas_textures if key != texture_key)
    if extra_textures:
        errors.append("atlas declares undeclared textures: " + ", ".join(extra_textures))
    manifest_texture = manifest.get("texture")
    if not isinstance(manifest_texture, dict):
        errors.append("manifest texture section is missing")
    else:
        if manifest_texture.get("id") != texture_key:
            errors.append(
                f"manifest texture id is {manifest_texture.get('id')!r}, but the recipe declares "
                f"{texture_key!r}"
            )
        if manifest_texture.get("path") != expected_texture_path:
            errors.append(
                f"manifest texture path is {manifest_texture.get('path')!r}, "
                f"expected {expected_texture_path!r}"
            )

    artifacts = manifest.get("artifacts")
    if not isinstance(artifacts, list) or not artifacts:
        errors.append("manifest artifacts array is missing")
    else:
        for item in artifacts:
            if not isinstance(item, dict) or not isinstance(item.get("path"), str):
                errors.append("manifest artifact entry has no path")
                continue
            path = Path(item["path"])
            if not path.is_absolute():
                path = output / path
            if not path.is_file():
                errors.append(f"artifact is missing: {path}")
                continue
            if build.sha256_file(path) != item.get("sha256"):
                errors.append(f"artifact hash mismatch: {path}")
            if path.stat().st_size != item.get("bytes"):
                errors.append(f"artifact byte size mismatch: {path}")
        declared = {Path(item["path"]).name for item in artifacts if isinstance(item, dict) and isinstance(item.get("path"), str)}
        managed = declared | {"manifest.json", "atlas.json", texture_filename}
        texture_artifacts = [
            Path(item["path"]).name
            for item in artifacts
            if isinstance(item, dict) and item.get("kind") == "texture" and isinstance(item.get("path"), str)
        ]
        if texture_artifacts != [texture_filename]:
            errors.append(
                f"manifest records texture artifact(s) {sorted(texture_artifacts)}, expected "
                f"exactly {texture_filename!r}"
            )
        for entry in sorted(output.iterdir()):
            if entry.name not in managed:
                infos.append(f"unmanaged entry in the output directory (not produced by this tool): {entry.name}")

    texture_path = output / texture_filename
    if not texture_path.is_file():
        errors.append(f"texture is missing: {texture_path}")
        return errors, infos, summary
    with Image.open(texture_path) as handle:
        texture = handle.convert("RGBA")
    summary["texture_size"] = list(texture.size)
    if texture.size != (columns * build.CELL_SIZE[0], rows * build.CELL_SIZE[1]):
        errors.append(f"texture is {texture.size}, expected {(columns * build.CELL_SIZE[0], rows * build.CELL_SIZE[1])}")
    if texture.mode != "RGBA":
        infos.append(f"texture mode is {texture.mode}; RGBA is expected for a transparent atlas")

    violation = _alpha_violation(texture)
    if violation is not None:
        errors.append(f"non-binary alpha at {violation[0]},{violation[1]} (alpha={violation[2]})")
    palette_violation = _palette_violation(texture, palette)
    if palette_violation is not None:
        red, green, blue = palette_violation[2]
        errors.append(
            f"non-palette color at {palette_violation[0]},{palette_violation[1]}: "
            f"#{red:02x}{green:02x}{blue:02x}"
        )

    sprites = atlas.get("sprites")
    if not isinstance(sprites, dict):
        errors.append("atlas sprites must be an object")
        sprites = {}
    expected_ids = [frame.id for frame in frames]
    if set(sprites) != set(expected_ids):
        missing = sorted(set(expected_ids) - set(sprites))
        extra = sorted(set(sprites) - set(expected_ids))
        if missing:
            errors.append("atlas is missing frames: " + ", ".join(missing))
        if extra:
            errors.append("atlas has undeclared sprites: " + ", ".join(extra))

    recorded_frames = manifest.get("frames")
    if not isinstance(recorded_frames, list):
        errors.append("manifest frames array is missing")
        recorded_frames = []
    recorded_by_id = {
        item.get("id"): item for item in recorded_frames if isinstance(item, dict) and isinstance(item.get("id"), str)
    }

    cell_digests: dict[str, str] = {}
    derived_digests: dict[str, str] = {}
    palette_cache: dict[Any, tuple[int, int, int, int]] = {}
    scales: dict[str, float] = {}
    for index, frame in enumerate(frames):
        entry = sprites.get(frame.id)
        expected_rect = _cell_rect(index, columns)
        if isinstance(entry, dict):
            if entry.get("texture") != texture_key:
                errors.append(f"sprite {frame.id} texture must be {texture_key}")
            if list(entry.get("rect", [])) != list(expected_rect):
                errors.append(
                    f"sprite {frame.id} rect is {entry.get('rect')}, expected {list(expected_rect)}"
                )
            if list(entry.get("anchor", [])) != list(build.ANCHOR):
                errors.append(f"sprite {frame.id} anchor must be {list(build.ANCHOR)}")
        source = sources.get(frame.source)
        recorded = recorded_by_id.get(frame.id)
        if recorded is None:
            errors.append(f"manifest has no frame record for {frame.id}")
        else:
            if recorded.get("rect") != list(expected_rect):
                errors.append(f"manifest frame {frame.id} rect does not match its recipe index")
            if recorded.get("crop") != list(frame.crop):
                errors.append(f"manifest frame {frame.id} crop does not match the recipe")
            if recorded.get("scale") != frame.scale:
                errors.append(f"manifest frame {frame.id} scale does not match the recipe")
            if recorded.get("source") != frame.source:
                errors.append(f"manifest frame {frame.id} source does not match the recipe")
            for key in ("foreground_pixels", "bbox", "border_touches", "animations"):
                if key not in recorded:
                    errors.append(f"manifest frame {frame.id} is missing the {key} field")
        scales.setdefault(frame.source, frame.scale)
        if source is None:
            continue
        try:
            cell, info = build.render_frame(source, frame, palette_tuple, palette_cache)
        except build.ConfigError as exc:
            errors.append(f"frame {frame.id} cannot be reconstructed: {exc}")
            continue
        if info["foreground_pixels"] == 0:
            errors.append(f"frame {frame.id} has zero visible pixels")
        derived_digests[frame.id] = hashlib.sha256(cell.tobytes()).hexdigest()
        artifact_cell = texture.crop(
            (expected_rect[0], expected_rect[1], expected_rect[0] + expected_rect[2], expected_rect[1] + expected_rect[3])
        )
        cell_digests[frame.id] = hashlib.sha256(artifact_cell.tobytes()).hexdigest()
        if cell_digests[frame.id] != derived_digests[frame.id]:
            differing = _difference_count(artifact_cell, cell)
            errors.append(
                f"frame {frame.id} cell content does not match the recipe-derived frame "
                f"({differing} differing pixels); neighbor-cell leakage or modified pixels"
            )
        if recorded is not None:
            if recorded.get("foreground_pixels") != info["foreground_pixels"]:
                errors.append(f"manifest frame {frame.id} foreground_pixels does not match the atlas")
            if recorded.get("bbox") != info["bbox"]:
                errors.append(f"manifest frame {frame.id} bbox does not match the atlas")

    for frame_id in sorted(set(derived_digests) & set(cell_digests)):
        if derived_digests[frame_id] == cell_digests[frame_id]:
            continue
        index = [frame.id for frame in frames].index(frame_id)
        column, row = divmod(index, columns)
        rect = (column * build.CELL_SIZE[0], row * build.CELL_SIZE[1], build.CELL_SIZE[0], build.CELL_SIZE[1])
        artifact_cell = texture.crop((rect[0], rect[1], rect[0] + rect[2], rect[1] + rect[3]))
        try:
            source = sources[frames[index].source]
            expected_cell, _info = build.render_frame(source, frames[index], palette_tuple, palette_cache)
        except build.ConfigError:
            continue
        extras = _extra_visible_pixels(artifact_cell, expected_cell)
        if extras:
            errors.append(
                f"neighbor-cell leakage: frame {frame_id} has {extras} visible pixel(s) that the recipe does not "
                "place in its own cell"
            )

    animations_atlas = atlas.get("animations")
    if not isinstance(animations_atlas, dict):
        errors.append("atlas animations must be an object")
        animations_atlas = {}
    expected_animations = {
        animation.id: {"frames": list(animation.frames), "fps": animation.fps, "loop": animation.loop}
        for animation in animations
    }
    for animation_id, expected in expected_animations.items():
        recorded_animation = animations_atlas.get(animation_id)
        if recorded_animation is None:
            errors.append(f"atlas is missing animation {animation_id}")
            continue
        if recorded_animation != expected:
            errors.append(f"atlas animation {animation_id} does not match the recipe")
    for animation_id in animations_atlas:
        if animation_id not in expected_animations:
            errors.append(f"atlas has an undeclared animation {animation_id}")

    semantics = atlas.get("action_semantics")
    if not isinstance(semantics, dict):
        errors.append("atlas action_semantics must be an object")
    else:
        for animation_id, expected in expected_animations.items():
            entry = semantics.get(animation_id)
            if not isinstance(entry, dict):
                errors.append(f"atlas action_semantics is missing {animation_id}")
                continue
            if list(entry.get("cell_size", [])) != list(build.CELL_SIZE) or list(entry.get("anchor", [])) != list(build.ANCHOR):
                errors.append(f"atlas action_semantics {animation_id} has an unexpected cell or anchor")

    animation_summary: dict[str, Any] = {}
    for animation in animations:
        seen: dict[str, str] = {}
        duplicates: list[list[str]] = []
        for frame_id in animation.frames:
            digest = cell_digests.get(frame_id)
            if digest is None:
                continue
            if digest in seen:
                duplicates.append([seen[digest], frame_id])
            else:
                seen[digest] = frame_id
        animation_summary[animation.id] = {
            "frames": len(animation.frames),
            "distinct_pixel_frames": len(seen),
            "duplicate_pixel_frames": duplicates,
        }
        if duplicates:
            errors.append(
                f"animation {animation.id} repeats identical frames (fake animation): "
                + ", ".join(f"{pair[0]}={pair[1]}" for pair in duplicates)
            )
        recorded_animation = manifest.get("animations", {}).get(animation.id) if isinstance(manifest.get("animations"), dict) else None
        if isinstance(recorded_animation, dict):
            if recorded_animation.get("distinct_pixel_frames") != len(seen):
                errors.append(f"manifest animation {animation.id} distinct_pixel_frames does not match the atlas")
    summary["animation_summary"] = animation_summary
    summary["scale_by_source"] = scales
    recorded_scales = manifest.get("scale_by_source")
    if isinstance(recorded_scales, dict):
        for key, value in scales.items():
            if recorded_scales.get(key) != value:
                errors.append(f"manifest scale_by_source for {key} does not match the recipe")
    orphan = manifest.get("orphan_frames")
    if isinstance(orphan, list) and orphan:
        infos.append("frames not used by any animation: " + ", ".join(str(item) for item in orphan))
    cross_records = manifest.get("duplicate_pixel_frames")
    if isinstance(cross_records, list) and cross_records:
        infos.append(
            "frames with identical pixels across animations: "
            + "; ".join(",".join(group) for group in cross_records)
        )
    for frame in frames:
        recorded = recorded_by_id.get(frame.id)
        if isinstance(recorded, dict) and recorded.get("border_touches"):
            touches = recorded["border_touches"]
            if touches.get("crop"):
                infos.append(f"frame {frame.id} foreground touches its crop edge: {','.join(touches['crop'])}")
            if touches.get("cell"):
                infos.append(f"frame {frame.id} foreground touches the cell edge: {','.join(touches['cell'])}")
        if isinstance(recorded, dict) and recorded.get("background_removed_enclosed_pixels"):
            infos.append(
                f"frame {frame.id} had {recorded['background_removed_enclosed_pixels']} enclosed pixels removed "
                "by the declared color key (check interior art)"
            )

    if update_manifest and not errors:
        manifest_path = output / "manifest.json"
        refreshed = dict(manifest)
        artifacts_now = []
        for item in manifest.get("artifacts", []):
            path = Path(item["path"])
            if not path.is_absolute():
                path = output / path
            refreshed_item = dict(item)
            refreshed_item["sha256"] = build.sha256_file(path)
            refreshed_item["bytes"] = path.stat().st_size
            artifacts_now.append(refreshed_item)
        refreshed["artifacts"] = artifacts_now
        refreshed["technical_verification"] = {
            "status": "verified_mechanical_only",
            "scope": "mechanical output properties only; not visual approval",
            "checked_with": "tools/art_pipeline/p1_ranger_actions_v01/verify.py",
        }
        build.json_write(manifest_path, refreshed)
        infos.append("manifest hashes and technical_verification were refreshed")
    return errors, infos, summary


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path, help="version output directory")
    parser.add_argument("--config", type=Path, default=None, help="recipe JSON path (defaults to the manifest record)")
    parser.add_argument("--update-manifest", action="store_true", help="refresh hashes after a clean check")
    args = parser.parse_args(argv)
    errors, infos, summary = verify_output(args.output, args.config, args.update_manifest)
    for line in infos:
        print(f"info: {line}")
    if summary.get("scale_by_source"):
        print("info: scale_by_source " + json.dumps(summary["scale_by_source"], sort_keys=True))
    for animation_id, value in sorted(summary.get("animation_summary", {}).items()):
        print(
            f"info: {animation_id} frames={value['frames']} distinct={value['distinct_pixel_frames']}"
        )
    if errors:
        print(f"VERIFY FAILED ({len(errors)} error(s)):", file=sys.stderr)
        for line in errors:
            print(f"  - {line}", file=sys.stderr)
        return 1
    print(f"VERIFY OK: {args.output} ({len(infos)} info line(s))")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
