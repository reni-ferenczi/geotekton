# Planet Shader

The planet shader (`Scenes/Planet/planet.gdshader`) renders the Earth texture
with a longitude/latitude grid overlay, the geometry of the features on the
surface of a sphere, and a yellow outline layer over that.

## Base Rendering

- **Earth texture**: sampled from an equirectangular projection via UV
- **Grid overlay**: longitude/latitude lines with configurable `split` (divisions), `width`, and `color`; pole-aware width correction in globe mode

## Feature Geometry Rendering

A feature is drawn from one of three kinds of primitive, all of which follow
great circles on the unit sphere:

| Kind | Value | Vertices used | Drawn as |
|---|---|---|---|
| Triangle | 0 | a, b, c | A filled spherical triangle, one of the triangles a polygon was cut into |
| Segment | 1 | a, b | A great-circle capsule between the two ends of a polyline segment |
| Point | 2 | a | A round marker at one vertex of a multipoint |

### Math

For each fragment, the shader converts UV coordinates to a position on the unit sphere:

```
lat = (0.5 - UV.y) * PI
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
| `geometry_edge_width` | `float` | `0.001` | Width of the white rim on a filled triangle |
| `geometry_line_width` | `float` | `0.012` | Width of a polyline segment |
| `geometry_point_radius` | `float` | `0.02` | Radius of a multipoint marker |

The widths are chord lengths on the unit sphere, so 0.012 is about 0.7 degrees.

### Data Texture Layout

The `geometry_data` texture uses `FORMAT_RGBAF` (32-bit float per channel) with **width = primitive count** and **height = 3 rows**:

| Row | R | G | B | A |
|---|---|---|---|---|
| 0 | lat_a (rad) | lon_a (rad) | lat_b (rad) | lon_b (rad) |
| 1 | lat_c (rad) | lon_c (rad) | feature | kind |
| 2 | red | green | blue | alpha |

Each column stores one primitive, and the shader reads exact texels via
`texelFetch`. A vertex a kind does not use repeats vertex a, so a fetch never
reads uninitialised data. The vertices are in the frame of the feature the
primitive belongs to, and `feature` is the column of `feature_data` holding the
rotation that carries them into world space.

### Edge Rendering

The rim of a filled triangle is antialiased using `smoothstep` over the minimum signed distance to the three great-circle planes:

```glsl
float edge = smoothstep(geometry_edge_width * 0.5, geometry_edge_width, min_dist);
```

The rim is white and the fill is the feature colour blended over the Earth. Since
every triangle carries its own rim, the cuts inside a polygon show as hairlines.

### Winding Order

The half-plane tests assume **counter-clockwise (CCW)** winding, seen from
outside the sphere. `Feature.ensure_front_winding()` puts every derived triangle
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
| `starts`, `ends` | Where each feature's primitives sit in `primitives`, as a half open range |
| `cap_centres`, `cap_cosines` | The bounding cap of each feature, in its own frame |
| `bases`, `shown` | Where each feature is and whether it is there, at `time` |

`verts` are `Vector2(latitude, longitude)` in **degrees**, in the feature's own
frame. `resolve(root, time)` fills `bases` and `shown` for a time, walking the
tree from the root so that each node composes its own rotation with what its
ancestors gave it.

### `Planet.collect_geometry(root: Feature, time := 0.0) -> Geometry`

Walks a Feature tree and flattens the enabled features into primitives. A
polygon contributes its cached triangles, a polyline the segments between
consecutive vertices of each ring, and a multipoint one marker per vertex. The
result is resolved for the given time, so it can be drawn or hit tested
straight away.

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

- The UV-to-latlon conversion is the same for both globe (SphereMesh) and map (PlaneMesh) views, so the geometry renders correctly in both modes.
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
