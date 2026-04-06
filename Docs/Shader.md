# Planet Shader

The planet shader (`Scenes/Planet/planet.gdshader`) renders the Earth texture with a longitude/latitude grid overlay and craton (continental segment) triangles on the surface of a sphere.

## Base Rendering

- **Earth texture**: sampled from an equirectangular projection via UV
- **Grid overlay**: longitude/latitude lines with configurable `split` (divisions), `width`, and `color`; pole-aware width correction in globe mode

## Craton Rendering

Cratons are rendered as spherical triangles whose edges follow great circles on the unit sphere. The primitive element is a single triangle defined by three lat/lon vertices.

### Math

For each fragment, the shader converts UV coordinates to a position on the unit sphere:

```
lat = (0.5 - UV.y) * PI
lon = (UV.x - 0.5) * TAU
P   = (cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon))
```

A great circle between two points A and B defines a plane through the origin with normal `cross(A, B)`. A point P is on the inside of that edge if `dot(normalize(cross(A, B)), P) > 0`. A point is inside the spherical triangle if it passes the half-plane test for all three edges (assuming CCW winding).

### Shader Uniforms

| Uniform | Type | Default | Description |
|---|---|---|---|
| `craton_data` | `sampler2D` | — | Data texture containing triangle vertices and colors |
| `craton_count` | `int` | `0` | Number of triangles to render |
| `craton_edge_width` | `float` | `0.005` | Width of triangle edge lines (antialiased via smoothstep) |

### Data Texture Layout

The `craton_data` texture uses `FORMAT_RGBAF` (32-bit float per channel) with **width = triangle count** and **height = 3 rows**:

| Row | R | G | B | A |
|---|---|---|---|---|
| 0 | lat_a (rad) | lon_a (rad) | lat_b (rad) | lon_b (rad) |
| 1 | lat_c (rad) | lon_c (rad) | unused | unused |
| 2 | red | green | blue | alpha |

Each column stores one triangle. The shader reads exact texels via `texelFetch`.

### Edge Rendering

Edges are antialiased using `smoothstep` over the minimum signed distance to the three great-circle planes:

```glsl
float edge = smoothstep(craton_edge_width * 0.5, craton_edge_width, min_dist);
```

Edge color is white; fill color is the triangle's color blended over the earth base.

### Winding Order

The half-plane tests assume **counter-clockwise (CCW)** winding. If a triangle appears inverted (nothing renders, or the complement renders), swap any two vertices.

## GDScript API

### `Planet.set_cratons(triangles: Array)`

Uploads craton triangles to the shader. Each entry is a dictionary:

```gdscript
{
    "verts": [Vector2(lat_deg, lon_deg), Vector2(...), Vector2(...)],
    "color": Color(r, g, b, a)
}
```

Vertices use **degrees** (latitude in [-90, 90], longitude in [-180, 180]). The method converts to radians, packs into a `FORMAT_RGBAF` image, and sets the `craton_data` and `craton_count` parameters on both globe and map shader materials.

Passing an empty array clears all cratons.

### `Planet.collect_triangles(root: Feature) -> Array`

Static helper that walks a Feature tree and extracts triangles. Every **3 consecutive vertices** in a leaf feature form one triangle. Only enabled features are included.

```gdscript
var triangles = Planet.collect_triangles(feature_root)
planet.set_cratons(triangles)
```

## Outline Rendering (Drawing Preview)

The shader also renders a polygon outline preview used during the Draw tool's vertex placement phase. This is separate from committed craton triangles.

### Outline Uniforms

| Uniform | Type | Default | Description |
|---|---|---|---|
| `outline_data` | `sampler2D` | — | Vertex data texture: each texel `(lat_rad, lon_rad, 0, 0)` |
| `outline_vertex_count` | `int` | `0` | Number of outline vertices |
| `outline_closed` | `bool` | `false` | Draw closing segment from last to first vertex |
| `outline_line_width` | `float` | `0.004` | Width of outline line segments |
| `outline_dot_radius` | `float` | `0.012` | Radius of vertex dot markers |

### Outline Data Texture Layout

Width = vertex count, height = 1, format `RGBAF`:

| Row | R | G | B | A |
|---|---|---|---|---|
| 0 | lat (rad) | lon (rad) | unused | unused |

### Outline Math

**Vertex dots**: Angular distance from fragment to vertex approximated as `sqrt(2 * (1 - dot(V, P)))` where V and P are unit sphere positions. This equals the chord distance, which approximates the arc distance for small angles. Dots are antialiased via `smoothstep`.

**Line segments**: Each segment between vertices A and B is rendered as a great-circle capsule:

1. Compute great-circle plane normal: `N = normalize(cross(A, B))`
2. Distance to the plane: `d = |dot(N, P)|`
3. Check if P projects within the arc: `dot(cross(N, A), P) >= 0` and `dot(cross(B, N), P) >= 0`
4. If within arc, use plane distance. Otherwise, use chord distance to nearest endpoint.

This produces rounded-cap line segments (capsule shapes) that follow great circles on the sphere.

**Closing segment**: When `outline_closed` is true, an additional segment from the last vertex to the first is included in the loop by using `seg_count = outline_vertex_count` instead of `outline_vertex_count - 1`.

The outline is composited on top of everything else using yellow color (`vec3(1, 1, 0)`) at the computed alpha.

## Notes

- The UV-to-latlon conversion is the same for both globe (SphereMesh) and map (PlaneMesh) views, so cratons render correctly in both modes.
- The data texture approach has no hard size limit — just add more triangles to the array.
- Performance scales linearly with triangle count — see below.

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
