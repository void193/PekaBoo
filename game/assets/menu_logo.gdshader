shader_type canvas_item;
// A cream edge keeps the black artwork and wordmark readable over the moving house preview.
// (Adapted from the assets repo's branding/menu_logo.gdshader, with a ring of 16 taps for a rounder edge.)
uniform vec4 edge_color : source_color = vec4(1.0, 0.985, 0.95, 1.0);
uniform float edge_width = 12.0;

void fragment() {
	vec4 ink = texture(TEXTURE, UV);
	float edge = 0.0;
	for (int i = 0; i < 16; i++) {
		float a = float(i) * 0.3927;
		vec2 o = vec2(cos(a), sin(a)) * TEXTURE_PIXEL_SIZE * edge_width;
		edge = max(edge, texture(TEXTURE, UV + o).a);
		edge = max(edge, texture(TEXTURE, UV + o * 0.5).a);
	}
	float under = edge * edge_color.a * (1.0 - ink.a);
	float alpha = ink.a + under;
	vec3 color = (ink.rgb * ink.a + edge_color.rgb * under) / max(alpha, 0.001);
	COLOR = vec4(color, alpha) * COLOR;
}
