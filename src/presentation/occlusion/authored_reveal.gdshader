shader_type canvas_item;

uniform sampler2D revealed_texture : source_color, filter_nearest;
uniform float reveal_weight : hint_range(0.0, 1.0) = 0.0;
varying vec4 item_tint;

void vertex() {
	item_tint = COLOR;
}

void fragment() {
	vec4 full = texture(TEXTURE, UV);
	vec4 revealed = texture(revealed_texture, UV);
	float weight = clamp(reveal_weight, 0.0, 1.0);
	float alpha = mix(full.a, revealed.a, weight);
	vec3 premultiplied = mix(full.rgb * full.a, revealed.rgb * revealed.a, weight);
	vec3 rgb = alpha > 0.00001 ? premultiplied / alpha : vec3(0.0);
	// One sample per state, one tint, one composite. Whole-object pairs have
	// identical RGB/silhouettes and differ only in their authored alpha.
	COLOR = vec4(rgb, alpha) * item_tint;
}
