shader_type canvas_item;

// Town-only actual-silhouette foreground reveal. A native front piece is
// cleared exactly over the covered actor's CURRENT opaque silhouette texels:
// the presenter uploads each covered actor's live frame texture, atlas region,
// flip flags and viewport-space draw cell on every presentation frame. Pixels
// outside those texels, and transparent gaps inside the actor cell, keep the
// piece's authored color and alpha, so the legacy transparent ground under a
// foreground piece is never exposed. With actor_count 0 or reveal_weight 0 the
// piece renders unchanged. Presentation-only: never consulted by movement,
// vision, or combat.

const int MAX_ACTORS = 8;

uniform sampler2D actor_textures[MAX_ACTORS] : filter_nearest;
uniform vec4 actor_cells[MAX_ACTORS];   // xy = viewport-space cell top-left, zw = cell size in pixels
uniform vec4 actor_regions[MAX_ACTORS]; // xy = atlas region top-left in texels, zw = region size in texels
uniform vec4 actor_flags[MAX_ACTORS];   // x = flip_h, y = flip_v, zw = atlas size in texels
uniform int actor_count = 0;
uniform float reveal_weight : hint_range(0.0, 1.0) = 0.0;
uniform float clear_alpha : hint_range(0.0, 1.0) = 0.0;

// GL Compatibility (GLSL 1.30 class drivers, e.g. Mesa llvmpipe) forbids
// indexing a sampler array with anything but a constant expression: the
// direct actor_textures[i] sample compiled on Vulkan-class backends but the
// GLES3 driver rejected the whole fragment program ("sampler arrays indexed
// with non-constant expressions"), leaving every bound piece unrendered.
// The dynamic slot index therefore goes through this literal-index ladder;
// the vec4 arrays keep their loop indexing, which GLSL allows.
bool actor_texel_opaque(int i, vec2 uv) {
	if (i == 0) { return texture(actor_textures[0], uv).a >= 0.5; }
	if (i == 1) { return texture(actor_textures[1], uv).a >= 0.5; }
	if (i == 2) { return texture(actor_textures[2], uv).a >= 0.5; }
	if (i == 3) { return texture(actor_textures[3], uv).a >= 0.5; }
	if (i == 4) { return texture(actor_textures[4], uv).a >= 0.5; }
	if (i == 5) { return texture(actor_textures[5], uv).a >= 0.5; }
	if (i == 6) { return texture(actor_textures[6], uv).a >= 0.5; }
	if (i == 7) { return texture(actor_textures[7], uv).a >= 0.5; }
	return false;
}

void fragment() {
	vec4 c = COLOR;
	float keep = 1.0;
	float weight = clamp(reveal_weight, 0.0, 1.0);
	if (actor_count > 0 && weight > 0.0 && c.a > 0.0) {
		float inner = mix(1.0, clamp(clear_alpha, 0.0, 1.0), weight);
		for (int i = 0; i < MAX_ACTORS; i++) {
			if (i >= actor_count) {
				break;
			}
			vec2 local = FRAGCOORD.xy - actor_cells[i].xy;
			if (local.x < 0.0 || local.y < 0.0 || local.x >= actor_cells[i].z || local.y >= actor_cells[i].w) {
				continue;
			}
			// Texel indexing floors the pixel center to an integer pixel index
			// FIRST and mirrors that index; mirroring the float center instead
			// shifts flipped sampling one texel left (span-1-(i+0.5) floors to
			// span-2-i). The CPU coverage refinement uses the same convention.
			vec2 index = floor(local);
			if (actor_flags[i].x > 0.5) {
				index.x = actor_cells[i].z - 1.0 - index.x;
			}
			if (actor_flags[i].y > 0.5) {
				index.y = actor_cells[i].w - 1.0 - index.y;
			}
			vec2 texel = actor_regions[i].xy + index;
			vec2 uv = (texel + vec2(0.5)) / max(actor_flags[i].zw, vec2(1.0));
			if (actor_texel_opaque(i, uv)) {
				keep = min(keep, inner);
			}
		}
	}
	COLOR = vec4(c.rgb, c.a * keep);
}
