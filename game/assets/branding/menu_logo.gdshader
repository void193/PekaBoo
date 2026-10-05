shader_type canvas_item;
// A fine light edge keeps the black artwork readable over the moving game preview.
uniform vec4 edge_color : source_color = vec4(1.0, 0.985, 0.95, 0.95);
uniform float edge_width = 3.0;
varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec4 ink = texture(TEXTURE, UV);
	vec2 step_uv = TEXTURE_PIXEL_SIZE * edge_width;
	float edge = 0.0;
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			edge = max(edge, texture(TEXTURE, UV + vec2(float(x), float(y)) * step_uv).a);
		}
	}
	float under = edge * edge_color.a * (1.0 - ink.a);
	float alpha = ink.a + under;
	vec3 color = (ink.rgb * ink.a + edge_color.rgb * under) / max(alpha, 0.001);
	COLOR = vec4(color, alpha) * tint;
}
