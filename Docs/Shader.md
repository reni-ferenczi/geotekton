# Planet Shader

The planet shader (`Scenes/Planet/planet.gdshader`) renders the planet's color,
with the document's raster over it, a longitude/latitude grid overlay, the geometry of the features on the
surface of a sphere, and a yellow outline layer over that.

## Base Rendering

- **Planet color and raster**: a flat `planet_color`, with the document's image, sampled from an equirectangular projection via UV, blended over it; see [The raster](#the-raster)
- **Grid overlay**: longitude/latitude lines with configurable `split` (divisions), `width`, and `color`; pole-aware width correction in globe mode. The document holds one spacing in degrees and `ViewSettings.grid_split()` turns it into the divisions the shader counts

The globe carries the equirectangular grid on its own surface, so its UV *is*
the latitude and longitude of a fragment. A map does not: the shader turns UV
into a point of the projection's sheet and asks the projection which place of
the planet is drawn there. Everything after that — the planet color, the
raster, the grid, the features, the outline — is the same code in both views, because
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

## The raster

The base of the planet is one flat color, `planet_color`, which
`Planet.apply_view_settings()` sets from the document. It is ocean blue unless
the document says otherwise, and always opaque: the planet is never
see-through, so the alpha is dropped when the color is set and never read.

A document may wear an image over that color. `Logic/raster.gd` reads it from
the file the document names (PNG, JPEG and WebP through the engine's own
decoders, SVG rasterized to a fixed width) and hands the texture to
`Planet.set_raster()`. A `res://` path names an image the application ships and
is loaded as the imported resource it is. The only one so far,
`res://Assets/Textures/Earth.jpg`, is what the developers call the built in
Earth. The shader blends the image over the planet color before anything else is
drawn, so the grid, the features and the outline all sit on top of it:

```glsl
vec3 surface = planet_color.rgb;
if (raster_opacity > 0.0) {
	surface = mix(surface, texture(raster_tex, surface_uv).rgb, raster_opacity);
}
```

The image is sampled by `surface_uv`, so it is an equirectangular map of the
whole planet, and it follows every projection for free.

`raster_opacity` is zero, and the texture is never sampled, when the document
names no image, hides the one it names, or names one that cannot be read. A
document naming an image that has since been moved still opens: the planet
shows its own color and `Application.raster.error` says why, which the View
settings dialog shows beside the path and a test reads over the automation port.

| Uniform | Type | Default | Description |
|---|---|---|---|
| `planet_color` | `vec4`, `source_color` | ocean blue, `(0.16, 0.36, 0.60, 1)` | The planet under any raster; the alpha is not read |
| `raster_tex` | `sampler2D` | — | The image the planet wears |
| `raster_opacity` | `float` | `0.0` | How much of the planet color it covers; 0 is none |

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

### The export camera

On screen the camera leaves about a fifth of a margin around the sheet and
letterboxes for whatever shape the window is
(`PlanetView._fov_for_view()`). A picture of the map wants neither, so
`PlanetView.render_export()` sizes the viewport at the sheet's own aspect,
`width` by `round(width * extent)`, and gives the camera the field of view that
puts the top and bottom edges of the sheet on the edges of the image:

```gdscript
camera.fov = rad_to_deg(2.0 * atan(extent / camera.position.z))
```

The sheet is at the middle of the scene and the camera stands at `z` in front of
it, so half the height in view at that distance is `z * tan(fov / 2)`, which the
line above makes exactly `extent`. Half the width follows from the aspect,
`extent * width / (width * extent)`, which is 1: the half width the sheet has.
The view angle and the camera offset are zero for the frame and the zoom does not
come into it, since the field of view is worked out from the sheet rather than
from the window.

