shader_type canvas_item;
render_mode unshaded;

// One source-pixel keyline, confined to the current atlas region. It follows
// the actor's real alpha silhouette and inherits every existing fade/hit tint.
uniform vec4 rim_color : source_color = vec4(0.91, 0.84, 0.63, 1.0);
uniform vec4 outline_color : source_color = vec4(0.025, 0.035, 0.045, 1.0);
uniform float brightness = 1.16;
uniform vec4 source_region = vec4(0.0);
varying vec4 actor_tint;

void vertex() {
	actor_tint = COLOR;
}

float inside_region(vec2 point, vec4 region, vec2 pixel_size) {
	vec2 lower = region.xy + pixel_size * 0.5;
	vec2 upper = region.xy + region.zw - pixel_size * 0.5;
	return float(all(greaterThanEqual(point, lower)) && all(lessThanEqual(point, upper)));
}

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	vec4 bounds = source_region.z > 0.0 ? source_region : REGION_RECT;
	vec2 left_uv = UV - vec2(TEXTURE_PIXEL_SIZE.x, 0.0);
	vec2 right_uv = UV + vec2(TEXTURE_PIXEL_SIZE.x, 0.0);
	vec2 up_uv = UV - vec2(0.0, TEXTURE_PIXEL_SIZE.y);
	vec2 down_uv = UV + vec2(0.0, TEXTURE_PIXEL_SIZE.y);
	float left = texture(TEXTURE, left_uv).a * inside_region(left_uv, bounds, TEXTURE_PIXEL_SIZE);
	float right = texture(TEXTURE, right_uv).a * inside_region(right_uv, bounds, TEXTURE_PIXEL_SIZE);
	float up = texture(TEXTURE, up_uv).a * inside_region(up_uv, bounds, TEXTURE_PIXEL_SIZE);
	float down = texture(TEXTURE, down_uv).a * inside_region(down_uv, bounds, TEXTURE_PIXEL_SIZE);
	float around = max(max(left, right), max(up, down));
	vec3 body = clamp(source.rgb * actor_tint.rgb * brightness, vec3(0.0), vec3(1.0));
	// An upper/left rim gives a second, lighter edge against dark ground.
	float lit_edge = source.a * (1.0 - min(left, up));
	body = mix(body, rim_color.rgb, lit_edge * 0.48);
	float outline = (1.0 - source.a) * step(0.5, around) * 0.94;
	float alpha = source.a + outline;
	vec3 rgb = mix(outline_color.rgb, body, source.a / max(alpha, 0.0001));
	COLOR = vec4(rgb, alpha * actor_tint.a);
}
