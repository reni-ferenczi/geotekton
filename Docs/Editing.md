# Usage

## Tools

The toolbar contains ten mutually exclusive tool buttons, two switches and a
number:

- **Move** — Default. Enables globe rotation, dragging, and feature movement.
- **Rotate** — Turns the selected feature about its own middle; see
  [Turning a feature](#turning-a-feature). Needs a leaf feature holding vertices
  of its own, as the Vertex tool does.
- **Pole** — Turns the selected feature about a pole placed with a click; see
  [Turning a feature](#turning-a-feature).
- **Draw** — Enables drawing on the globe surface. See `Docs/Draw.md` for full details.
  Offered on a Polygon, a Line and Points.
- **Vertex** — Edits the vertices of the selected feature. Needs a leaf feature
  holding vertices of its own; see [The Vertex tool](#the-vertex-tool).
- **Measure** — Reports great circle distances in the status bar; see
  [The Measure tool](#the-measure-tool).
- **Circle** — Draws a circle from a centre or through three points; see
  [The Circle tool](#the-circle-tool). Offered on a Circle.
- **Topology** — Builds a line topology out of the features it runs along; see
  [Line topologies](#line-topologies). Offered on a Topology.
- **Light** — Drags the light around the globe; see
  [The Light tool](#the-light-tool). Offered on the globe alone.
- **Snap** — Whether a dragged vertex, or a pole being placed, jumps onto a
  nearby vertex. The Vertex and Pole tools use it; see [Snapping](#snapping).
- **Split** — Cuts the selected polygon in two along a line drawn across it;
  see [The Split tool](#the-split-tool). Offered while a polygon is selected.
- **Circle segments** — Shown only while the Circle tool is active; see
  [Segments of a circle](#segments-of-a-circle).
- **Outline** — Whether the Circle tool commits a polyline rather than a
  polygon. Shown beside the segment box, and remembered between sessions; see
  [What it commits](#what-it-commits).
- **Ridge** — Whether the Split tool leaves a line along the cut. Shown only
  while that tool is active, on to start with, and remembered between sessions;
  see [The ridge](#the-ridge).

Which of Draw, Circle and Topology is offered follows the selected feature's
[type](Properties.md#what-the-type-restricts), which is picked in the Properties
panel and is the one place it is picked. Picking a type on a feature holding
nothing arms the tool that draws it, so a new feature can be drawn straight
away.

Only one of Move, Rotate, Pole, Draw, Vertex, Measure, Circle, Topology, Light
and Split is active at a time. Everything but
Move takes the clicks on the planet for itself, so selecting a feature, moving
one and the right click menu wait until Move comes back. Rotating the globe with
the middle button always works.

### The tool keys

Each tool has a letter of its own, pressed without a modifier, which is what the
tooltip ends with. The letters are GPlates' where GPlates has one for the same
tool:

| Key | Tool     | Key | Tool     |
| --- | -------- | --- | -------- |
| M   | Move     | C   | Circle   |
| R   | Rotate   | T   | Topology |
| P   | Pole     | L   | Light    |
| D   | Draw     | X   | Split    |
| V   | Vertex   |     |          |
| E   | Measure  |     |          |

A key of a tool the toolbar greys out for what is selected does nothing. A text
field with the keyboard takes the letter as the character it is, so typing a
name never picks a tool; the same rule covers Space, which plays and pauses the
animation. See [Shell](Shell.md#menus). The Vertex tool's own **S** and
**Shift+S** are read while that tool is armed and are not tool keys.

Undo and redo leave the active tool alone: they put another version of the same
document in place, which is no reason to take a tool out of someone's hand mid
edit. File > New and File > Open do go back to Move, since whatever was half
drawn or half picked belonged to the document being left. Both also put the
time at the oldest age of the animation; see
[Time](Time.md#the-time-control).

## The feature tree

Each row of the tree carries the title of the feature or group and two buttons:
a colour swatch, on a feature only, and a switch that enables the node. A
disabled node is neither drawn nor hit tested, itself and everything under it.
The picture in front of the title is the [icon](Properties.md#the-icon) the
feature was given, greyed out while the feature is disabled; a feature with no
icon shows the plain row picture instead, and a group shows whether it is open.
A row is greyed out while its feature is outside its time range at the current
time, which is when the globe leaves it out as well; see
[Time](Time.md#being-there-at-all).
A left click on the swatch selects the feature and opens the colour picker of
the [Properties](Properties.md) panel, so the colour is picked where it is
shown; a right click puts the colour back to the one the feature's type gives.
Everything else about a feature is edited in the Properties panel.

The feature selected in the tree is highlighted on the planet in yellow:

- a **polygon** gets an outline along its rings;
- a **line** (a polyline, a topology, or a circle drawn as a line) is drawn
  thicker;
- a **multipoint** gets larger markers on its vertices.

A dot on every vertex appears only in the [Vertex tool](#the-vertex-tool),
where the vertices are there to be picked; there a line is traced at its own
width instead of thickened. The Circle, Measure and Light tools show their own
points in place of the highlight, and the Draw tool's preview of the shape
being drawn is drawn over it as before. See
[Shader](Shader.md#the-selected-feature).

Up to 0.1.0 the rows also had invert, single, wrap, resize and repeat, five
switches left over from the rule editor this interface came from. Nothing read
them and they were dropped in 0.2.0, files included.

## Moving Features

When the Move tool is active and a feature holding geometry is selected in the
feature tree, left-clicking on the globe starts moving it. A group cannot be
moved, since a group carries no motion. A move writes the keyframe at the current
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

## Turning a feature

The Move tool carries a feature along a great circle: the point that was grabbed
follows the pointer and the feature keeps facing the way it did. Turning one in
place is a different rotation, and two tools do it.

- The **Rotate** tool turns the selected feature about its own middle, the axis
  through the sum of its world vertices.
- The **Pole** tool turns it about a pole placed with a click, which is how a
  plate is turned about a rotation pole somewhere else on the planet.

Both need a leaf feature holding vertices of its own, so a group, a topology and
a feature holding nothing are refused the way the Move tool is disabled for
them. Both write the keyframe at the current time as the drag goes and record
one undo version on the release, exactly as a move does; a release off the
planet puts the keyframe list back. A feature that
[rides on another](Time.md#coupling) is turned in world space and its keyframe
is written in the frame in effect at the time. The status bar says how far the
drag has turned it.

| Input | Action |
|-------|--------|
| **LMB drag** on the planet | Turn the feature to follow the pointer |
| **LMB click** (Pole tool) | Place the pole to turn about |
| **Escape** (Pole tool) | Take the pole away |

The pole is drawn as a dot with a short cross through it, in the same yellow the
selection is traced in, and it stays while the Pole tool is armed, so several
features can be turned about one pole in turn. Picking another tool takes it
away. With [Snap](#snapping) on, a pole lands on the nearest vertex of any
feature instead of where it was clicked.

A drag whose pointer comes within about three degrees of the axis, or of the
point opposite it, is ignored: there is no direction about an axis from the axis
itself. It is the same refusal an antipodal drag of the Move tool meets.

The arithmetic is in [Moving](Moving.md#rotating).

## The Vertex tool

The Vertex tool edits the geometry of the selected feature on the globe itself.
The [Properties](Properties.md) panel lists no coordinates, so this is where a
vertex is moved, inserted or deleted. It is available once a leaf feature holding vertices of its own is
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
give it at the current time; see
[Time](Time.md#keyframes). The Vertex tool therefore maps every click
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

### Copying a shape

**Edit > Copy Shape** (`Ctrl+Shift+C`) takes the vertices of the selected
feature, every part of it, and holds on to them. **Edit > Paste Shape**
(`Ctrl+Shift+V`) adds them to whatever feature is selected then and arms the
Vertex tool on it, so the copy can be dragged into shape straight away. A paste
is one undo version.

The shape travels in world coordinates at the time it was copied and is put into
the frame the receiving feature has at the time it is pasted, so it lands where
it was seen whatever either of the two has been turned by; see
[Editing a feature that has moved](#editing-a-feature-that-has-moved).

A feature holding nothing takes the kind that came with the shape, and its type
follows the kind: a polygon pasted into a new feature makes it a Polygon. A
feature already holding another kind refuses it, with the reason in the status
bar, since the parts of one feature are all of one kind. Pasting into a feature
that holds the same kind appends another part, so the same shape can be laid
down twice and the second copy moved off the first.

A [line topology](#line-topologies) has no vertices of its own, but Copy Shape
takes what its sections resolve to at the current time, one run per section.
That is the way to turn a boundary into a polyline someone can edit.

The shape is held by the application rather than by the system clipboard, which
Copy and Paste use for whole features. Copying a shape therefore leaves the
clipboard alone, and a shape outlives the document it came from.

The feature tree selects one feature at a time. To gather the shapes of several
features into one, copy and paste them one after another: each paste appends a
part.

## Snapping

The **Snap** button in the toolbar decides whether a dragged vertex jumps onto a
nearby one when it is dropped, and whether the [Pole tool](#turning-a-feature)
puts its pole on one. Every vertex of every feature the current time
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
- A **polygon** is cut along a line, with the [Split tool](#the-split-tool).
  In the Vertex tool it can also be cut straight between two of its vertices:
  hold the first with **Shift+S**, then pick the second and press **S**. Both
  halves keep both vertices.

The cut has to lie inside the shape. On a concave polygon a line between two
vertices can run outside it, across the mouth of a dent, or cross an edge on the
way; either would leave two rings that overlap instead of covering the original,
so the split is refused and the status bar says why.

Both halves carry the type, the colour and opacity, the time range and the
keyframes of the feature they came from, so the two go on moving together and go
on existing over the same span. The first keeps the title and every other part
the feature had; the second is named after it, `Laurentia` and `Laurentia 2`,
and holds its half alone. A split is one undo version.

Both halves also keep the [couplings](Time.md#coupling) of the feature they came
from, so both go on riding on the same parent. A feature that rode on the one
that was split rides on the first half, which keeps the original's uuid.

## The Split tool

The Split tool cuts the selected polygon in two along a line drawn across it.
Click where the cut starts, any points it should bend through, and where it
ends. The line is drawn over the polygon's outline as it grows, like the shape
the Draw tool previews.

| Input | Action |
|-------|--------|
| **LMB** on the globe | Add the next point of the cut |
| **RMB** or **Ctrl+Z** | Take the last point back |
| **Ctrl+Y** | Put it back |
| **Enter** | Split the polygon along the cut |
| **Escape** | Start again with no points |

The ends do not have to be clicked on the edge. On Enter each end moves to the
nearest point of the polygon's boundary and becomes a new vertex there, or uses
the vertex that is already there, as a click just past a corner does. The
points between the ends go to both halves, so the two halves share the whole
cut. A feature of several polygons is cut in the part whose edge is nearest the
first point.

A cut is refused, with the reason in the status bar, when:

- both ends land on the same edge;
- it runs outside the polygon, as a straight cut across the mouth of a bay
  does;
- it crosses the polygon's edge anywhere between its ends, or crosses itself.

A refused cut keeps its points, so the one at fault can be taken back with
Ctrl+Z. A cut that is made records one undo version and goes back to the Move
tool, with the first half selected. The status bar names what the cut left
behind, `Split into Laurentia, Laurentia 2, Laurentia ridge`.

### The ridge

With the **Ridge** switch on, which is how it starts, the cut also leaves a
line where the two halves parted, the rift or mid ocean ridge that opens between
two continents as they drift apart. It is a Line feature named after the
polygon, `Laurentia ridge`, placed after the second half, holding the shared cut
as its one part: the two ends where they landed on the boundary and every point
clicked between them.

The ridge rides on both halves at once, over a span from the age the cut was
made at to the present, and its frame is theirs at one half. That is the half
stage rotation GPlates reconstructs a ridge by, so the line stays midway between
the two halves as they diverge and turns by half of whatever either one does.
See [Riding on two parents](Time.md#riding-on-two-parents). Both halves have the
polygon's own pose at the moment of the cut, so the ridge starts out lying
exactly on it. Its time range runs from that age to the present, since it did
not exist before the continent broke.

The ridge is part of the split's one undo version, so undo takes all three
features away together. Deleting a half afterwards leaves the span with a parent
that cannot be followed, drawn in the warning color like a missing parent
anywhere else, and undo mends it.

With the switch off the cut leaves the two halves and nothing else.

The cut between two vertices in the [Vertex tool](#the-vertex-tool) is the same
operation with no points between the ends, and `GeometryEdit` works both out
with the same functions.

## The Circle tool

A **circle** is every point the same angular distance from one centre, which is
also the path a point follows while a plate turns about a fixed pole. A great
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
| **RMB** or **Ctrl+Z** | Take the last point back |
| **Ctrl+Y** | Put it back |
| **Enter** | Commit the circle to the selected feature |
| **Escape** | Start again with no points |

The status bar carries the centre, the radius in degrees and the segment count
while the tool is armed, so the circle can be read before it is committed.

### Segments of a circle

A committed circle is not a true curve but a ring of straight edges. The
**Circle segments** box in the toolbar says how many: from 3 to 720,
starting at 36. Only this tool reads it, so the box is shown only while the
Circle tool is active. The preview and the status bar follow it as it changes.

The box and the Outline switch beside it fit in the toolbar's spare width, so
showing them does not push the Properties panel aside or move the planet. That
is why neither label is longer. The scripted session checks that the planet
stays put when the tool changes.

### What it commits

The circle becomes a ring cut into the number of segments the box holds. The
**Outline** switch beside the box says which kind of ring:

- With the switch off, a **polygon**, one vertex per segment, closing from the
  last back to the first.
- With it on, a **polyline**, one vertex more, the first one repeated at the
  end, so it draws the whole circle rather than stopping a segment short.

The switch is a preference rather than part of a document, so it is remembered
between sessions the way the snap switch is.

The vertices are worked out in world coordinates and then mapped into the
feature's own frame, the same way the Draw tool does it, so a circle drawn while
the current time has moved the feature lands where it was clicked. Committing
records one undo version and goes back to the Move tool. The tool is offered on
a [Circle](Properties.md#the-type-is-picked-before-the-shape) alone, which is
what a feature drawn with it already is.

The construction itself is in `Logic/circle.gd` and is tested without a
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

That is also why a topology has **no motion of its own** and no keyframe row
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
another feature shows its keyframe row: the feature each one runs along, the two
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

## The Light tool

Where the light comes from is a direction in the scene rather than a place on
the planet, so it is dragged on the globe: press anywhere on it and the light
shines straight at the point under the pointer, following it until the button is
let go. A yellow marker sits where the light stands, so the direction is visible
even where the shading is not.

The direction is fixed to the view, not to the planet, so turning the globe
carries the terminator across it rather than dragging the light along. A map
sheet is flat and has no point for the light to shine at, so the tool is offered
on the globe alone and gives way to Move when a map takes over.

The direction and the ambient level can also be typed on the
[View settings](#view-settings) dialog, which is what to reach for when the part
of the globe the light should come from is on the far side.

## The Measure tool

The Measure tool measures the great circle distance between two points.

| Input | Action |
|-------|--------|
| **LMB** on the globe | The first point, then the second; a third starts the next measurement from where it fell |
| **RMB** or **Ctrl+Z** | Take the last point back |
| **Ctrl+Y** | Put it back |
| **Escape** | Start again with no points |

A measurement is one segment: it is a measuring tool, not a drawing tool. With
two points the distance is written in the status bar and beside the line
itself, a little up and to the right of its midpoint, where it follows the
camera and hides while the midpoint is round the back of the globe or off the
map. With fewer than two the status bar says what to click. Outside the
Measure tool the same field shows the length along the selected feature's
geometry: around the outline of a polygon, along a polyline, and nothing for a
multipoint, whose vertices are separate markers rather than a path.

The two points and the line between them are drawn in the same yellow outline
overlay the Draw tool uses.

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

## View settings

**View > View Settings...** opens the scene around the features: what is behind
the planet, what is drawn over it, where the light comes from, the planet's
own color and which image it wears. Every field takes effect as
it is changed rather than when the dialog is closed, so the planet under it
shows what is being chosen.

| Setting | What it does |
|---------|--------------|
| Background | The colour behind the planet |
| Star field | Whether the stars are drawn; they add their light to the background colour, so the colour shows between them |
| Grid | The color of the longitude and latitude lines |
| Grid spacing | How far apart its lines are, from 1 to 90 degrees |
| Light elevation, light azimuth | Where the light comes from, away from the line of sight; `(0, 0)` shines from the camera |
| Ambient light | How much light reaches the night side; 0 is a black night, 1 no night at all |
| Planet color | The color of the planet where no raster covers it, ocean blue unless changed. The picker has no alpha, since the planet is never see-through |
| Raster shown, Raster opacity | Whether the image is drawn and how much of the planet color it covers |
| Raster | The image the planet wears, in PNG, JPEG, WebP or SVG. The field reads None when there is no image. **Browse...** picks a file, **Built in Earth** picks the Earth image that ships with Middle Earth, and **Clear** takes the image away |

A new document has no raster, so its planet is the flat planet color. A file
saved before 0.17.0 that named no image opens wearing the built in Earth, which
is how it looked then; see
[Persistence](Persistence.md#0160-to-0170).

The dialog does not set what color the features come out. That is set per
group, with the Style, Colour, Palette and Ramp rows of the
[Properties panel](Properties.md#the-properties-panel), which is also where a
`.cpt` palette file is loaded. The root group's style is pinned to each
feature's own color at full opacity, so a feature under no group of its own is
drawn in its own color.

Which classes of geometry are drawn at all is in the View menu itself, one check
item each for polygons, polylines, points, circles and topologies. See
[Styling](Styling.md) for what is in each class, what the group styles resolve
to and which part of the palette format is read.

The settings belong to the document and are saved with it, so a map of a world
keeps the way its author drew it, and every change to them is one step of the
undo stack; see [Persistence](Persistence.md#view-settings).

**Save as default** makes the block, and the view being shown, what File > New
starts from. **Restore defaults** puts the open document back to them. An
opened file always wins over the default: what the file says is what that
document looks like.

An image that cannot be read — moved, renamed, or in a format Middle Earth does
not read — is not an error the document has to be repaired from. The planet
shows its own color and the reason appears under the path.

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
| Zoom | The zoom as a percentage, 100% being the whole planet in view, which is also as far out as zooming goes |
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
