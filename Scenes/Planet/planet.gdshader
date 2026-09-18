shader_type spatial;
//render_mode depth_draw_always;

uniform bool is_globe = false;

// The planet's own color under any raster, given in sRGB as the document holds
// it; source_color has the engine linearize it, as it does the raster. Opaque:
// the alpha is not read, since the planet is never see-through.
uniform vec4 planet_color : source_color = vec4(0.16, 0.36, 0.60, 1.0);

// The image a document wears, blended over the planet color by raster_opacity.
// Zero is no raster at all, which is what a document naming no image, hiding the
// one it names or failing to read it comes to, and the fragment then never
// samples the texture.
uniform sampler2D raster_tex : source_color, repeat_disable;
uniform float raster_opacity = 0.0;

uniform vec4 color = vec4(1.0, 1.0, 1.0, 0.3333);
uniform vec2 split = vec2(24.0, 12.0);
// How wide a grid line is, in screen pixels.
const float GRID_PIXELS = 1.5;

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
// Layout: width = primitive count, height = 2
//   Row 0: (lat_a, lon_a, lat_b, lon_b) in radians
//   Row 1: (lat_c, lon_c, feature, kind)
// kind 0 is a triangle (a, b, c), 1 a polyline segment (a, b), 2 a
// multipoint marker (a), 3 a hotspot sample (a), a marker SAMPLE_DOT_SCALE
// the size, and 4 a circle around a whose angular radius is in lat_b, drawn
// like a segment; the unused vertices repeat a. The vertices are in the
// frame of the feature the primitive belongs to, and `feature` is the column of
// feature_data holding the rotation and the color of that feature.
uniform sampler2D geometry_data : filter_nearest, repeat_disable;
uniform int geometry_count = 0;

// The width of a feature line before its feature's line_scale, and the radius of
// a marker.
uniform float geometry_line_width = 0.012;
uniform float geometry_point_radius = 0.02;
// How large a hotspot sample dot is against geometry_point_radius:
// Planet.SAMPLE_DOT_SCALE.
const float SAMPLE_DOT_SCALE = 0.5;

// How much wider the halo under the segments of the selected feature is than
// the segments themselves, and its color, which is also the outline overlay's.
const float SELECTED_LINE_SCALE = 1.25;
const vec3 HIGHLIGHT_COLOR = vec3(1.0);
// How much of a line's width the antialiasing feather takes, from the outside.
const float LINE_FEATHER = 0.2;
// What the segments of a child of the selected feature are drawn in, at the
// normal width: Planet.CHILD_COLOR, an sRGB orange, in linear light.
const vec3 CHILD_COLOR = vec3(1.0, 0.214041, 0.0);

// Per feature state at the current time (filter_nearest for exact texel reads)
// Layout: width = feature count, height = 5
//   Row 0: (m00, m10, m20, hovered)  -- the first column of the rotation
//   Row 1: (m01, m11, m21, visible)  -- the second
//   Row 2: (m02, m12, m22, selected) -- the third
//   Row 3: (r, g, b, a)              -- the color, linear, alpha the opacity
//   Row 4: (related, line_scale, 0, 0)
// Keeping the rotation and the color here rather than beside the vertices is
// what makes a step of an animation or a change of color cheap: only these
// five texels per feature are re-uploaded, whatever the triangle count is.
// `visible` is 0 while the feature is outside its time range, `hovered` is 1
// while the pointer rests on it, `selected` is 1 on the feature whose
// segments get a white halo, and `related` is 1 on a child of the
// selected feature, whose lines and markers are drawn orange. A related
// polygon keeps its fill; the outline overlay traces it instead. `line_scale`
// is what the feature's segments are drawn at against geometry_line_width,
// halo and feather included: Feature.line_scale().
uniform sampler2D feature_data : filter_nearest, repeat_disable;

// Outline overlay data texture (filter_nearest for exact texel reads)
// Layout: width = vertex count, height = 1
//   Row 0: (lat, lon, part_start, style), lat and lon in radians
// part_start is the index this part begins at, so several parts fit in one
// texture. style 0 draws an open line, 1 closes it with a faint last segment
// (the shape being drawn), 2 draws the vertex markers only, 3 closes it with
// every segment alike (a polygon in the Vertex tool), 4 closes it the same way
// with no markers (a selected polygon), 5 draws larger markers only (a
// selected multipoint) and 6 closes it like 4 in CHILD_COLOR (a polygon that
// follows the selected feature). 7 draws an open line BOLD_SCALE times as wide
// as a feature line, geometry_line_width, with no markers (the pole cross). 8 is
// a circle drawn like 3, from two vertices, its center and a point of its rim,
// with no markers (the circle being drawn). 9 is 0 with no markers, for a run
// sampled finely enough that a dot per vertex would be a string of beads (the
// Measure tool's parallels). Every style but 4, 6, 7, 8 and 9 marks each vertex.
uniform sampler2D outline_data : filter_nearest, repeat_disable;
uniform int outline_vertex_count = 0;
uniform float outline_line_width = 0.002;
uniform float outline_dot_radius = 0.006;
uniform float outline_closing_opacity = 0.25;
// The opacity of a closed outline, style 3 and 4, so the fill and the grid
// show through the white edge of a selected polygon.
const float OUTLINE_OPACITY = 0.6;

