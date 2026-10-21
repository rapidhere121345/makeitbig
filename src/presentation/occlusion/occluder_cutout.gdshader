shader_type canvas_item;

// Per-piece cutout window for native occluders. Each hole punches a soft
// elliptical disc (in viewport pixel space) through the piece so a covered
// actor reads through it. When hole_count is 0 the piece renders opaque.
// Presentation-only: never consulted by movement, vision, or combat.

const int MAX_HOLES = 8;

uniform vec4 holes[MAX_HOLES]; // xy = viewport-space center, z = radius
uniform int hole_count = 0;
uniform float feather = 9.0;
uniform float inner_alpha = 0.18;

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	float keep = 1.0;
	for (int i = 0; i < MAX_HOLES; i++) {
		if (i >= hole_count) {
			break;
		}
		float d = distance(FRAGCOORD.xy, holes[i].xy);
		float f = smoothstep(holes[i].z - feather, holes[i].z + feather, d);
		keep = min(keep, mix(inner_alpha, 1.0, f));
	}
	COLOR = vec4(c.rgb, c.a * keep);
}
