# Draw Tool

The Draw tool allows users to paint craton shapes (continental fragments) directly on the planet surface by clicking to place polygon vertices, then closing the shape to fill it with triangles.

## Tool Selection

The toolbar above the planet view contains two mutually exclusive tool buttons:

- **Move** (ToolMove icon) — Default. Enables rotation and dragging of the globe.
- **Draw** (Edit/pencil icon) — Enables craton drawing on the globe surface.

Only one tool can be active at a time. They behave as a radio button group: selecting one deselects the other.

### Enabling the Draw Tool

The Draw button is **disabled** when no leaf feature is selected (i.e., when a group or nothing is selected). It becomes enabled when a leaf feature node is selected in the feature tree.

If a newly selected feature has **no vertices** (no craton data yet), the Draw tool is automatically activated to streamline the workflow.

## Drawing Process

Drawing uses a **polygon outline mode**. The user clicks vertices one by one to trace the craton boundary, then presses Enter to close and triangulate the shape.

### Input Mapping

| Input | Action |
|-------|--------|
| **LMB** | Place the next vertex on the globe surface |
| **RMB** | Undo the last placed vertex (pop from outline) |
| **Enter** | Close the polygon and triangulate — commits to the feature |
| **Escape** | Cancel the current outline, discard all placed vertices |
| **MMB** | Planet rotation (always available, unchanged) |

### Visual Feedback

While placing vertices, the shader renders a **live preview overlay**:

- **Yellow dots** at each placed vertex (antialiased circles)
- **Yellow lines** connecting consecutive vertices along great-circle arcs
- **Closing line** from the last vertex back to the first (shown when 3+ vertices are placed) so the user can preview the final polygon shape

This preview is ephemeral — it is not saved to the feature until Enter is pressed.

### Step by Step

1. Select a leaf feature in the feature tree (or create one).
2. Activate the Draw tool (or let it auto-activate for empty features).
3. **Left-click** on the globe to place vertices in order, tracing the craton boundary.
4. Use **right-click** to undo mistakes (removes the last vertex).
5. When satisfied with the polygon shape (3+ vertices required), press **Enter** to close and fill.
6. The polygon is triangulated and appended to the feature's craton data.
7. Repeat to add more polygons to the same feature, or select a different feature.

Press **Escape** at any time to discard the current outline and start over.

### State Clearing

The in-progress outline is automatically cleared when:

- Enter commits the polygon
- Escape cancels it
- The active tool switches to Move
- A different feature is selected in the tree

## Triangulation Algorithm — Ear Clipping

When the user presses Enter with 3+ vertices, the polygon is decomposed into triangles using the **ear-clipping algorithm**:

1. **Signed area** is computed via the shoelace formula to determine the polygon's winding direction (CW or CCW).
2. The algorithm maintains a list of remaining vertex indices and iterates through them.
3. For each vertex `i`, it checks whether the triangle `(i-1, i, i+1)` is an **ear**:
   - The triangle must be **convex** (its cross product matches the polygon's winding sign).
   - **No other polygon vertex** may fall inside the triangle (point-in-triangle test).
4. If the triangle is a valid ear, it is output and vertex `i` is removed from the list.
5. This repeats until only 3 vertices remain, which form the final triangle.

The algorithm runs in the 2D lat/lon plane and handles **concave polygons** correctly. Self-intersecting polygons are not supported and will produce undefined results.

### Winding Order Correction

After ear clipping, each output triangle is corrected to have **front-facing winding order** on the sphere:

1. The three vertices (lat/lon in degrees) are converted to 3D unit sphere positions.
2. The cross product of two edges gives the triangle normal.
3. If the normal points inward (dot product with centroid < 0), two vertices are swapped.

This ensures all triangles are visible from outside the planet regardless of the order the user clicked the vertices.

## Data Model

Each leaf feature stores its craton as a flat array of `Vector2` vertices in `Feature.vertices`. Every 3 consecutive vertices define one triangle. Vertices are in `(latitude_deg, longitude_deg)` format.

Drawing appends new triangles to the existing array, so multiple polygons can be drawn on the same feature.

After committing, the tool:
1. Saves an undo version via `document.record()`.
2. Reloads the feature tree via `features.reload()`.
3. Refreshes the craton rendering via `refresh_cratons()`.

## Rendering Pipeline

### Committed Cratons

`Planet.collect_triangles(root)` walks the entire feature tree, extracts all enabled features' triangle data, and uploads it to the planet shader as a data texture. The shader performs per-fragment great-circle half-plane tests to render filled triangles with edge outlines. See `Docs/Shader.md` for shader details.

### Outline Preview

During drawing, `Planet.set_outline(vertices, closed)` uploads the in-progress polygon vertices to the shader as a separate data texture. The shader renders:

- **Vertex dots**: For each vertex, computes the angular distance from the fragment to the vertex position. Draws an antialiased circle using `smoothstep` over `outline_dot_radius`.
- **Line segments**: For each pair of consecutive vertices, computes the great-circle capsule distance (plane distance within the arc, endpoint distance outside). Draws antialiased lines using `smoothstep` over `outline_line_width`.
- **Closing segment**: When `outline_closed` is true (3+ vertices), an additional segment from the last vertex back to the first is drawn.

The outline is rendered after cratons, composited on top with yellow color at full opacity.

#### Outline Shader Uniforms

| Uniform | Type | Default | Description |
|---|---|---|---|
| `outline_data` | `sampler2D` | — | Vertex positions: each texel is `(lat_rad, lon_rad, 0, 0)` |
| `outline_vertex_count` | `int` | `0` | Number of vertices in the outline |
| `outline_closed` | `bool` | `false` | Whether to draw the closing segment (last → first) |
| `outline_line_width` | `float` | `0.004` | Width of outline lines |
| `outline_dot_radius` | `float` | `0.012` | Radius of vertex dots |

## Color

All cratons currently use the feature's color (default `Color.CHOCOLATE`). The outline preview is always yellow.
