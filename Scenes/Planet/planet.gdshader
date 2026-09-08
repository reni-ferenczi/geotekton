shader_type spatial;
//render_mode depth_draw_always;

uniform bool is_globe = false;
uniform sampler2D earth_tex : source_color;

uniform vec4 color = vec4(1.0, 1.0, 1.0, 0.3333);
uniform vec2 width = vec2(0.015, 0.015);
uniform vec2 split = vec2(24.0, 12.0);

// Which map projection the flat view draws in, matching MapProjection.Kind, and
// how tall the sheet it draws on is, matching MapProjection.extent(). The globe
// ignores both. map_centre is (latitude, longitude) in radians: the longitude is
// the central meridian of every projection and the latitude is the centre of the
// hemisphere an orthographic one shows.
uniform int projection = 0;
uniform float map_extent = 0.5;
uniform vec2 map_centre = vec2(0.0, 0.0);

const int PROJECTION_RECTANGULAR = 0;
const int PROJECTION_MERCATOR = 1;
const int PROJECTION_MOLLWEIDE = 2;
const int PROJECTION_ROBINSON = 3;
const int PROJECTION_ORTHOGRAPHIC = 4;

// The Robinson tables and scale factors, and the slack the edges of a sheet are
// tested with. All of them are MapProjection's, and have to stay its.
const float ROBINSON_STEP = 5.0;
const float ROBINSON_EXTENT = 0.50718800410786;
const float MAP_EDGE_SLACK = 1e-6;

// Feature geometry data texture (filter_nearest for exact texel reads)
// Layout: width = primitive count, height = 3
//   Row 0: (lat_a, lon_a, lat_b, lon_b) in radians
//   Row 1: (lat_c, lon_c, feature, kind)
//   Row 2: (r, g, b, a) color
// kind 0 is a triangle (a, b, c), 1 a polyline segment (a, b) and 2 a
// multipoint marker (a); the unused vertices repeat a. The vertices are in the
// frame of the feature the primitive belongs to, and `feature` is the column of
// feature_data holding the rotation that carries them into world space.
uniform sampler2D geometry_data : filter_nearest, repeat_disable;
uniform int geometry_count = 0;

uniform float geometry_edge_width = 0.001;
uniform float geometry_line_width = 0.012;
uniform float geometry_point_radius = 0.02;

// Per feature state at the current time (filter_nearest for exact texel reads)
// Layout: width = feature count, height = 3
//   Row 0: (m00, m10, m20, hovered)  -- the first column of the rotation
//   Row 1: (m01, m11, m21, visible)  -- the second
//   Row 2: (m02, m12, m22, unused)   -- the third
// Keeping the rotation here rather than in the vertices is what makes a step of
// an animation cheap: only these three texels per feature are re-uploaded,
// whatever the triangle count is. `visible` is 0 while the feature is outside
// its time range, and `hovered` is 1 while the pointer rests on it.
uniform sampler2D feature_data : filter_nearest, repeat_disable;

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

// One of the two Robinson tables at a latitude in degrees, interpolated between
// the five degree entries it is given at. The counterpart of
// MapProjection._robinson_at(); `lengths` picks the table.
float robinson_at(bool lengths, float lat_deg) {
	float table[19] = lengths
		? float[19](1.0000, 0.9986, 0.9954, 0.9900, 0.9822, 0.9730, 0.9600,
			0.9427, 0.9216, 0.8962, 0.8679, 0.8350, 0.7986, 0.7597, 0.7186,
			0.6732, 0.6213, 0.5722, 0.5322)
		: float[19](0.0000, 0.0620, 0.1240, 0.1860, 0.2480, 0.3100, 0.3720,
			0.4340, 0.4958, 0.5571, 0.6176, 0.6769, 0.7346, 0.7903, 0.8435,
			0.8936, 0.9394, 0.9761, 1.0000);
	float position = clamp(lat_deg, 0.0, 90.0) / ROBINSON_STEP;
	int low = int(position);
	if (low >= 18) {
		return table[18];
	}
	return mix(table[low], table[low + 1], position - float(low));
}

