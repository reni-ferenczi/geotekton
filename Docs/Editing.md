# Usage

## Tools

The toolbar contains six mutually exclusive tool buttons, two switches, a
selector and a number:

- **Move** — Default. Enables globe rotation, dragging, and feature movement.
- **Draw** — Enables drawing on the globe surface. See `Docs/Draw.md` for full details.
- **Vertex** — Edits the vertices of the selected feature. Needs a leaf feature
  holding vertices of its own; see [The Vertex tool](#the-vertex-tool).
- **Measure** — Reports great circle distances in the status bar; see
  [The Measure tool](#the-measure-tool).
- **Circle** — Draws a small circle from a centre or through three points; see
  [The Circle tool](#the-circle-tool).
- **Topology** — Builds a line topology out of the features it runs along; see
  [Line topologies](#line-topologies).
- **Snap** — Whether a dragged vertex jumps onto a nearby one. Only the Vertex
  tool uses it; see [Snapping](#snapping).
- **Split** — Cuts the selected feature in two at the vertex the Vertex tool is
  holding; see [Splitting](#splitting). Its tooltip says why it is unavailable
  when it is.
- **Geometry kind** — What the Draw and Circle tools produce: Polygon, Polyline
  or Multipoint. Only the kinds the selected feature's type allows can be
  picked; see [Properties](Properties.md#what-the-type-restricts).
- **Segments** — How many segments a small circle is cut into when it is
  committed, from 3 to 720.

Only one of Move, Draw, Vertex, Measure, Circle and Topology is active at a
time. Everything but
Move takes the clicks on the planet for itself, so selecting a feature, moving
one and the right click menu wait until Move comes back. Rotating the globe with
the middle button always works.

Undo and redo leave the active tool alone: they put another version of the same
document in place, which is no reason to take a tool out of someone's hand mid
edit. File > New and File > Open do go back to Move, since whatever was half
drawn or half picked belonged to the document being left.

## The feature tree

Each row of the tree carries the title of the feature or group and two buttons:
a colour swatch, on a feature only, and a switch that enables the node. A
disabled node is neither drawn nor hit tested, itself and everything under it.
A row is greyed out while its feature is outside its time range at the current
time, which is when the globe leaves it out as well; see
[Time](Time.md#being-there-at-all).
A right click on the swatch puts the colour back to the one the feature's type
gives. Everything else about a feature is edited in the
[Properties](Properties.md) panel.

Up to 0.1.0 the rows also had invert, single, wrap, resize and repeat, five
switches left over from the rule editor this interface came from. Nothing read
them and they were dropped in 0.2.0, files included.

## Moving Features

When the Move tool is active and something with geometry under it is selected in
the feature tree, left-clicking on the globe starts moving it. That can be a
group as well as a leaf feature, because a group carries motion its children
inherit; only the root is left out. A move writes the keyframe at the current
time, so moving at two times is what makes something move at all — see
[Time](Time.md#making-a-keyframe).

### Input Mapping

| Input | Action |
|-------|--------|
| **LMB press** on globe | Start moving the selected feature |
| **Mouse motion** (while moving) | Turn the feature so that the anchor follows the cursor |
| **LMB release** | Finish moving — saves an undo version |
| **MMB hold** (while moving) | Temporarily rotate the planet instead of moving the feature |
| **MMB release** (while moving) | Resume moving the feature |
| **RMB** on globe | Select what is under the pointer and offer Duplicate and Delete |
| **Ctrl+LMB** | Geographic dragging (unchanged, does not start a move) |
| **MMB** (not moving) | Planet rotation (unchanged) |
| **Scroll wheel** | Zoom in/out (always available) |

### Behavior

- During a move the mouse cursor is hidden and the mouse is captured, so the cursor does not leave the window.
- Horizontal mouse movement changes longitude, vertical movement changes latitude.
- Holding the middle mouse button while moving temporarily switches to planet rotation. Releasing it resumes moving the feature. This allows repositioning the view without letting the feature go.
- Releasing the left mouse button ends the move, restores the cursor, and records an undo version.
- The keyframe at the current time is written as the drag goes, so what is on the globe during the drag is what the release records. Releasing off the globe puts the keyframe list back the way it was.

### Auto-select After Drawing

After committing a shape (pressing Enter in the Draw tool), the Move tool is automatically selected. This prevents accidentally drawing a second shape on the same feature.

## The Vertex tool

The Vertex tool edits the geometry of the selected feature on the globe itself,
rather than through the coordinate table of the [Properties](Properties.md)
panel. It is available once a leaf feature holding vertices of its own is
selected; there is nothing to take hold of otherwise, and a
[line topology](#line-topologies) borrows every vertex it draws from the
features its sections run along.

| Input | Action |
|-------|--------|
| **LMB press** on a vertex | Take hold of it and start dragging |
| **Mouse motion** (while dragging) | The vertex follows the cursor, snapping if snapping is on |
| **LMB release** | Drop it there — saves one undo version |
| **LMB click** on an edge | Put a new vertex on that edge, where the click fell |
| **Delete** | Take the vertex being held out |
| **S** | Split the feature at the vertex being held |
| **Shift+S** | Hold that vertex as one end of a polygon cut |
| **Escape** | Put a dragged vertex back and let go of it |
| **MMB drag** | Planet rotation, as everywhere |

A click that lands on neither a vertex nor an edge lets go of the one being
held. Picking works in **window pixels**, not in degrees, so a vertex is as easy
to hit whatever the view is zoomed to; the reach is
`Application.VERTEX_PICK_PIXELS`.

### Editing a feature that has moved

A feature keeps its vertices in its own frame, before the rotation its keyframes
and its groups' give it at the current time; see
[Time](Time.md#groups-carry-motion). The Vertex tool therefore maps every click
back into that frame, through the inverse of
`Feature.world_basis(root, feature, time)`.

That matters as soon as the current time is anywhere but where the feature was
drawn. An edit that skipped the mapping would look right on the globe and write
the wrong numbers into the file, so the scripted check in `run_vertex_session`
reads back the **stored** vertex and turns it through the feature's rotation
before comparing it with where the pointer was.

### Inserting on an edge

A click near an edge puts a new vertex at the point of that edge nearest the
click, rather than at the click itself, so the shape does not change until the
new vertex is dragged. The point is found in pixels, along the straight line
between the two vertices on screen, and then turned into a latitude and
longitude a fraction of the way along the great circle arc between them
(`Measure.along`). Over a long edge the straight line and the arc part company
slightly, which is why the new vertex can sit a fraction of a degree off the
edge it was asked for.

An edge with a vertex round the back of the globe is left alone: a screen
distance to something that cannot be seen means nothing.

### Deleting

Delete takes out the vertex being held. It is **refused** when the part would
fall under the minimum its kind needs — three for a polygon, two for a polyline,
one for a multipoint — and the status bar says so. On the globe the alternative
is a triangle disappearing under a single key press.

The Remove button of the Properties panel is the older behaviour and keeps it:
there a part that falls under its minimum is removed along with the vertex. The
two differ on purpose. The panel lists the parts, so one of them going is
visible in the table the click was made in; the globe shows no such list.

## Snapping

The **Snap** button in the toolbar decides whether a dragged vertex jumps onto a
nearby one when it is dropped. Every vertex of every feature the current time
shows is a candidate, not only those of the feature being edited, so two
features can be made to meet exactly. The vertex being dragged is left out of
the candidates; it is always nearest to itself.

The reach is `Application.SNAP_PIXELS` in window pixels, and the nearest
candidate inside it wins. The setting is remembered between runs.

## Splitting

A feature can be cut in two, leaving two features side by side in the tree.

- A **polyline** is cut at one vertex. Both halves keep that vertex, so between
  them they hold every original vertex once. An end vertex is refused: one half
  would be a single point.
- A **polygon** is cut between two vertices. Hold the first with **Shift+S**,
  then pick the second and press **S** or the Split button. Both halves keep
  both vertices.

The cut has to lie inside the shape. On a concave polygon a line between two
vertices can run outside it, across the mouth of a dent, or cross an edge on the
way; either would leave two rings that overlap instead of covering the original,
so the split is refused and the status bar says why.

Both halves carry the type, the colour, the time range and the keyframes of the
feature they came from, so the two go on moving together and go on existing over
the same span. The first keeps the title and every other part the feature had;
the second is named after it, `Laurentia` and `Laurentia 2`, and holds its half
alone.

## The Circle tool

A **small circle** is the path a point follows while a plate turns about a fixed
pole: every point of it the same angular distance from one centre. A great
circle is the case where that distance is 90 degrees.

The tool takes the circle from the points clicked on the globe, and how many
were clicked says which construction is meant:

| Points clicked | The circle |
|----------------|------------|
| 2 | Centre, then a point on the rim; the second click sets the angular radius |
| 3 | The circle those three points lie on, whose centre is never clicked |

There is no mode to pick. The preview shows what the clicks so far describe, so
a third click turns the one construction into the other in front of you, and a
fourth starts again.

| Input | Action |
|-------|--------|
| **LMB** on the globe | Add a point; the fourth starts a new circle |
| **RMB** | Take the last point back |
| **Enter** | Commit the circle to the selected feature |
| **Escape** | Start again with no points |

The status bar carries the centre, the radius in degrees and the segment count
while the tool is armed, so the circle can be read before it is committed.

### What it commits

The circle becomes a ring of the kind the geometry selector is on, cut into the
number of segments the Segments box holds:

- A **polygon** holds one vertex per segment and closes from the last back to
  the first.
- A **polyline** holds one vertex more, the first one repeated at the end, so
  it draws the whole circle rather than stopping a segment short.
- A **multipoint** is refused: a circle is a path, not a bag of markers.

The vertices are worked out in world coordinates and then mapped into the
feature's own frame, the same way the Draw tool does it, so a circle drawn while
the current time has moved the feature lands where it was clicked. Committing
records one undo version and goes back to the Move tool.

The construction itself is in `Logic/small_circle.gd` and is tested without a
window. How well three points settle a centre depends on how large the circle
is: a vertex is a pair of 32-bit floats and the centre comes out of differences
between three of them, so a circle a degree across lands its centre to about a
thousandth of a degree, and a larger one to much less.

## Line topologies

A **line topology** is a feature whose geometry is borrowed rather than drawn: a
list of **sections**, each naming another feature, a range of that feature's
vertices and which way round to walk them. A plate boundary is the usual one —
it runs along the edges of the plates on either side of it, so it should move
when they do rather than have to be redrawn.

Nothing about it is stored as vertices. Every time the tree or the current time
changes, `Logic/topology.gd` finds the features the sections name, takes the
runs of vertices they cover and carries them through the rotation those features
have then. What comes out is what is drawn, hit tested and measured, so from
there on a topology is a polyline like any other.

That is also why a topology has **no motion of its own** and no keyframe table
in the [Properties](Properties.md) panel: where it is comes from the features
under it.

### Building one

Select a feature holding nothing yet, pick the **Topology** tool, and click the
features the boundary runs along, in order:

| Input | Action |
|-------|--------|
| **LMB** on a feature | Add the part of it that was clicked as the next section |
| **RMB** | Take the last section back |

There is nothing to commit. Each click is one edit and one undo version, so the
boundary is on the globe as it grows, and the status bar counts the sections.

A click adds the **whole** of one part of the feature — the part holding the
vertex nearest the click, for a feature that has several. Trimming it to the
stretch that belongs to the boundary is done afterwards in the panel.

A click is refused, with the reason in the status bar, when the feature under it
is a group, is the topology itself, is another topology, or has no vertices. The
feature being built on is refused as well when it already holds vertices of its
own: a feature cannot both draw its geometry and borrow it.

### Editing the sections

The [Properties](Properties.md#the-section-table) panel shows the sections where
another feature shows its coordinates: the feature each one runs along, the two
vertices it runs between, and which way round. **Reverse** turns the selected
section round, which is what a boundary usually needs when the next feature's
vertices run back towards the last one, and **Remove** takes it out.

### Sections that cannot be followed

A section is never dropped. One whose feature has been deleted, or is not there
at the current time, is drawn in the panel in a warning colour with the reason
as its tooltip, contributes no vertices, and stays in the file. So deleting a
feature and undoing it mends the topology by itself.

That is what the persisted `uuid` is for. A section names its feature by an id
that survives a save and a load, and survives the tree being replaced by a clone
of itself — which is what undo, redo and every reload do; see
[Persistence](Persistence.md#feature-tree-serialization).

### The gap between two sections

Each section becomes a **part of its own**, so nothing is drawn between the end
of one and the start of the next. A line topology is the stretches it names, and
a segment across the gap is one no feature ever drew.

## The Measure tool

The Measure tool reports great circle distances in the status bar.

| Input | Action |
|-------|--------|
| **LMB** on the globe | Add a point to the path being measured |
| **RMB** | Take the last point back |
| **Escape** | Start again with no points |

With two or more points the status bar shows the last segment and the total
along the whole path. With none it says so. Outside the Measure tool the same
field shows the length along the selected feature's geometry: around the outline
of a polygon, along a polyline, and nothing for a multipoint, whose vertices are
separate markers rather than a path.

The points are drawn in the same yellow outline overlay the Draw tool uses, so
the path being measured is visible while it is read.

### The planet radius

Distances on a sphere are angles until a radius is put to them. The radius is a
**preference**, not part of a document: it says which planet the numbers are read
against, not anything about the features, so it neither dirties a document nor
needs a place in the file format. It defaults to Earth's mean radius, 6371 km,
the value the IUGG publishes.

The distance itself is worked out with the haversine formula rather than from
the dot product of the two points. The dot product of two nearly equal unit
vectors is 1 to within the rounding of the arithmetic, and taking its arc cosine
throws most of the digits away — and a short distance is what a measurement
usually is.

## Preferences

File > Preferences carries three settings that belong to the tools:

| Setting | What it does |
|---------|--------------|
| Planet radius (km) | What distances are read against, in whole kilometres |
| Vertex marker size | How large the outline overlay draws its vertex markers |
| Outline line width | How wide it draws the lines between them |

The two sizes are multiples of what `planet.gdshader` draws at, from
`Config.MIN_SCALE` to `Config.MAX_SCALE`. A multiple is easier to pick than the
chord length on a unit sphere the shader uniform is in; see
[Shader](Shader.md#outline-uniforms).

## Navigating the planet

Navigation works in every tool unless noted otherwise.

| Input | Action |
|-------|--------|
| **RMB** on the planet | The Edit commands for the feature under the pointer, in the Move tool only |
| **Ctrl+LMB drag** on the globe | Geographic dragging — turns the globe so the surface follows the cursor |
| **MMB drag** | Free rotation — captured mouse rotation of the globe |
| **Scroll wheel** | Zoom in and out |

The two drags turn the globe itself and do nothing on the map, where the
latitude and longitude fields of the view toolbar move the view instead.

## The view toolbar

The second row of the toolbar says what the planet is drawn as and where the
camera stands. Everything on it works on both views.

| Control | What it does |
|---------|--------------|
| Projection | The globe, or the map in one of five projections |
| Zoom out, zoom in | One step of the zoom, which is a factor of 1.2 |
| Zoom | The zoom as a percentage, 100% being the whole planet in view |
| Zoom reset | Back to 100% |
| Latitude, longitude | The place the view is centred on |
| Turn anticlockwise, turn clockwise | Fifteen degrees of the view's own rotation |
| Camera reset | The middle of the planet, the right way up |

### The projections

`Globe` is the sphere; the other five draw the planet flat, as
[MapProjection](../Logic/map_projection.gd) defines them and
[Shader](Shader.md#map-projections) describes the arithmetic.

| Projection | What it looks like | What it does not show |
|------------|--------------------|-----------------------|
| Rectangular | Latitude and longitude straight onto a two by one sheet | — |
| Mercator | A square sheet with the parallels pulled apart towards the poles | Above 85.05° either way, which runs off the sheet |
| Mollweide | An ellipse, equal area, the meridians curving to the poles | — |
| Robinson | The compromise outline, flattened poles, straight parallels | — |
| Orthographic | A disc: the planet as it is seen from far away | The far side |

Where a projection draws nothing — outside the Mollweide ellipse, the corners
of a Robinson sheet, the far side of an orthographic disc — the sky shows
through, and the pointer there reports itself off the planet.

### Where the camera looks

The latitude and longitude fields mean the same thing in every view, but each
view reaches them its own way:

- The **globe** turns to bring that point to the front.
- **Orthographic** centres its hemisphere on it, which comes to the same thing.
- The other four projections take the longitude as the **central meridian**,
  so the sheet is redrawn about it and nothing is ever cut in half at the edge
  of the view. The latitude slides the camera up the sheet, as far as the edge
  of it and no further: at 100% the whole sheet is on screen and there is
  nowhere to slide to, so the latitude only starts to bite once the view is
  zoomed in.

Turning the view rolls the camera, so it turns the map and the globe alike.
