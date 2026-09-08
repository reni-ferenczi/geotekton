# Planet Shader

The planet shader (`Scenes/Planet/planet.gdshader`) renders the Earth texture
with a longitude/latitude grid overlay, the geometry of the features on the
surface of a sphere, and a yellow outline layer over that.

## Base Rendering

- **Earth texture**: sampled from an equirectangular projection via UV
- **Grid overlay**: longitude/latitude lines with configurable `split` (divisions), `width`, and `color`; pole-aware width correction in globe mode. The document holds one spacing in degrees and `ViewSettings.graticule_split()` turns it into the divisions the shader counts

The globe carries the equirectangular grid on its own surface, so its UV *is*
the latitude and longitude of a fragment. A map does not: the shader turns UV
into a point of the projection's sheet and asks the projection which place of
the planet is drawn there. Everything after that — the Earth texture, the
graticule, the features, the outline — is the same code in both views, because
all of it works in latitude and longitude.

## Lighting and ambient

The planet is a lit surface: the shader writes `ALBEDO` and the engine shades it
with the `DirectionalLight3D` in `planet.tscn`, so nothing about the light lives
in the shader itself. What a document says about it is a direction and an
ambient level, and `Planet.apply_view_settings()` and
`PlanetView.apply_view_settings()` put the two where the engine reads them:

- **Direction** turns the light. It is stored as an elevation above the line of
  sight and an azimuth around it, both in degrees, and `(0, 0)` shines straight
  from the camera, which is where the scene has always put it.
  `ViewSettings.light_vector()` turns that into a direction in the scene and
  `light_from_vector()` takes it back, which is how the Light tool stores a
  drag on the globe.
- **Ambient** is the environment's `ambient_light_energy`, with the source set
  to a plain colour. Zero is the black night side the scene has always had; one
  is a planet with no night at all.

The direction is fixed to the view rather than to the planet, so turning the
globe carries the terminator across it and a document looks the same whichever
way it is turned. That is what GPlates does by default too.

## The backdrop image

A document may wear an image in place of the built in Earth.
`Logic/backdrop.gd` reads it from the file the document names — PNG, JPEG and
WebP through the engine's own decoders, SVG rasterized to a fixed width — and
hands the texture to `Planet.set_backdrop()`. The shader blends it over the
Earth before anything else is drawn, so the graticule, the features and the
outline all sit on top of it:

```glsl
vec4 earth = texture(earth_tex, surface_uv);
if (backdrop_opacity > 0.0) {
	earth = mix(earth, texture(backdrop_tex, surface_uv), backdrop_opacity);
}
```

The image is sampled by the same `surface_uv` as the Earth, so it is an
equirectangular map of the whole planet, and it follows every projection for
free.

`backdrop_opacity` is zero — and the texture never sampled — when the document
names no image, hides the one it names, or names one that cannot be read. A
document naming an image that has since been moved still opens: the planet keeps
the built in Earth and `Application.backdrop.error` says why, which the View
settings dialog shows beside the path and a test reads over the automation port.

| Uniform | Type | Default | Description |
|---|---|---|---|
| `backdrop_tex` | `sampler2D` | — | The image the planet wears |
| `backdrop_opacity` | `float` | `0.0` | How much of it covers the Earth; 0 is none |

## Map Projections

`Logic/map_projection.gd` holds the five projections in GDScript and
`planet.gdshader` holds the inverse of each one again in GLSL. Both are needed:
every fragment of the map goes through the shader's copy and every click goes
through `MapProjection.inverse()`, and a click and a pixel are supposed to be
about the same place. `Tests/Rendered/test_projection.gd` probes the pixel at
the position `MapProjection.forward()` gives a feature, which fails if the two
ever part company.

### The sheet

Every projection draws on the same sheet: `x` from -1 to 1 across the whole
width and `y` from `-extent` to `extent`, where the extent is what the
projection's own aspect ratio asks for. `Planet._apply_projection()` scales the
map mesh by it, so the mesh is exactly as tall as the projection needs and its
UV covers the sheet and nothing else:

```glsl
vec2 plane = vec2((UV.x - 0.5) * 2.0, (0.5 - UV.y) * 2.0 * map_extent);
```

| Kind | Value | Extent | Aspect | Notes |
|---|---|---|---|---|
| Rectangular | 0 | 0.5 | 2:1 | `x = λ/π`, `y = φ/π` |
| Mercator | 1 | 1.0 | 1:1 | `y = ln(tan(π/4 + φ/2))/π`, which reaches ±1 at 85.05113° |
| Mollweide | 2 | 0.5 | 2:1 | `2θ + sin 2θ = π sin φ`, then `x = λ cos θ/π`, `y = sin θ/2` |
| Robinson | 3 | 0.50719 | 1.97:1 | Tabulated every 5°, interpolated linearly |
| Orthographic | 4 | 1.0 | 1:1 | `x = cos φ sin λ`, `y = cos φ₀ sin φ - sin φ₀ cos φ cos λ` |

