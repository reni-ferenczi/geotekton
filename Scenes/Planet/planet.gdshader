shader_type spatial;
//render_mode depth_draw_always;

uniform bool is_globe = false;
uniform sampler2D earth_tex : source_color;

uniform vec4 color = vec4(1.0, 1.0, 1.0, 0.3333);
uniform vec2 width = vec2(0.015, 0.015);
uniform vec2 split = vec2(24.0, 12.0);

void fragment() {
    // Fetch base Earth color
    vec4 earth = texture(earth_tex, UV);

    // Longiture and latitute grids
	vec2 uv = UV * split;
	vec2 f = abs(fract(uv + vec2(0.5)) - vec2(0.5));
	if (is_globe) {
		// Widen the grid towards the poles to keep the line width constant
		f.x *= cos(PI * abs(UV.y - 0.5));
	}
	bool g = f.x < width.x || f.y < width.y;

    // mix grid & earth
    ALBEDO = mix(earth.rgb, color.rgb, g ? color.a : 0.0);
    ALPHA = 1.0;
}
