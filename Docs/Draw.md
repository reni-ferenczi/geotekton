# Draw Tool

The Draw tool places the geometry of a feature on the planet surface: click to
put vertices down, then press Enter to commit them.

## Tool Selection

The toolbar above the planet view holds the mutually exclusive tool buttons.
Only the two this page is about are listed here; the rest are in
[Editing](Editing.md#tools):

- **Move** (ToolMove icon) — Default. Enables rotation and dragging of the globe.
- **Draw** (Edit/pencil icon) — Enables drawing on the globe surface.

Only one tool can be active at a time. They behave as a radio button group:
selecting one deselects the others.

### Enabling the Draw Tool

The Draw button is **disabled** when no leaf feature is selected, that is when a
group or nothing is selected, and when the selected feature is typed Topology,
whose sections are picked with the section table's
[Pick toggle](Editing.md#building-one) instead.

If a newly selected feature has **no geometry** yet, the tool its type is drawn
with is activated to streamline the workflow.

### The geometry kind

What the Draw tool produces follows the selected feature's
[type](Properties.md#what-the-type-restricts): a Polygon gives a polygon, a Line
a polyline, Points a multipoint and a Circle a circle. A feature holds one kind of geometry, so once
it holds anything, everything else drawn on it joins that as another part of the
same kind, whatever the type says.

| Kind | Minimum vertices | What a part is |
|---|---|---|
| Polygon | 3 | A closed outline, filled in |
| Polyline | 2 | An open line through the vertices |
| Multipoint | 1 | Separate markers, one per vertex |
| Circle | 2 or 3 clicks | A polyline around a circle, cut into the Circle segments count |

A Circle takes its points differently. Two clicks are the centre and a point
on the rim; three are points the circle passes through. A fourth click starts
a new circle, and Enter commits the circle the clicks describe. Snapping and
tracing do not apply, and the Circle segments box is shown in the toolbar
while Draw is armed on a Circle. RMB, Ctrl+Z, Ctrl+Y and Escape work on the
clicked points as they do on vertices. See
[Drawing a circle](Editing.md#drawing-a-circle). The rest of this page is about
the other three kinds.

The minimums are `Feature.MINIMUM_VERTICES`, which the Vertex tool reads as
well: it refuses to delete a vertex that would leave a part under its minimum.
See [Deleting](Editing.md#deleting).

## Drawing Process

The user clicks vertices one by one, then presses Enter to commit them to the
selected feature.

### Input Mapping

| Input | Action |
|-------|--------|
| **LMB** | Place the next vertex on the globe surface, on a nearby vertex of a shown feature while Edit > Snap to vertices is on |
| **Shift+LMB** | With snapping on, when the last point sits on a vertex of the same ring: add the vertices along the ring up to the clicked one |
| **Ctrl+Shift+V** | Paste Shape: add the vertices of the copied shape to the drawing |
| **RMB** or **Ctrl+Z** | Take the last placed vertex back |
| **Ctrl+Y** | Put the last vertex taken back down again |
| **Enter** | Commit the vertices to the feature |
| **Escape** | Cancel the current outline, discard all placed vertices |
| **MMB** | Planet rotation (always available, unchanged) |

Snapping, tracing along a ring and pasting a shape are described in
[Snapping](Editing.md#snapping) and [Copying a shape](Editing.md#copying-a-shape).
Each of them only adds held points, so Enter still decides what is committed.

### Visual Feedback

While placing vertices, the shader renders a **live preview overlay** in white:

- **White dots** at each placed vertex (antialiased circles)
- **White lines** connecting consecutive vertices along great-circle arcs,
  unless the kind is Multipoint, which shows the dots alone
- **Closing line** from the last vertex back to the first, faint, once a Polygon
  has three vertices, so the shape it would close into is visible

This preview is ephemeral — it is not saved to the feature until Enter is pressed.

The vertices are not in the document either, so Undo and Redo work on them
while any are held: Ctrl+Z takes the last one back and Ctrl+Y puts it down
again, and the document's own undo stack is reached only once the outline is
empty. Without this, Ctrl+Z halfway through a shape would undo the creation of
the very feature being drawn on. The vertices taken back are forgotten by the
next click, a commit, Escape or a change of tool. The points of a circle and
those of the Measure tool are held the same way.

Outside drawing, the selected feature is highlighted instead: a translucent
white outline along the rings of a polygon, a white halo along a line, larger
markers on a multipoint, and no dots on the vertices. See [Editing](Editing.md#the-feature-tree).

### Step by Step

1. Select a leaf feature in the feature tree (or create one, which is a Polygon).
2. Pick its type in the Properties panel, while the feature is still empty.
3. Activate the Draw tool (or let it auto-activate for empty features).
4. **Left-click** on the globe to place vertices in order.
5. Use **right-click** or **Ctrl+Z** to take the last vertex back, and
   **Ctrl+Y** to put it down again.
6. Press **Enter** to commit them, once the kind has enough of them.
7. Repeat to add more parts to the same feature, or select a different feature.

Press **Escape** at any time to discard the current outline and start over.

### State Clearing

The in-progress outline is automatically cleared when:

- Enter commits the shape
- Escape cancels it
- The active tool switches to Move
- A different feature is selected in the tree

## Data Model

A feature stores its geometry as `rings`, each an ordered
`PackedVector2Array` of `(latitude_deg, longitude_deg)` vertices, plus a
`geometry_kind` saying what those rings mean. A ring is closed only for a
polygon; several rings on one polygon are separate outlines, not holes.

The vertices are kept in the frame of the feature itself, before the rotation
its keyframes give it at the current time is applied, so moving a feature never
rewrites them. What the user clicks is in world space, so the inverse of that
rotation, `Feature.world_basis(root, feature, time).transposed()` through
`Feature.apply_basis()`, takes it back to that frame on commit. See
[Time](Time.md#keyframes).

For a polygon, `Feature.rebuild_triangles()` derives the triangles that fill it,
on load and after every edit. They are a cache: never written to a file, and
copied rather than recomputed when the undo stack clones the tree.

After committing, the tool:
1. Saves an undo version via `document.record()`.
2. Reloads the feature tree via `features.reload()`.
3. Refreshes the rendering via `refresh_geometry()`.

## Triangulation — Ear Clipping

`Feature.ear_clip()` decomposes a polygon ring into triangles:

1. **Signed area** is computed via the shoelace formula to determine the polygon's winding direction (CW or CCW).
2. The algorithm maintains a list of remaining vertex indices and iterates through them.
3. For each vertex `i`, it checks whether the triangle `(i-1, i, i+1)` is an **ear**:
   - The triangle must be **convex** (its cross product matches the polygon's winding sign).
   - **No other polygon vertex** may fall inside the triangle (point-in-triangle test).
4. If the triangle is a valid ear, it is output and vertex `i` is removed from the list.
5. This repeats until only 3 vertices remain, which form the final triangle.

The algorithm runs in the 2D lat/lon plane and handles **concave polygons** correctly. Self-intersecting polygons are not supported and will produce undefined results.

Two kinds of ring have no proper shape in that plane, and are handled first:

- **Across the date line.** The longitudes are unwrapped before clipping, so
  each step from one vertex to the next is under 180 degrees. A quad from 175 E
  to 175 W is clipped as the 10 degree quad it is, not as one 350 degrees wide.
- **Round a pole.** When the longitude steps of a ring, each taken the short
  way, add up to a full turn, the ring encloses a pole. It is cut into a fan of
  triangles `(pole, v[i], v[i+1])`, one per vertex, with the pole on the side
  where most of the ring's latitude lies. The pole is added to the triangle
  list as an extra vertex. A ring at one latitude, which a circle centered on
  the pole is, would otherwise have no area and no fill at all.

### Winding Order Correction

Ear clipping keeps the winding of the ring it was given, which is whichever way
round the user happened to click. `Feature.rebuild_triangles()` then turns each
triangle so that it faces away from the centre of the sphere, which
`Feature.faces_outwards()` answers:

1. The three vertices (lat/lon in degrees) are converted to 3D unit sphere positions.
2. The cross product of two edges gives the triangle normal.
3. If the normal points inward (dot product with centroid < 0), two vertices are swapped.

This ensures all triangles are visible from outside the planet regardless of the
order the user clicked the vertices. The swap is made on the ring indices rather
than on the vertices, because it permutes the triangle's edges and
`rebuild_triangles()` has to know afterwards which of them came from the ring;
see [Shader](Shader.md#edge-rendering).

## Rendering Pipeline

`Planet.collect_geometry(root)` walks the feature tree and flattens every
enabled feature into primitives — triangles, segments or markers — which
`Planet.set_geometry()` uploads to the shader as a data texture.
`Planet.set_outline()` uploads the overlay on top of it. See
[Shader](Shader.md) for both texture layouts and the tests the shader runs.

## Color

Every kind is drawn in the colour of its feature. A new feature starts in the
Polygon color, `Color(0.36, 0.60, 0.33)`, a medium green that stands out
against the blue ocean; see [Properties](Properties.md#the-type-catalog).
The outline overlay is white, apart from the orange outline of a child of the
selection. A closed ring in it, such as the outline of a selected polygon or
a finished circle, is drawn at 60 percent opacity; see
[Shader](Shader.md#outline-overlay).