`λ` is the longitude from the central meridian and `φ` the latitude. Robinson's
two tables — the length of each parallel and its distance from the equator —
appear in both files and have to stay the same in both; the shader interpolates
them exactly as `MapProjection._robinson_at()` does, so a round trip through the
table is exact.

### Off the map

Not every point of the sheet is a place on the planet. `MapProjection.inverse()`
answers `null` and the shader's `map_inverse()` answers a zero third component,
which the fragment shader turns into a `discard`, so what is behind the map
shows through:

- outside the Mollweide ellipse and the Robinson outline, where the meridian
  the arithmetic gives is past ±180°;
- outside the orthographic disc, where the radius is past 1;
- the Mercator sheet has no such place, but the projection cannot reach a pole
  at all, so `forward()` reports latitudes past 85.05113° as not drawn.

A point exactly on the edge comes back a few bits outside it, because a
`Vector2` holds 32-bit floats, so both files allow `EDGE_SLACK` of 1e-6 past
each bound and clamp back onto it. Without it a pole would be reported as off
the map it was just drawn on.

### Uniforms

| Uniform | Type | Default | Description |
|---|---|---|---|
| `projection` | `int` | `0` | Which projection, matching `MapProjection.Kind` |
| `map_extent` | `float` | `0.5` | Half the height of the sheet, matching `MapProjection.extent()` |
| `map_centre` | `vec2` | `(0, 0)` | Latitude and longitude of the centre, in radians |

`map_centre.y` is the central meridian of every projection; `map_centre.x` is
the centre of the hemisphere an orthographic projection shows and is unused by
the other four. `Planet._process()` writes all three from `projection`, `lat`
and `lon`.

## Feature Geometry Rendering

A feature is drawn from one of three kinds of primitive, all of which follow
great circles on the unit sphere:

| Kind | Value | Vertices used | Drawn as |
|---|---|---|---|
| Triangle | 0 | a, b, c | A filled spherical triangle, one of the triangles a polygon was cut into |
| Segment | 1 | a, b | A great-circle capsule between the two ends of a polyline segment |
| Point | 2 | a | A round marker at one vertex of a multipoint |

### Math