// How much larger style 5 draws its markers than outline_dot_radius.
const float SELECTED_MARKER_SCALE = 2.0;
// How wide style 7 draws its line against geometry_line_width:
// Planet.BOLD_SCALE.
const float BOLD_SCALE = 0.5;

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

// How much of a fragment at `d` from a line `width` wide the line covers:
// all of it inside, fading over the outer LINE_FEATHER of the width.
float line_coverage(float width, float d) {
	return 1.0 - smoothstep(width * (1.0 - LINE_FEATHER), width, d);
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

// The angle between two unit vectors. atan() of the sine and the cosine stays
// exact near zero, where acos() of the cosine loses the digits of a small circle.
float angle_between(vec3 a, vec3 b) {
	return atan(length(cross(a, b)), dot(a, b));
}

// Distance from p to the circle of the given angular radius around axis, as an
// angle. The counterpart of Planet.circle_distance().
float circle_distance(vec3 axis, float radius, vec3 p) {
	return abs(angle_between(axis, p) - radius);
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

	// The planet color, under whatever image the document wears
	vec3 surface = planet_color.rgb;
	if (raster_opacity > 0.0) {
		surface = mix(surface, texture(raster_tex, surface_uv).rgb, raster_opacity);
	}

	// Longitude and latitude grids, GRID_PIXELS wide on screen and antialiased,
	// the same on the globe and the map. The middle of the sheet is taken off
	// first, so the lines are counted from the equator and the prime meridian
	// and land on every multiple of the spacing. The derivative is taken before
	// fract so the wrap of a line does not give its column a huge one. Meridians
	// fade out where they would be denser than one per two pixels, which is how
	// they converge on the globe's poles without flooding them; parallels never
	// do.
	vec2 uv = (surface_uv - vec2(0.5)) * split;
	vec2 d = fwidth(uv) * GRID_PIXELS;
	vec2 f = abs(fract(uv + vec2(0.5)) - vec2(0.5));
	float line_x = 1.0 - smoothstep(0.0, d.x, f.x);
	line_x *= 1.0 - smoothstep(0.25, 0.5, d.x);
	float line_y = 1.0 - smoothstep(0.0, d.y, f.y);
	float g = max(line_x, line_y);
	vec3 base = surface;

	// Precompute sphere position for the geometry and the outline
	vec3 p = latlon_to_unit(vec2(lat, lon));

	// Feature geometry. Every primitive of one feature follows the last, so the
	// rotation and the color are fetched once per feature rather than once per
	// primitive.
	int loaded_feature = -1;
	mat3 rotation = mat3(1.0);
	float hovered = 0.0;
	bool feature_visible = true;
	bool feature_selected = false;
	bool feature_related = false;
	float line_scale = 1.0;
	vec4 feature_color = vec4(1.0);
	// The selected feature's segments are laid down after the loop, halo first
	// and the line over it, from the distance to the nearest of them. Drawing
	// each segment's halo in turn would paint over the line of the one before
	// where the two meet. The distance is divided by the feature's line_scale,
	// which is the same as drawing at the scaled width. A hotspot's sample dots
	// are held back too, so the halo does not cross them.
	float selected_line_dist = 1e10;
	float selected_dot = 0.0;
	vec4 selected_paint = vec4(1.0);
	float selected_hovered = 0.0;

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
			feature_selected = f2.w > 0.5;
			feature_color = texelFetch(feature_data, ivec2(feature, 3), 0);
			vec4 f4 = texelFetch(feature_data, ivec2(feature, 4), 0);
			feature_related = f4.r > 0.5;
			line_scale = f4.g;
		}
		if (!feature_visible) {
			continue;
		}

		vec3 a = rotation * latlon_to_unit(row0.xy);
		int kind = int(row1.w + 0.5);

		// How much of this fragment the primitive covers, and in what color.
		float coverage = 0.0;
		vec4 paint = feature_color;

		if (kind == 0) {
			vec3 b = rotation * latlon_to_unit(row0.zw);
			vec3 c = rotation * latlon_to_unit(row1.xy);

			// Great-circle half-plane tests (CCW winding)
			if (dot(cross(a, b), p) > 0.0 && dot(cross(b, c), p) > 0.0
					&& dot(cross(c, a), p) > 0.0) {
				coverage = 1.0;
			}
		} else if (kind == 1 || kind == 4) {
			float d = kind == 1 ? arc_distance(a, rotation * latlon_to_unit(row0.zw), p)
				: circle_distance(a, row0.z, p);
			if (feature_selected) {
				selected_line_dist = min(selected_line_dist, d / line_scale);
				selected_paint = feature_color;
				selected_hovered = hovered;
				continue;
			}
			// A related line is drawn opaque orange.
			if (feature_related) {
				paint = vec4(CHILD_COLOR, 1.0);
			}
			coverage = line_coverage(geometry_line_width * line_scale, d);
		} else {
			float d = chord(a, p);
			float radius = geometry_point_radius * (kind == 3 ? SAMPLE_DOT_SCALE : 1.0);
			coverage = 1.0 - smoothstep(radius * 0.7, radius, d);
			if (kind == 3 && feature_selected) {
				selected_dot = max(selected_dot, coverage);
				continue;
			}
			if (feature_related) {
				paint = vec4(CHILD_COLOR, 1.0);
			}
		}

		if (coverage > 0.0) {
			// One flat color, laid over what is beneath by its opacity.
			vec3 fill = mix(base, paint.rgb, paint.a);
			// Hover highlight: brighten slightly while the pointer is on it
			if (hovered > 0.5) {
				fill = mix(fill, vec3(1.0), 0.15);
			}
			base = mix(base, fill, coverage);
		}
	}

	// The selected line: an opaque white halo, so it shows even at an opacity
	// of zero, and the line and its sample dots in its own color on top.
	if (selected_line_dist < 1e9 || selected_dot > 0.0) {
		float halo = line_coverage(geometry_line_width * SELECTED_LINE_SCALE, selected_line_dist);
		base = mix(base, HIGHLIGHT_COLOR, halo);
		vec3 fill = mix(base, selected_paint.rgb, selected_paint.a);
		if (selected_hovered > 0.5) {
			fill = mix(fill, vec3(1.0), 0.15);
		}
		base = mix(base, fill,
			max(line_coverage(geometry_line_width, selected_line_dist), selected_dot));
	}

	// The grid goes over the feature fills, the way GPlates draws its
	// graticule, so a polygon never hides it. The outline stays on top.
	base = mix(base, color.rgb, g * color.a);

	// Outline overlay
	if (outline_vertex_count > 0) {
		float min_dot_dist = 1e10;
		float min_line_dist = 1e10;
		float closing_line_dist = 1e10;
		float closed_line_dist = 1e10;
		float child_line_dist = 1e10;
		float bold_line_dist = 1e10;

		for (int i = 0; i < outline_vertex_count; i++) {
			vec4 v = texelFetch(outline_data, ivec2(i, 0), 0);
			vec3 a = latlon_to_unit(v.xy);
			int style = int(v.w + 0.5);
			// A circle part is its center and a point of its rim, read at the
			// center.
			if (style == 8) {
				if (i + 1 < outline_vertex_count && i == int(v.z + 0.5)) {
					vec3 rim = latlon_to_unit(texelFetch(outline_data, ivec2(i + 1, 0), 0).xy);
					closed_line_dist = min(closed_line_dist,
						circle_distance(a, angle_between(a, rim), p));
				}
				continue;
			}
			// A larger marker is the same test against a shorter distance.
			if (style == 5) {
				min_dot_dist = min(min_dot_dist, chord(a, p) / SELECTED_MARKER_SCALE);
				continue;
			}
			if (style != 4 && style != 6 && style != 7 && style != 9) {
				min_dot_dist = min(min_dot_dist, chord(a, p));
			}
			if (style == 2) {
				continue;
			}

			// The segment leaves this vertex for the next one of the same part,
			// or back to the first one when the part is closed.
			int start = int(v.z + 0.5);
			bool last = i + 1 >= outline_vertex_count
				|| int(texelFetch(outline_data, ivec2(i + 1, 0), 0).z + 0.5) != start;
			if (last && (style == 0 || style == 7 || style == 9 || i == start)) {
				continue;
			}

			int other = last ? start : i + 1;
			vec3 b = latlon_to_unit(texelFetch(outline_data, ivec2(other, 0), 0).xy);
			float d = arc_distance(a, b, p);
			if (last && style == 1) {
				closing_line_dist = min(closing_line_dist, d);
			} else if (style == 6) {
				child_line_dist = min(child_line_dist, d);
			} else if (style == 7) {
				bold_line_dist = min(bold_line_dist, d);
			} else if (style == 3 || style == 4) {
				closed_line_dist = min(closed_line_dist, d);
			} else {
				min_line_dist = min(min_line_dist, d);
			}
		}

		// Composite: dots are larger circles at vertices, lines between them
		float dot_alpha = 1.0 - smoothstep(outline_dot_radius * 0.7, outline_dot_radius, min_dot_dist);
		float line_alpha = line_coverage(outline_line_width, min_line_dist);
		float closed_alpha = line_coverage(outline_line_width, closed_line_dist) * OUTLINE_OPACITY;
		float closing_alpha = line_coverage(outline_line_width, closing_line_dist) * outline_closing_opacity;
		float bold_alpha = line_coverage(geometry_line_width * BOLD_SCALE, bold_line_dist);
		float outline_alpha = max(max(dot_alpha, bold_alpha), max(max(line_alpha, closed_alpha), closing_alpha));
		float child_alpha = line_coverage(outline_line_width, child_line_dist);
		base = mix(base, CHILD_COLOR, child_alpha);
		base = mix(base, HIGHLIGHT_COLOR, outline_alpha);
	}

	ALBEDO = base;
	ALPHA = 1.0;
	// A matte surface: the default specular term would lift every colour
	// towards white under the light, on top of what the albedo says.
	SPECULAR = 0.0;
}
