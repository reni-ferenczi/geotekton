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
uniform float craton_edge_width = 0.001;

// Outline data texture (filter_nearest for exact texel reads)
// Layout: width = vertex count, height = 1
//   Row 0: (lat, lon, unused, unused) in radians
uniform sampler2D outline_data : filter_nearest, repeat_disable;
uniform int outline_vertex_count = 0;
uniform bool outline_closed = false;
uniform float outline_line_width = 0.002;
uniform float outline_dot_radius = 0.006;
uniform float outline_closing_opacity = 0.25;
uniform bool outline_triangles_mode = false;

// Axis marker (rotation/move axis handle)
uniform bool axis_enabled = false;
uniform vec2 axis_latlon = vec2(0.0, 0.0); // radians
uniform float axis_dot_radius = 0.02;
uniform float axis_line_width = 0.003;

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

	// Precompute sphere position for craton and outline rendering
	float lat = (0.5 - UV.y) * PI;
	float lon = (UV.x - 0.5) * TAU;
	vec3 p = latlon_to_unit(vec2(lat, lon));

	// Craton rendering
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
			// Hover highlight: brighten slightly when row1.z is set
			float hovered = row1.z;
			if (hovered > 0.5) {
				fill = mix(fill, vec3(1.0), 0.15);
			}
			base = mix(vec3(1.0), fill, edge);
		}
	}

	// Outline rendering (polygon drawing preview)
	if (outline_vertex_count > 0) {
		// Dot rendering: find distance to nearest vertex
		float min_dot_dist = 1e10;
		for (int i = 0; i < outline_vertex_count; i++) {
			vec4 v = texelFetch(outline_data, ivec2(i, 0), 0);
			vec3 vp = latlon_to_unit(v.xy);
			float d = sqrt(2.0 * max(0.0, 1.0 - dot(vp, p)));
			min_dot_dist = min(min_dot_dist, d);
		}

		// Line segment rendering: great-circle capsule distance
		float min_line_dist = 1e10;
		float closing_line_dist = 1e10;

		if (outline_triangles_mode) {
			// Triangles mode: every 3 vertices form a closed triangle
			int tri_count = outline_vertex_count / 3;
			for (int t = 0; t < tri_count; t++) {
				int base_idx = t * 3;
				// 3 edges per triangle: (0,1), (1,2), (2,0)
				for (int e = 0; e < 3; e++) {
					vec4 va = texelFetch(outline_data, ivec2(base_idx + e, 0), 0);
					vec4 vb = texelFetch(outline_data, ivec2(base_idx + (e + 1) % 3, 0), 0);

					vec3 a = latlon_to_unit(va.xy);
					vec3 b = latlon_to_unit(vb.xy);

					vec3 n = normalize(cross(a, b));
					float d_plane = abs(dot(n, p));
					vec3 perp_a = cross(n, a);
					vec3 perp_b = cross(b, n);

					float dist;
					if (dot(perp_a, p) >= 0.0 && dot(perp_b, p) >= 0.0) {
						dist = d_plane;
					} else {
						float da = sqrt(2.0 * max(0.0, 1.0 - dot(a, p)));
						float db = sqrt(2.0 * max(0.0, 1.0 - dot(b, p)));
						dist = min(da, db);
					}
					min_line_dist = min(min_line_dist, dist);
				}
			}
		} else {
			// Polyline mode: sequential segments
			int solid_seg_count = outline_vertex_count - 1;
			for (int i = 0; i < solid_seg_count; i++) {
				vec4 va = texelFetch(outline_data, ivec2(i, 0), 0);
				vec4 vb = texelFetch(outline_data, ivec2(i + 1, 0), 0);

				vec3 a = latlon_to_unit(va.xy);
				vec3 b = latlon_to_unit(vb.xy);

				vec3 n = normalize(cross(a, b));
				float d_plane = abs(dot(n, p));
				vec3 perp_a = cross(n, a);
				vec3 perp_b = cross(b, n);

				float dist;
				if (dot(perp_a, p) >= 0.0 && dot(perp_b, p) >= 0.0) {
					dist = d_plane;
				} else {
					float da = sqrt(2.0 * max(0.0, 1.0 - dot(a, p)));
					float db = sqrt(2.0 * max(0.0, 1.0 - dot(b, p)));
					dist = min(da, db);
				}
				min_line_dist = min(min_line_dist, dist);
			}

			// Closing segment (last vertex back to first) at reduced opacity
			if (outline_closed) {
				vec4 va = texelFetch(outline_data, ivec2(outline_vertex_count - 1, 0), 0);
				vec4 vb = texelFetch(outline_data, ivec2(0, 0), 0);

				vec3 a = latlon_to_unit(va.xy);
				vec3 b = latlon_to_unit(vb.xy);

				vec3 n = normalize(cross(a, b));
				float d_plane = abs(dot(n, p));
				vec3 perp_a = cross(n, a);
				vec3 perp_b = cross(b, n);

				if (dot(perp_a, p) >= 0.0 && dot(perp_b, p) >= 0.0) {
					closing_line_dist = d_plane;
				} else {
					float da = sqrt(2.0 * max(0.0, 1.0 - dot(a, p)));
					float db = sqrt(2.0 * max(0.0, 1.0 - dot(b, p)));
					closing_line_dist = min(da, db);
				}
			}
		}

		// Composite: dots are larger circles at vertices, lines between them
		float dot_alpha = 1.0 - smoothstep(outline_dot_radius * 0.7, outline_dot_radius, min_dot_dist);
		float line_alpha = 1.0 - smoothstep(outline_line_width * 0.5, outline_line_width, min_line_dist);
		float closing_alpha = (1.0 - smoothstep(outline_line_width * 0.5, outline_line_width, closing_line_dist)) * outline_closing_opacity;
		float outline_alpha = max(dot_alpha, max(line_alpha, closing_alpha));
		base = mix(base, vec3(1.0, 1.0, 0.0), outline_alpha);
	}

	// Axis marker rendering
	if (axis_enabled) {
		vec3 ap = latlon_to_unit(axis_latlon);
		// Distance to axis point and its antipode on the surface
		float d_near = sqrt(2.0 * max(0.0, 1.0 - dot(ap, p)));
		float d_far  = sqrt(2.0 * max(0.0, 1.0 + dot(ap, p)));
		float d_dot = min(d_near, d_far);
		float dot_alpha = 1.0 - smoothstep(axis_dot_radius * 0.7, axis_dot_radius, d_dot);
		// Great circle perpendicular to the axis (the "equator" of the axis)
		float d_plane = abs(dot(ap, p));
		float line_alpha = 1.0 - smoothstep(axis_line_width * 0.5, axis_line_width, d_plane);
		float axis_alpha = max(dot_alpha, line_alpha * 0.6);
		base = mix(base, vec3(1.0, 0.3, 0.3), axis_alpha);
	}

	ALBEDO = base;
	ALPHA = 1.0;
}
