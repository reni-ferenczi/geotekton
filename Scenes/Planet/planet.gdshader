shader_type spatial;
//render_mode depth_draw_always;

uniform bool is_globe = false;
uniform sampler2D earth_tex : source_color;

uniform vec4 color = vec4(1.0, 1.0, 1.0, 0.3333);
uniform vec2 width = vec2(0.015, 0.015);
uniform vec2 split = vec2(24.0, 12.0);

// Feature geometry data texture (filter_nearest for exact texel reads)
// Layout: width = primitive count, height = 3
//   Row 0: (lat_a, lon_a, lat_b, lon_b) in radians
//   Row 1: (lat_c, lon_c, hovered, kind)
//   Row 2: (r, g, b, a) color
// kind 0 is a triangle (a, b, c), 1 a polyline segment (a, b) and 2 a
// multipoint marker (a); the unused vertices repeat a.
uniform sampler2D geometry_data : filter_nearest, repeat_disable;
uniform int geometry_count = 0;
uniform float geometry_edge_width = 0.001;
uniform float geometry_line_width = 0.012;
uniform float geometry_point_radius = 0.02;

// Outline overlay data texture (filter_nearest for exact texel reads)
// Layout: width = vertex count, height = 1
//   Row 0: (lat, lon, part_start, style), lat and lon in radians
// part_start is the index this part begins at, so several parts fit in one
// texture. style 0 draws an open line, 1 closes it with a faint last segment
// (the shape being drawn), 2 draws the vertex markers only and 3 closes it
// with every segment alike (the outline of the selected feature).
uniform sampler2D outline_data : filter_nearest, repeat_disable;
uniform int outline_vertex_count = 0;
uniform float outline_line_width = 0.002;
uniform float outline_dot_radius = 0.006;
uniform float outline_closing_opacity = 0.25;

// Convert lat/lon (radians) to unit sphere position
vec3 latlon_to_unit(vec2 ll) {
	float cos_lat = cos(ll.x);
	return vec3(cos_lat * cos(ll.y), sin(ll.x), cos_lat * sin(ll.y));
}

// Chord length between two points on the unit sphere.
float chord(vec3 a, vec3 b) {
	return sqrt(2.0 * max(0.0, 1.0 - dot(a, b)));
}

// Distance from p to the great-circle arc from a to b, as a chord length:
// the distance to the plane of the arc within it, to the nearer end outside.
// The counterpart of Planet.arc_distance().
float arc_distance(vec3 a, vec3 b, vec3 p) {
	vec3 cr = cross(a, b);
	if (dot(cr, cr) < 1e-12) {
		return chord(a, p);
	}
	vec3 n = normalize(cr);
	if (dot(cross(n, a), p) >= 0.0 && dot(cross(b, n), p) >= 0.0) {
		return abs(dot(n, p));
	}
	return min(chord(a, p), chord(b, p));
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

	// Precompute sphere position for the geometry and the outline
	float lat = (0.5 - UV.y) * PI;
	float lon = (UV.x - 0.5) * TAU;
	vec3 p = latlon_to_unit(vec2(lat, lon));

	// Feature geometry
	for (int i = 0; i < geometry_count; i++) {
		vec4 row0 = texelFetch(geometry_data, ivec2(i, 0), 0);
		vec4 row1 = texelFetch(geometry_data, ivec2(i, 1), 0);
		vec4 row2 = texelFetch(geometry_data, ivec2(i, 2), 0);

		vec3 a = latlon_to_unit(row0.xy);
		int kind = int(row1.w + 0.5);

		// How much of this fragment the primitive covers, and how close it is
		// to the rim of a filled triangle.
		float coverage = 0.0;
		float edge = 1.0;

		if (kind == 0) {
			vec3 b = latlon_to_unit(row0.zw);
			vec3 c = latlon_to_unit(row1.xy);

			// Great-circle half-plane tests (CCW winding)
			float d_ab = dot(normalize(cross(a, b)), p);
			float d_bc = dot(normalize(cross(b, c)), p);
			float d_ca = dot(normalize(cross(c, a)), p);

			if (d_ab > 0.0 && d_bc > 0.0 && d_ca > 0.0) {
				coverage = 1.0;
				float min_dist = min(abs(d_ab), min(abs(d_bc), abs(d_ca)));
				edge = smoothstep(geometry_edge_width * 0.5, geometry_edge_width, min_dist);
			}
		} else if (kind == 1) {
			float d = arc_distance(a, latlon_to_unit(row0.zw), p);
			coverage = 1.0 - smoothstep(geometry_line_width * 0.5, geometry_line_width, d);
		} else {
			float d = chord(a, p);
			coverage = 1.0 - smoothstep(geometry_point_radius * 0.7, geometry_point_radius, d);
		}

		if (coverage > 0.0) {
			vec3 fill = mix(row2.rgb, base, 1.0 - row2.a);
			// Hover highlight: brighten slightly when row1.z is set
			if (row1.z > 0.5) {
				fill = mix(fill, vec3(1.0), 0.15);
			}
			base = mix(base, mix(vec3(1.0), fill, edge), coverage);
		}
	}

	// Outline overlay
	if (outline_vertex_count > 0) {
		float min_dot_dist = 1e10;
		float min_line_dist = 1e10;
		float closing_line_dist = 1e10;

		for (int i = 0; i < outline_vertex_count; i++) {
			vec4 v = texelFetch(outline_data, ivec2(i, 0), 0);
			vec3 a = latlon_to_unit(v.xy);
			min_dot_dist = min(min_dot_dist, chord(a, p));

			int style = int(v.w + 0.5);
			if (style == 2) {
				continue;
			}

			// The segment leaves this vertex for the next one of the same part,
			// or back to the first one when the part is closed.
			int start = int(v.z + 0.5);
			bool last = i + 1 >= outline_vertex_count
				|| int(texelFetch(outline_data, ivec2(i + 1, 0), 0).z + 0.5) != start;
			if (last && (style == 0 || i == start)) {
				continue;
			}

			int other = last ? start : i + 1;
			vec3 b = latlon_to_unit(texelFetch(outline_data, ivec2(other, 0), 0).xy);
			float d = arc_distance(a, b, p);
			if (last && style == 1) {
				closing_line_dist = min(closing_line_dist, d);
			} else {
				min_line_dist = min(min_line_dist, d);
			}
		}

		// Composite: dots are larger circles at vertices, lines between them
		float dot_alpha = 1.0 - smoothstep(outline_dot_radius * 0.7, outline_dot_radius, min_dot_dist);
		float line_alpha = 1.0 - smoothstep(outline_line_width * 0.5, outline_line_width, min_line_dist);
		float closing_alpha = (1.0 - smoothstep(outline_line_width * 0.5, outline_line_width, closing_line_dist)) * outline_closing_opacity;
		float outline_alpha = max(dot_alpha, max(line_alpha, closing_alpha));
		base = mix(base, vec3(1.0, 1.0, 0.0), outline_alpha);
	}

	ALBEDO = base;
	ALPHA = 1.0;
}