A picture is transparent around the sheet. For that frame the viewport gets
`transparent_bg`, the star field quad is hidden and the environment's
background mode is `BG_CLEAR_COLOR`, so the fragments the shader discards
outside the sheet or around the globe leave alpha 0. The sheet writes
`ALPHA = 1.0`, so the planet stays opaque. All three are put back with the
viewport size. A video frame skips this step and keeps the background. See
[Shell](Shell.md#exporting-a-picture-of-the-map).

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
| `geometry_line_width` | `float` | `0.012` | Width of a polyline segment |
| `geometry_point_radius` | `float` | `0.02` | Radius of a multipoint marker |

The widths are chord lengths on the unit sphere, so 0.012 is about 0.7 degrees.

A feature is drawn in one flat color: whichever the active draw style gave it,
worked out once per feature and held in row 3 of
[`feature_data`](#per-feature-rotation). The alpha of that color is the
feature's opacity, which the shader lays the color over what is beneath by. At
0 the planet shows through, and the feature is still hit tested. See
[Styling](Styling.md).

### Colour space

A `Color` holds sRGB values: the numbers the colour picker shows and the file
stores. The shader writes `ALBEDO` in linear light and the renderer encodes the
frame to sRGB on the way out, so a colour packed as it stands is lifted along
the transfer curve — 0.5 grey came out at 0.74 before GP-0032 — while the Earth
texture, declared `source_color`, was decoded properly.
`Planet.set_feature_state()` therefore packs `Color.srgb_to_linear()` into row 3
of `feature_data`, leaving the alpha as it is, and
`Planet.apply_view_settings()` does the same for the grid color. The
outline yellow is unaffected, since 0 and 1 map onto themselves.

The planet color is handled like the raster instead: `planet_color` is declared
`source_color`, so it is handed over as the document holds it and the engine
decodes it. `Tests/Rendered/test_scene.gd` checks a pixel of the bare planet
against the same place under an opaque image of the same color, which shows
that the two are decoded alike.

The shader also sets `SPECULAR` to zero. The default specular term brightens
every lit fragment towards white on top of the albedo, which is not what a
flat map of a planet should do. With the light shining from the camera a
feature therefore comes out at exactly the colour it was given, which is what
the rendered and scripted colour checks compare against.

### Data Texture Layout

The `geometry_data` texture uses `FORMAT_RGBAF` (32-bit float per channel) with **width = primitive count** and **height = 2 rows**:

| Row | R | G | B | A |
|---|---|---|---|---|
| 0 | lat_a (rad) | lon_a (rad) | lat_b (rad) | lon_b (rad) |
| 1 | lat_c (rad) | lon_c (rad) | feature | kind |

Each column stores one primitive, and the shader reads exact texels via
`texelFetch`. A vertex a kind does not use repeats vertex a, so a fetch never
reads uninitialised data. The vertices are in the frame of the feature the
primitive belongs to, and `feature` is the column of `feature_data` holding the
rotation that carries them into world space and the color they are drawn in.

Nothing here changes when a feature moves or changes color, so the texture is
built again only when the geometry itself does.

### Filled polygons

A polygon is drawn as the triangles ear clipping cut it into, and a fragment
inside any of them takes the feature's color. There is no rim along the
boundary and none along the cuts, so the polygon reads as one flat shape. The
pale rim it carried until GP-0033, with the per triangle edge flags that kept
the rim off the cuts, is gone.

### The selected feature

The feature selected in the tree is highlighted in yellow, and how depends on
its kind:

| Kind | Highlight | Drawn by |
|---|---|---|
| Polygon | An outline along its rings, with no vertex markers | Outline style 4 |
| Line (polyline, topology, a circle drawn as a line) | Its segments at twice `geometry_line_width`, opaque yellow | The segment pass, from the `selected` flag |
| Multipoint | Its vertex markers at twice `outline_dot_radius` | Outline style 5 |

A line is highlighted in the segment pass rather than by the outline overlay,
because the thicker line is the line itself: it follows the feature's rotation
like any other segment, and the flag rides in `feature_data`, so nothing is
uploaded twice. The yellow is opaque, so a line at an opacity of zero still
shows while it is selected. The fill of a polygon and the markers of a
multipoint ignore the flag.

`Application._highlighted_feature()` decides which feature carries the flag.
It is the selected leaf feature in every tool but Vertex, Circle, Light and
Measure. The last three draw overlays of their own. The Vertex tool traces the
rings with a dot on every vertex instead, styles 3, 0 and 2, since picking
vertices is what it is for, and a thick line would cover those dots.

The hit test does not widen with the highlight: a selected line is picked with
the same `Planet.LINE_HIT_WIDTH` as any other.

### Riders of the selected feature

With View > [Highlight riders](Editing.md#highlighting-riders) on, the features
riding on the highlighted one at the current time are drawn in `RIDER_COLOR`,
orange. `Application._find_riders()` asks `Coupling.riders()` for them, which
walks the couplings downward, and `_drawn_riders()` passes them on only while
`_highlighted_feature()` names a feature, so the tools that drop the selection
highlight drop this one too.

| Kind | Highlight | Drawn by |
|---|---|---|
| Polygon | An orange outline along its rings, fill unchanged | Outline style 6 |
| Line | Its segments at the normal `geometry_line_width`, opaque orange | The segment pass, from the `related` flag |
| Multipoint | Its markers at their normal size, opaque orange | The marker pass, from the `related` flag |

The width stays normal so a rider cannot be taken for the selection, which is
thicker as well as yellow. `RIDER_COLOR` in the shader is `Planet.RIDER_COLOR`,
an sRGB orange, in linear light; `test_shader_constants.gd` holds the two to
each other. The tree tints a rider's row in the same orange at a quarter
alpha, `FeatureTree.RIDER_TINT`.

`Application._refresh_feature_state()` works the riders out again, so they
follow a change of selection, of tool and of time along with the selection
highlight.

### Winding Order

The half-plane tests assume **counter-clockwise (CCW)** winding, seen from
outside the sphere. `Feature.faces_outwards()` puts every derived triangle
that way round, whichever way the ring it came from was drawn.

## Per feature rotation

Rotating every vertex on the processor for every frame of an animation would
not hold up, so the shader does the turning instead. The geometry texture above
changes only when the tree does; a second texture holds one rotation and one
color per feature, and that is the whole of what a step of an animation or a
change of color re-uploads, whatever the triangle count is.

`feature_data` uses `FORMAT_RGBAF` with **width = feature count** and
**height = 5 rows**, one column of the rotation per row in the first three, the
color in the fourth and the rider flag in the fifth:

| Row | R | G | B | A |
|---|---|---|---|---|
| 0 | m00 | m10 | m20 | hovered |
| 1 | m01 | m11 | m21 | visible |
| 2 | m02 | m12 | m22 | selected |
| 3 | red (linear) | green (linear) | blue (linear) | opacity |
| 4 | related | 0 | 0 | 0 |

The color is what the draw style resolved for the feature, which is why it
lives here rather than beside the vertices. The selection highlight of GP-0034
and the age colors of GP-0036 change it on every selection and every frame of
an animation, and neither has to rebuild the geometry texture to do so.

`hovered` is 1 while the pointer rests on the feature, which brightens its
fill. `visible` is 0 while the feature is outside its time range, so it is
skipped without the geometry texture being rebuilt. `selected` is 1 on the
feature the tree has selected, which draws its segments thicker and yellow; see
[The selected feature](#the-selected-feature). `related` is 1 on a feature
riding on the selected one while riders are highlighted, which draws its lines
and markers orange; see
[Riders of the selected feature](#riders-of-the-selected-feature). The first
four rows have no channel left over, so the flag takes a row of its own.
Selecting another feature re-uploads this texture and nothing else.

The pointer is not the only thing that ends a hover. A change of the current
time moves the features under a pointer that need not have moved at all, so
`Application.refresh_motion()` works out what the pointer is over again, from
the latitude and longitude it was last reported at, before it uploads the row.
It costs a hit test only while the pointer is on the globe.

The rotation is the feature's own, worked out for every feature at once by
`Planet.Geometry.resolve()`; a group above it moves nothing, see
[Time](Time.md#groups-do-not-move). A `Basis` in Godot is column-major, so
`Basis.x`, `.y` and `.z` are the three columns, and `mat3(f0.xyz, f1.xyz,
f2.xyz)` in the shader is the same matrix.

Every primitive of one feature is contiguous in the geometry texture, so the
shader fetches the four rows once per feature rather than once per primitive:

```glsl
int feature = int(row1.z + 0.5);
if (feature != loaded_feature) {
    loaded_feature = feature;
    // four texelFetches: a mat3, the two flags and the color
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
| `primitives` | One dictionary per primitive: `kind`, `verts`, `feature`, `index` |
| `features` | The features the primitives belong to, in the order they were met |
| `starts`, `ends` | Where each feature's primitives sit in `primitives`, as a half open range |
| `cap_centres`, `cap_cosines` | The bounding cap of each feature, in its own frame |
| `bases`, `shown` | Where each feature is and whether it is there, at `time` |
| `colors` | The color each feature is drawn in, sRGB with the opacity in alpha |

`verts` are `Vector2(latitude, longitude)` in **degrees**, in the feature's own
frame. `resolve(root, time)` fills `bases` and `shown` for a time, one feature
after another, from each feature's own keyframes. `recolor(styling)` fills
`colors` from a styling, or from each feature's own color without one.

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
color in `colors` is whatever the active style resolved to. See
[Styling](Styling.md).

### `Planet.set_geometry(geometry: Geometry)`

Packs the primitives into a `FORMAT_RGBAF` image and sets `geometry_data` and
`geometry_count` on both the globe and the map material. A geometry with no
primitives clears everything.

### `Planet.set_feature_state(geometry: Geometry, hovered_feature: Feature = null, selected_feature: Feature = null, related: Array[Feature] = [])`

Packs `bases`, `shown`, `colors`, the hover, the selection and the riders into
`feature_data`. This is what a step of an animation calls, and it is the only
thing it calls. A change of color takes the same path:
`Application.refresh_colors()` calls `geometry.recolor()` and then this, which
is what dragging the color picker or changing the opacity costs. So does a
change of selection or of tool.

```gdscript
geometry = Planet.collect_geometry(root, document.current_time)
planet.set_geometry(geometry)
planet.set_feature_state(geometry, hovered_feature, selected_feature)
```

### `Planet.hit_test(lat, lon, geometry) -> Feature`

The same tests on the CPU, walking the features backwards so the topmost one
wins, skipping whichever features `shown` says are not there, and skipping the
ones whose [bounding cap](#the-bounding-cap) the point falls outside. Returns
the feature under the point, or null.

## Outline Overlay

The shader draws a second, yellow layer over the geometry. It shows the shape
being drawn while the Draw tool places vertices, the points of the Circle,
Measure and Light tools, and otherwise the outline of a selected polygon or
the markers of a selected multipoint. A selected line is drawn by the segment
pass instead; see [The selected feature](#the-selected-feature).

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
| 3 | Closed, every segment alike — a polygon in the Vertex tool, a closed circle |
| 4 | Closed like 3, with no vertex markers — the rings of a selected polygon |
| 5 | The vertex markers only, twice the size — a selected multipoint |
| 6 | Closed like 4, in `RIDER_COLOR`: the rings of a polygon riding on the selected feature |
| 7 | Open like 0, at `geometry_line_width` rather than `outline_line_width`, with no vertex markers: the arms of the Pole tool's cross |

`Planet.OutlineStyle` names the same eight values.

### Outline Math

**Vertex dots**: the chord distance from the fragment to the nearest vertex,
antialiased via `smoothstep`. Every vertex gets one except in styles 4, 6 and 7. Style 5
divides the distance by `SELECTED_MARKER_SCALE`, which draws the same dot twice
as large.

**Line segments**: the same `arc_distance()` the geometry pass uses, which gives
each segment rounded caps. Style 7 segments are as wide as a feature line,
`geometry_line_width`, so the Outline line width preference, which scales
`outline_line_width`, leaves them alone.

**Closing segment**: a vertex whose successor starts a new part is the last of
its own. When the style closes the part, that vertex joins back to the vertex
the part started at, at reduced opacity for style 1 and at full opacity for
styles 3 and 4.

The outline is composited on top of everything else using yellow color (`vec3(1, 1, 0)`) at the computed alpha. Style 6 keeps a distance of its own and is laid down in `RIDER_COLOR` first, so the yellow of a selection drawn over the same place wins.

## Notes

- The geometry, the outline and the grid work in latitude and longitude, so a new projection needs its own inverse and nothing else.
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
| 2,000 | 18.5 ms | 16.7 ms |
| 3,000 | — | 20.4 ms |
| 4,000 | — | 26.3 ms |
| 5,000 | 29.4 ms | 31.3 ms |

The 2,000 and 5,000 rows were measured again once GP-0033 had moved the color
into `feature_data` and dropped the rim. The other rows are older.

Playing under the Feature age style with the custom ramp, which works out
every feature's color again on every frame (GP-0036), measured 16.7 ms at 2,000
triangles against 17.0 ms playing in flat colors, and 34.5 ms at 5,000 against
33.3 ms. The engine reports whole frames per second, so 33.3 and 34.5 ms are
neighboring readings of 30 and 29.

Sixty frames a second is 16.7 ms, so it holds to about 2,000 triangles and not
beyond. `Planet.MAX_PRIMITIVES` is where that stops being a slow frame and
becomes no frame at all: the geometry texture is one texel per primitive wide,
and 16,384 is the widest a desktop device is required to make one. A document
holding more than that is drawn up to the limit and the rest of its features
are left out — counted on `Geometry.dropped`, still in the feature tree, and
still saved. A [GPlates import](Import.md) is the only thing that reaches it
today; raising the limit is GP-0030 in the workspace ticket list.

Playing costs almost nothing over standing still, which is the point of
keeping the rotation in `feature_data`: what a frame of an animation changes is
five texels per feature. The limit is the per-fragment loop over the triangles
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