For each fragment, the shader turns the latitude and longitude worked out above
into a position on the unit sphere. On the globe those two come straight from
UV; on a map they come from [the projection](#map-projections):

```
lat = (0.5 - UV.y) * PI   // the globe; a map goes through map_inverse()
lon = (UV.x - 0.5) * TAU
P   = (cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon))
```

A great circle between two points A and B defines a plane through the origin with normal `cross(A, B)`. A point P is on the inside of that edge if `dot(normalize(cross(A, B)), P) > 0`. A point is inside the spherical triangle if it passes the half-plane test for all three edges (assuming CCW winding).

A segment and a point are drawn by distance instead. `arc_distance(a, b, p)` gives
the distance from P to the arc from A to B: the distance to the plane of the arc
while P projects within it, and the chord distance to the nearer end outside it.
A point marker uses `chord(a, p)` directly. Both are antialiased with `smoothstep`,
which is also what gives the segment its rounded caps.

`Planet.arc_distance()` is the same function in GDScript, so a click and a
fragment agree on what a line covers. The tolerance the two use differs on
purpose: `Planet.LINE_HIT_WIDTH` and `Planet.POINT_HIT_RADIUS` are a little
wider than the drawn width, so a thin line stays easy to pick.

### Shader Uniforms

| Uniform | Type | Default | Description |
|---|---|---|---|
| `geometry_data` | `sampler2D` | — | Data texture holding the primitives |
| `geometry_count` | `int` | `0` | Number of primitives to render |
| `feature_data` | `sampler2D` | — | Where each feature is at the current time |
| `geometry_edge_width` | `float` | `0.001` | Width of the pale rim along the boundary of a filled polygon |
| `geometry_line_width` | `float` | `0.012` | Width of a polyline segment |
| `geometry_point_radius` | `float` | `0.02` | Radius of a multipoint marker |

The widths are chord lengths on the unit sphere, so 0.012 is about 0.7 degrees.

The colour a primitive is drawn in is whichever the active draw style gave the
feature it belongs to, worked out once per feature where the geometry is
flattened. See [Styling](Styling.md).

### Data Texture Layout

The `geometry_data` texture uses `FORMAT_RGBAF` (32-bit float per channel) with **width = primitive count** and **height = 4 rows**:

| Row | R | G | B | A |
|---|---|---|---|---|
| 0 | lat_a (rad) | lon_a (rad) | lat_b (rad) | lon_b (rad) |
| 1 | lat_c (rad) | lon_c (rad) | feature | kind |
| 2 | red | green | blue | alpha |
| 3 | edge a-b | edge b-c | edge c-a | unused |

Row 3 is 1 where that edge of a triangle came from the ring and 0 where ear
clipping cut it; see [Edge rendering](#edge-rendering). Only a triangle has
edges to mark, and only a fragment already inside one fetches the row, so the
extra texel costs nothing on the fragments that reject the primitive.

Each column stores one primitive, and the shader reads exact texels via
`texelFetch`. A vertex a kind does not use repeats vertex a, so a fetch never
reads uninitialised data. The vertices are in the frame of the feature the
primitive belongs to, and `feature` is the column of `feature_data` holding the
rotation that carries them into world space.

### Edge Rendering

A filled polygon carries a pale rim, antialiased using `smoothstep` over the
signed distance to the great-circle planes of its edges:

```glsl
float edge = smoothstep(geometry_edge_width * 0.5, geometry_edge_width, min_dist);
```

The rim is white and the fill is the feature colour blended over the Earth.

`min_dist` is the distance to the nearest edge **that came from the ring**, which
row 3 of the geometry texture says. A polygon is one shape to the person looking
at it but is drawn as the fan of triangles ear clipping cut it into, so taking
the nearest of all three edges would draw a rim along every cut and show the
triangulation through the fill. A triangle in the middle of a large polygon has
no ring edge at all and draws no rim; one cut from a triangle has all three.

`Feature.rebuild_triangles()` works this out while the ring indices are still to
hand: an edge is on the boundary exactly when its two vertices are neighbours in
the ring. It is kept in `Feature.triangle_edges`, one byte per triangle, beside
the triangles themselves. Until 0.4.0 every triangle drew its own rim, which
nothing noticed because no sample had more than two; see GP-0027.

### Winding Order

The half-plane tests assume **counter-clockwise (CCW)** winding, seen from
outside the sphere. `Feature.faces_outwards()` puts every derived triangle
that way round, whichever way the ring it came from was drawn.

## Per feature rotation

Rotating every vertex on the processor for every frame of an animation would
not hold up, so the shader does the turning instead. The geometry texture above
changes only when the tree does; a second texture holds one rotation per
feature, and that is the whole of what a step of an animation re-uploads,
whatever the triangle count is.

`feature_data` uses `FORMAT_RGBAF` with **width = feature count** and
**height = 3 rows**, one column of the rotation per row:

| Row | R | G | B | A |
|---|---|---|---|---|
| 0 | m00 | m10 | m20 | hovered |
| 1 | m01 | m11 | m21 | visible |
| 2 | m02 | m12 | m22 | unused |

`hovered` is 1 while the pointer rests on the feature, which brightens its
fill. `visible` is 0 while the feature is outside its time range, so it is
skipped without the geometry texture being rebuilt.

The pointer is not the only thing that ends a hover. A change of the current
time moves the features under a pointer that need not have moved at all, so
`Application.refresh_motion()` works out what the pointer is over again, from
the latitude and longitude it was last reported at, before it uploads the row.
It costs a hit test only while the pointer is on the globe.

The rotation is the feature's own composed with every group above it, worked
out from the root down by `Planet.Geometry.resolve()`; see
[Time](Time.md#groups-carry-motion). A `Basis` in Godot is column-major, so
`Basis.x`, `.y` and `.z` are the three columns, and `mat3(f0.xyz, f1.xyz,
f2.xyz)` in the shader is the same matrix.

Every primitive of one feature is contiguous in the geometry texture, so the
shader fetches the three rows once per feature rather than once per primitive:

```glsl
int feature = int(row1.z + 0.5);
if (feature != loaded_feature) {
    loaded_feature = feature;
    // three texelFetches, a mat3 and the two flags
}
```

`Planet.hit_test()` follows the same idea from the other end. Rather than
carrying the geometry into world space, it carries the point being asked about
into each feature's frame, through the transpose of that same rotation: one
rotation of one point per feature instead of one per vertex.

### The bounding cap

The hit test runs on every mouse motion, and walking every triangle of every
feature to answer it is most of what it costs. Each feature therefore carries a
cap: a centre and an angular radius that hold every vertex it draws, worked out
once by `Geometry.build_caps()` when the geometry is collected.

The cap is in the feature's own frame, like the vertices, so moving a feature
never invalidates it and a step of an animation does not touch it. The point
being asked about is already carried into that frame, so testing it is one dot
product against the centre. A point outside the cap is outside everything the
feature draws, and the whole feature is skipped before a triangle is looked at.

The radius is widened by the click tolerance, so a click just beside a thin line
still reaches the segment test. A feature wider than a hemisphere gets a cap of
the whole sphere, stored as a cosine of -1, and the loop then behaves exactly as
it did before caps existed.

On the 5,000 triangle sample of `Tests/run.py performance`, on an AMD Radeon
8060S, one hit test costs 76 microseconds with the caps and 5,925 without them,
which is 78 times faster. Most of that is features rejected outright: the cost
of the ones that survive the cap is what is left.

## GDScript API

### `Planet.Geometry`

What a feature tree comes to, held together so that the two textures can be
uploaded apart:

| Field | What it holds |
|---|---|
| `primitives` | One dictionary per primitive: `kind`, `verts`, `color`, `feature`, `index` |
| `features` | The features the primitives belong to, in the order they were met |
| `primitives[i]["edges"]` | For a triangle, which of its edges came from the ring, as `Feature.EDGE_AB`, `EDGE_BC` and `EDGE_CA` |
| `starts`, `ends` | Where each feature's primitives sit in `primitives`, as a half open range |
| `cap_centres`, `cap_cosines` | The bounding cap of each feature, in its own frame |
| `bases`, `shown` | Where each feature is and whether it is there, at `time` |

`verts` are `Vector2(latitude, longitude)` in **degrees**, in the feature's own
frame. `resolve(root, time)` fills `bases` and `shown` for a time, walking the
tree from the root so that each node composes its own rotation with what its
ancestors gave it.

### `Planet.collect_geometry(root: Feature, time := 0.0, styling: Styling = null) -> Geometry`

Walks a Feature tree and flattens the enabled features into primitives. A
polygon contributes its cached triangles, a polyline the segments between
consecutive vertices of each ring, and a multipoint one marker per vertex. The
result is resolved for the given time, so it can be drawn or hit tested
straight away.

The `styling` says which classes of geometry are drawn at all and what colour
each feature comes out; without one every feature is drawn in the colour it
carries, which is what a document said before there were any styles. This is
the only place either question is asked: a feature whose class is switched off
is not among the primitives, so it is neither drawn nor hit tested, and the
colour in row 2 of the geometry texture is whatever the active style resolved
to. See [Styling](Styling.md).

### `Planet.set_geometry(geometry: Geometry)`

Packs the primitives into a `FORMAT_RGBAF` image and sets `geometry_data` and
`geometry_count` on both the globe and the map material. A geometry with no
primitives clears everything.

### `Planet.set_feature_state(geometry: Geometry, hovered_feature: Feature = null)`

Packs `bases`, `shown` and the hover into `feature_data`. This is what a step
of an animation calls, and it is the only thing it calls.

```gdscript
geometry = Planet.collect_geometry(root, document.current_time)
planet.set_geometry(geometry)
planet.set_feature_state(geometry, hovered_feature)
```

### `Planet.hit_test(lat, lon, geometry) -> Feature`

The same tests on the CPU, walking the features backwards so the topmost one
wins, skipping whichever features `shown` says are not there, and skipping the
ones whose [bounding cap](#the-bounding-cap) the point falls outside. Returns
the feature under the point, or null.

## Outline Overlay

The shader draws a second, yellow layer over the geometry. It shows the shape
being drawn while the Draw tool places vertices, and otherwise traces the rings
of the selected feature.

### Outline Uniforms

| Uniform | Type | Default | Description |
|---|---|---|---|
| `outline_data` | `sampler2D` | — | Vertex data texture, one texel per vertex |
| `outline_vertex_count` | `int` | `0` | Number of outline vertices |
| `outline_line_width` | `float` | `0.002` | Width of outline line segments |
| `outline_dot_radius` | `float` | `0.006` | Radius of vertex dot markers |
| `outline_closing_opacity` | `float` | `0.25` | How faint the closing segment of an unfinished polygon is |

### Outline Data Texture Layout

Width = vertex count, height = 1, format `RGBAF`:

| Row | R | G | B | A |
|---|---|---|---|---|
| 0 | lat (rad) | lon (rad) | part start | style |

Several parts fit in one texture: every vertex carries the index its part begins
at, so the shader knows where a part ends without a second array. The style is
the same for every vertex of a part:

| Style | Meaning |
|---|---|
| 0 | Open: segments from the first vertex to the last, nothing more |
| 1 | Closed, with the closing segment faint — a polygon still being drawn |
| 2 | The vertex markers only — a multipoint |
| 3 | Closed, every segment alike — the rings of a selected polygon |

`Planet.OutlineStyle` names the same four values.

### Outline Math

**Vertex dots**: the chord distance from the fragment to the nearest vertex,
antialiased via `smoothstep`. Every vertex gets one, whatever the style.

**Line segments**: the same `arc_distance()` the geometry pass uses, which gives
each segment rounded caps.

**Closing segment**: a vertex whose successor starts a new part is the last of
its own. When the style closes the part, that vertex joins back to the vertex
the part started at, at reduced opacity for style 1 and at full opacity for
style 3.

The outline is composited on top of everything else using yellow color (`vec3(1, 1, 0)`) at the computed alpha.

## Notes

- The geometry, the outline and the graticule work in latitude and longitude, so a new projection needs its own inverse and nothing else.
- The data texture approach has no hard size limit — just add more primitives to the array.
- Performance scales linearly with primitive count — see below.

## Performance

Each fragment tests every triangle in the loop. Per triangle, the shader performs 3 `texelFetch` calls, 3 `latlon_to_unit` conversions (6 trig ops), 3 cross products, 3 normalizes, and 3 dot products — roughly 60–80 FLOPs plus the texture reads.

At 1080p the sphere may cover ~500K–1M fragments. Combined with the per-triangle cost:

| Triangles | Work per frame | Expectation |
|---|---|---|
| **< 500** | trivial | No issues on any GPU |
| **500–2,000** | moderate | Fine on discrete GPUs, may dip on integrated/mobile |
| **2,000–5,000** | heavy | Noticeable on mid-range, fine on high-end |
| **> 5,000** | very heavy | Needs optimization (spatial partitioning or bitmask texture) |

The main bottleneck is the **texture fetches inside the loop** (3 per triangle per fragment) more than the arithmetic. GPU caches help when nearby fragments read the same texels, but at thousands of triangles the loop length itself becomes the limiter.

For this application — continental cratons on a single planet — up to 10,000 triangles are expected, which requires optimization beyond the naive loop.

### Measured

On an AMD Radeon 8060S, at 1800x900, with every feature moving
(`uv run Tests/run.py performance`):

| Triangles | Frame, standing still | Frame, playing |
|---|---|---|
| 1,000 | 16.9 ms | 16.7 ms |
| 2,000 | 17.0 ms | 16.7 ms |
| 3,000 | — | 20.4 ms |
| 4,000 | — | 26.3 ms |
| 5,000 | 32.3 ms | 34.5 ms |

Sixty frames a second is 16.7 ms, so it holds to about 2,000 triangles and not
beyond. Playing costs almost nothing over standing still, which is the point of
keeping the rotation in `feature_data`: what a frame of an animation changes is
three texels per feature. The limit is the per-fragment loop over the triangles
themselves, which the strategies below address.

### Optimization Strategies

#### 1. Pre-rasterized overlay texture (recommended)

Instead of testing triangles per-fragment, rasterize all triangles into an equirectangular `Image` on the CPU, then sample it as a single texture in the shader.

- **Shader cost**: O(1) per fragment — just one extra `texture()` call regardless of triangle count
- **CPU cost**: only when triangles change (cratons move rarely)
- **Complexity**: low — replace the entire fragment loop with a texture sample
- **Resolution**: e.g. 4096x2048 gives ~0.09° per pixel, good enough for continental features

This is the clear winner for 10K triangles. The fragment shader becomes trivial, and the rasterization work moves to CPU where it only runs on data changes.

#### 2. Bounding box pre-filter

Add a lat/lon axis-aligned bounding box per triangle to the data texture. In the shader, check if the fragment's lat/lon falls within the AABB before doing the expensive great-circle tests.

- Most triangles are small relative to the sphere, so 95%+ get rejected by a cheap comparison
- Adds one extra texture row and 4 comparisons per triangle, but skips the 6 trig ops + 3 cross products for non-overlapping ones
- Still O(N) iteration, but with a much smaller constant

#### 3. Spatial grid index

Divide the sphere into a grid (e.g. 72x36 cells of 5°x5°). Store a per-cell list of overlapping triangle indices in a texture. The shader looks up which cell the fragment is in, then only tests those triangles.

- Reduces per-fragment work from 10K to maybe 10–50 tests
- More complex to implement (two-level texture lookup)
- Good if triangles change frequently and pre-rasterization is too slow