// The latitude in degrees whose Robinson distance from the equator is the given
// one, which is the same table read the other way round. The counterpart of
// MapProjection._robinson_latitude().
float robinson_latitude(float distance) {
	for (int i = 0; i < 18; i++) {
		float low = robinson_at(false, float(i) * ROBINSON_STEP);
		float high = robinson_at(false, float(i + 1) * ROBINSON_STEP);
		if (distance <= high) {
			return (float(i) + (distance - low) / max(high - low, 1e-9)) * ROBINSON_STEP;
		}
	}
	return 90.0;
}

// Which point of the planet a point of the map sheet shows, as
// (latitude, longitude, on the map), all in radians but the last, which is 1
// where the projection draws something and 0 where it does not: outside the
// Mollweide ellipse or the Robinson outline, or off the orthographic disc.
//
// The counterpart of MapProjection.inverse(), and the reason it exists twice:
// every fragment of the map needs it here, and every click needs it there.
vec3 map_inverse(vec2 plane) {
	float lat = 0.0;
	float lon = 0.0;

	if (projection == PROJECTION_RECTANGULAR) {
		lat = plane.y * PI;
		lon = plane.x * PI;
	} else if (projection == PROJECTION_MERCATOR) {
		lat = 2.0 * atan(exp(plane.y * PI)) - PI * 0.5;
		lon = plane.x * PI;
	} else if (projection == PROJECTION_MOLLWEIDE) {
		float sin_theta = plane.y * 2.0;
		if (abs(sin_theta) > 1.0 + MAP_EDGE_SLACK) {
			return vec3(0.0);
		}
		float theta = asin(clamp(sin_theta, -1.0, 1.0));
		float cos_theta = cos(theta);
		lat = asin(clamp((2.0 * theta + sin(2.0 * theta)) / PI, -1.0, 1.0));
		// The two poles are single points of the ellipse: every meridian
		// reaches them, so the central one answers for all of them.
		if (cos_theta >= 1e-6) {
			lon = plane.x * PI / cos_theta;
			if (abs(lon) > PI + MAP_EDGE_SLACK) {
				return vec3(0.0);
			}
		}
	} else if (projection == PROJECTION_ROBINSON) {
		float distance = plane.y / ROBINSON_EXTENT;
		if (abs(distance) > 1.0 + MAP_EDGE_SLACK) {
			return vec3(0.0);
		}
		float lat_deg = sign(plane.y) * robinson_latitude(min(abs(distance), 1.0));
		lon = plane.x * PI / robinson_at(true, abs(lat_deg));
		if (abs(lon) > PI + MAP_EDGE_SLACK) {
			return vec3(0.0);
		}
		lat = radians(lat_deg);
	} else {
		float radius = length(plane);
		if (radius > 1.0 + MAP_EDGE_SLACK) {
			return vec3(0.0);
		}
		float cos_centre = cos(map_centre.x);
		float sin_centre = sin(map_centre.x);
		if (radius < 1e-6) {
			lat = map_centre.x;
		} else {
			float angle = asin(min(radius, 1.0));
			float sin_c = sin(angle);
			float cos_c = cos(angle);
			lat = asin(clamp(
				cos_c * sin_centre + plane.y * sin_c * cos_centre / radius, -1.0, 1.0));
			lon = atan(
				plane.x * sin_c,
				radius * cos_c * cos_centre - plane.y * sin_c * sin_centre);
		}
	}

	lon = mod(lon + map_centre.y + PI, TAU) - PI;
	return vec3(lat, lon, 1.0);
}

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
	// Where on the planet this fragment is. The globe carries the
	// equirectangular grid on its surface, so its UV is the position; the map
	// has to be projected back, and a fragment its projection does not cover is
	// not part of the planet at all.
	float lat = (0.5 - UV.y) * PI;
	float lon = (UV.x - 0.5) * TAU;
	vec2 surface_uv = UV;
	if (!is_globe) {
		vec3 point = map_inverse(vec2((UV.x - 0.5) * 2.0, (0.5 - UV.y) * 2.0 * map_extent));
		if (point.z < 0.5) {
			discard;
		}
		lat = point.x;
		lon = point.y;
		surface_uv = vec2(lon / TAU + 0.5, 0.5 - lat / PI);
	}

	// Fetch base Earth color
	vec4 earth = texture(earth_tex, surface_uv);

	// Longitude and latitude grids
	vec2 uv = surface_uv * split;
	vec2 f = abs(fract(uv + vec2(0.5)) - vec2(0.5));
	if (is_globe) {
		// Widen the grid towards the poles to keep the line width constant
		f.x *= cos(PI * abs(UV.y - 0.5));
	}
	bool g = f.x < width.x || f.y < width.y;

	// Mix grid & earth
	vec3 base = mix(earth.rgb, color.rgb, g ? color.a : 0.0);

	// Precompute sphere position for the geometry and the outline
	vec3 p = latlon_to_unit(vec2(lat, lon));

	// Feature geometry. Every primitive of one feature follows the last, so the
	// rotation is fetched once per feature rather than once per primitive.
	int loaded_feature = -1;
	mat3 rotation = mat3(1.0);
	float hovered = 0.0;
	bool feature_visible = true;

	for (int i = 0; i < geometry_count; i++) {
		vec4 row0 = texelFetch(geometry_data, ivec2(i, 0), 0);
		vec4 row1 = texelFetch(geometry_data, ivec2(i, 1), 0);

		int feature = int(row1.z + 0.5);
		if (feature != loaded_feature) {
			loaded_feature = feature;
			vec4 f0 = texelFetch(feature_data, ivec2(feature, 0), 0);
			vec4 f1 = texelFetch(feature_data, ivec2(feature, 1), 0);
			vec4 f2 = texelFetch(feature_data, ivec2(feature, 2), 0);
			rotation = mat3(f0.xyz, f1.xyz, f2.xyz);
			hovered = f0.w;
			feature_visible = f1.w > 0.5;
		}
		if (!feature_visible) {
			continue;
		}

		vec4 row2 = texelFetch(geometry_data, ivec2(i, 2), 0);
		vec3 a = rotation * latlon_to_unit(row0.xy);
		int kind = int(row1.w + 0.5);

		// How much of this fragment the primitive covers, and how close it is
		// to the rim of a filled triangle.
		float coverage = 0.0;
		float edge = 1.0;

		if (kind == 0) {
			vec3 b = rotation * latlon_to_unit(row0.zw);
			vec3 c = rotation * latlon_to_unit(row1.xy);

			// Great-circle half-plane tests (CCW winding)
			float d_ab = dot(normalize(cross(a, b)), p);
			float d_bc = dot(normalize(cross(b, c)), p);
			float d_ca = dot(normalize(cross(c, a)), p);

			if (d_ab > 0.0 && d_bc > 0.0 && d_ca > 0.0) {
				coverage = 1.0;

				// The pale rim follows the boundary of the shape, not the
				// edges ear clipping cut it along. Row 3 says which of this
				// triangle's edges came from the ring; a triangle in the
				// middle of a large polygon has none and gets no rim at all.
				vec4 row3 = texelFetch(geometry_data, ivec2(i, 3), 0);
				float min_dist = 1e9;
				if (row3.x > 0.5) { min_dist = min(min_dist, abs(d_ab)); }
				if (row3.y > 0.5) { min_dist = min(min_dist, abs(d_bc)); }
				if (row3.z > 0.5) { min_dist = min(min_dist, abs(d_ca)); }
				edge = smoothstep(geometry_edge_width * 0.5, geometry_edge_width, min_dist);
			}
		} else if (kind == 1) {
			float d = arc_distance(a, rotation * latlon_to_unit(row0.zw), p);
			coverage = 1.0 - smoothstep(geometry_line_width * 0.5, geometry_line_width, d);
		} else {
			float d = chord(a, p);
			coverage = 1.0 - smoothstep(geometry_point_radius * 0.7, geometry_point_radius, d);
		}

		if (coverage > 0.0) {
			vec3 fill = mix(row2.rgb, base, 1.0 - row2.a);
			// Hover highlight: brighten slightly while the pointer is on it
			if (hovered > 0.5) {
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
