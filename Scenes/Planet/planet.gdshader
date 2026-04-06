shader_type spatial;
//render_mode depth_draw_always;

uniform bool is_globe = false;
uniform sampler2D earth_tex : source_color;

uniform vec4 color = vec4(1.0, 1.0, 1.0, 0.3333);
uniform vec2 width = vec2(0.015, 0.015);
uniform vec2 split = vec2(24.0, 12.0);

// Craton data texture (filter_nearest for exact texel reads)
// Layout: width = triangle count, height = 3
//   Row 0: (lat_a, lon_a, lat_b, lon_b) in radians
//   Row 1: (lat_c, lon_c, unused, unused)
//   Row 2: (r, g, b, a) color
uniform sampler2D craton_data : filter_nearest, repeat_disable;
uniform int craton_count = 0;
uniform float craton_edge_width = 0.005;

// Convert lat/lon (radians) to unit sphere position
vec3 latlon_to_unit(vec2 ll) {
	float cos_lat = cos(ll.x);
	return vec3(cos_lat * cos(ll.y), sin(ll.x), cos_lat * sin(ll.y));
}

void fragment() {
	// Fetch base Earth color
	vec4 earth = texture(earth_tex, UV);

	// Longitude and latitude grids
	vec2 uv = UV * split;
	vec2 f = abs(fract(uv + vec2(0.5)) - vec2(0.5));
	if (is_globe) {
		// Widen the grid towards the poles to keep the line width constant
		f.x *= cos(PI * abs(UV.y - 0.5));
	}
	bool g = f.x < width.x || f.y < width.y;

	// Mix grid & earth
	vec3 base = mix(earth.rgb, color.rgb, g ? color.a : 0.0);

	// Craton rendering
	if (craton_count > 0) {
		// Convert UV to lat/lon, then to unit sphere position
		float lat = (0.5 - UV.y) * PI;
		float lon = (UV.x - 0.5) * TAU;
		vec3 p = latlon_to_unit(vec2(lat, lon));

		for (int i = 0; i < craton_count; i++) {
			vec4 row0 = texelFetch(craton_data, ivec2(i, 0), 0);
			vec4 row1 = texelFetch(craton_data, ivec2(i, 1), 0);
			vec4 row2 = texelFetch(craton_data, ivec2(i, 2), 0);

			vec3 a = latlon_to_unit(row0.xy);
			vec3 b = latlon_to_unit(row0.zw);
			vec3 c = latlon_to_unit(row1.xy);

			// Great-circle half-plane tests (CCW winding)
			float d_ab = dot(normalize(cross(a, b)), p);
			float d_bc = dot(normalize(cross(b, c)), p);
			float d_ca = dot(normalize(cross(c, a)), p);

			if (d_ab > 0.0 && d_bc > 0.0 && d_ca > 0.0) {
				vec4 tri_color = row2;
				float min_dist = min(abs(d_ab), min(abs(d_bc), abs(d_ca)));
				float edge = smoothstep(craton_edge_width * 0.5, craton_edge_width, min_dist);
				vec3 fill = mix(tri_color.rgb, base, 1.0 - tri_color.a);
				base = mix(vec3(1.0), fill, edge);
			}
		}
	}

	ALBEDO = base;
	ALPHA = 1.0;
}
