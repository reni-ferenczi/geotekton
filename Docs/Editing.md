# Usage

## Tools

The toolbar contains seven mutually exclusive tool buttons, a few switches and
two numbers, each shown only while the tool that reads it is active:

- **Move** — Default. Enables globe rotation, dragging, and feature movement.
- **Rotate** — Turns the selected feature about its own middle; see
  [Turning a feature](#turning-a-feature). Needs a leaf feature holding vertices
  of its own, as the Vertex tool does.
- **Pole** — Turns the selected feature about a pole placed with a click; see
  [Turning a feature](#turning-a-feature).
- **Draw** — Enables drawing on the globe surface. See `Docs/Draw.md` for full details.
  Offered on a Polygon, a Line, Points, a Circle, where it draws a circle (see
  [Drawing a circle](#drawing-a-circle)), and a Hotspot, where one click places
  it (see [Hotspots](#hotspots)).
- **Vertex** — Edits the vertices of the selected feature. Needs a leaf feature
  holding vertices of its own; see [The Vertex tool](#the-vertex-tool).
- **Measure** — Reports great circle distances in the status bar; see
  [The Measure tool](#the-measure-tool).
- **Split** — Cuts the selected polygon in two along a line drawn across it;
  see [The Split tool](#the-split-tool). Offered while a polygon is selected.
- **Circle segments** — Shown only while the Draw tool is drawing a circle; see
  [Segments of a circle](#segments-of-a-circle).
- **Freehand** and **Tolerance** — Whether the Draw tool lays a line down under
  a dragged pointer instead of taking vertices click by click, and how closely
  the line follows the drag, in pixels. Shown only while the Draw tool draws a
  Line or a Polygon, off to start with, both remembered between sessions; see
  [Freehand](Draw.md#freehand).
- **Ridge** — Whether the Split tool leaves a ridge along the cut. Shown only
  while that tool is active, on to start with, and remembered between sessions;
  see [The ridge](#the-ridge).
- **Crust** — Whether the Split tool also leaves oceanic crust between the ridge
  and each half. Shown beside Ridge while the Split tool is active, greyed out
  while Ridge is off, on to start with, and remembered between sessions; see
  [The crust](#the-crust).

Whether Draw is offered, and whether it draws a circle, places a hotspot or
clicks a shape out vertex by vertex, follows the selected feature's
[type](Properties.md#what-the-type-restricts), which is picked in the Properties
panel and is the one place it is picked. Picking a type on a feature holding
nothing arms the tool that draws it, so a new feature can be drawn straight
away. A Topology is not drawn: its sections are picked with the **Pick** toggle
of the section table in the Properties panel, which arms the Topology tool
without a toolbar button; see [Topologies](#topologies). Whether a click or a
drag lands on a nearby vertex is a setting, Edit > Snap to vertices, rather
than a tool; see [Snapping](#snapping). The light is set in the
[View settings](#view-settings) dialog.

Only one of Move, Rotate, Pole, Draw, Vertex, Measure, Topology and Split is
active at a time. Everything but
Move takes the clicks on the planet for itself, so selecting a feature, moving
one and the right click menu wait until Move comes back. Rotating the globe with
the middle button always works.

### The tool keys

Each tool button has a letter of its own, pressed without a modifier. A
button's tooltip is the tool's name and that letter, such as "Rotate [R]". The
letters are GPlates' where GPlates has one for the same tool:

| Key | Tool              | Key | Tool              |
| --- | ----------------- | --- | ----------------- |
| M   | Move              | V   | Edit Vertices     |
| R   | Rotate            | E   | Measure Distances |
| P   | Pole Rotate       | X   | Split             |
| D   | Draw              |     |                   |

The Topology tool has no key, since it has no button. C, L and T pick nothing.

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

The [ridge](#the-ridge) and the [crusts](#the-crust) a split leaves have no
row. They are selected by clicking them on the globe, and then no row is
selected while the Properties panel, the highlight, the Edit menu and the keys
work on them as on any feature. Delete works on them, from the Edit menu, the
Delete key or the globe's right-click menu, and a deleted crust hands the
selection to its half and a deleted ridge to nothing. Cut, Copy, Duplicate and
Paste refuse them, since they are built from their halves. Deleting a half, or
a group holding one, deletes its crust, every ridge running along it and that
ridge's other crust with it, in the same undo step. `FeatureTree.sea_floor`
holds them by pnid and `selected_off_tree` the one selected, so
`get_selected_node()` and `select_node()` work for them as for a row.

Dragging a row moves the feature or group. Where it lands depends on the part
of the row the pointer is over when the button is released, and the tree marks
that part while the drag is on:

- the band at the top of a row: before that row, next to it in the same group;
- the band at the bottom of a row: after that row, next to it in the same group.
  This is the same for a feature, a collapsed group and an expanded group, so
  the band under a group's row is how an item leaves that group;
- the middle of a group's row: into that group, as its last item;
- the middle of a feature's row: after that feature;
- the empty space under the rows, or the Planet row: the end of the top level.

To put an item first in an open group, drop it on the band at the top of the
group's first row. A group cannot be dropped into itself or anything under it.
A move is one undo step.

The feature selected in the tree is highlighted on the planet in white:

- a **polygon** gets a translucent outline along its rings, with the fill and
  the grid showing through it, much as GPlates draws one;
- a **line** (a polyline, a topology, a circle or a hotspot track) keeps its
  own color and gets a white halo a quarter wider than itself, so a color
  picked for it shows while it is still selected. A hotspot track and a circle
  are drawn thinner than other lines, and so are their halos;
- a **multipoint** gets larger markers on its vertices.

A dot on every vertex appears only in the [Vertex tool](#the-vertex-tool),
where the vertices are there to be picked; there a line is traced at its own
width and has no halo. A circle being drawn and the Measure tool show
their own points in place of the highlight, and the Draw tool's preview of the shape
being drawn is drawn over it as before. See
[Shader](Shader.md#the-selected-feature).

### Highlighting children

View > Highlight children shows which features are
[coupled](Time.md#coupling) to the selected one. It is off by default, and the
choice is remembered like the panel switches. While it is on and a feature is
selected, every child it has at the current time is marked, and so are the
children of those in turn:

- on the planet, a child is traced in orange: a line or a multipoint is drawn
  orange at its normal width, and a polygon keeps its fill and gets an orange
  outline. The selection is white, so the two are not mixed up;
- in the tree, a child's row gets a faint orange background. The row is tinted
  even while the child is outside its time range, so the coupling shows when
  the planet leaves the child out.

The marks follow the current time, since a coupling holds over a span of it.
The planet and the tree always mark the same features, in every tool. A
selected group stands for the leaves under it: its children are the children
of those leaves, and the leaves themselves are left out, so selecting the root
marks nothing.

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
[follows another](Time.md#coupling) is turned in world space and its keyframe
is written in the frame in effect at the time. The status bar says how far the
drag has turned it.

| Input | Action |
|-------|--------|
| **LMB drag** on the planet | Turn the feature to follow the pointer |
| **LMB click** (Pole tool) | Place the pole to turn about |
| **Escape** (Pole tool) | Take the pole away |

The pole is drawn as a dot with a cross through it, in the same white the
selection is traced in. Each arm reaches three degrees from the pole and is
as wide as a feature line (`geometry_line_width`), which makes it wider than
an outline line; the Outline line width preference does not change
it. The pole stays while the
Pole tool is armed, so several features can be turned about one pole in turn.
Picking another tool takes it away. With [snapping](#snapping) on, a pole lands on
the nearest vertex of any feature instead of where it was clicked.

A drag whose pointer comes within about three degrees of the axis, or of the
point opposite it, is ignored: there is no direction about an axis from the axis
itself. It is the same refusal an antipodal drag of the Move tool meets.

The arithmetic is in [Moving](Moving.md#rotating).

## The Vertex tool

The Vertex tool edits the geometry of the selected feature on the globe itself.
The [Properties](Properties.md) panel lists no coordinates, so this is where a
vertex is moved, inserted or deleted. It is available once a leaf feature holding vertices of its own is
selected; there is nothing to take hold of otherwise, and a
[line topology](#topologies) borrows every vertex it draws from the
features its sections run along.

| Input | Action |
|-------|--------|
| **LMB press** on a vertex | Take hold of it and start dragging |
| **Mouse motion** (while dragging) | The vertex follows the cursor, snapping if snapping is on |
| **LMB release** | Drop it there — saves one undo version |
| **LMB click** on an edge | Put a new vertex on that edge, where the click fell |
| **Ctrl+LMB press** on a vertex | Take that vertex out, as Delete does, without dragging |
| **Delete** | Take the vertex being held out. While a vertex is held, this wins over **Edit > Delete**; with none held, Delete removes the feature as usual |
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
distance to something that cannot be seen means nothing. The other edges of
the same ring are offered as usual, so a polygon too wide to be on screen all
at once still takes a vertex on the edges that are. Until GP-0112 the whole
ring was left alone as soon as one vertex of it was hidden, which on a
continent sized polygon meant a click on a visible edge did nothing, with no
reason shown. A click within `VERTEX_PICK_PIXELS` of a vertex takes hold of
that vertex instead of inserting, so an edge shorter than twice that on
screen has no point that inserts; zoom in.

### Deleting

Delete takes out the vertex being held: the one under the pointer, or the one
last clicked when the pointer is on no vertex. Ctrl+LMB on a vertex does the
same to the vertex clicked; Ctrl+LMB on an edge or on empty planet does nothing.
Either one is a single undo version.

A part left with fewer vertices than its kind needs — three for a polygon, two
for a polyline, one for a multipoint — goes with the vertex: taking any
vertex out of a triangle removes the triangle, and the status bar says
`Removed a part of Laurentia`, or `Removed the last part of Laurentia` when
nothing is left. A polygon is never kept as a line or a point; its kind stays
what it was. This is the way to take one part out of a feature of several,
which Edit > Delete cannot do, since that removes the whole feature. A feature
whose last part went stays in the tree with no geometry, like a new one, so
the tool the type is drawn with is armed and it can be drawn again; Ctrl+Z
brings the part back. Deleting used to be refused at the minimum, so that a
key press could not make a triangle vanish; a single undo step is enough
protection, and the refusal left multi-part features uneditable (GP-0112).

**Edit > Delete** uses the same Delete key to remove the whole feature. While
the Vertex tool holds a vertex, the tool gets the key first and the feature
stays. With nothing held, the key goes to the menu and deletes the feature.

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

A [topology](#topologies) has no vertices of its own, but Copy Shape takes
what its sections resolve to at the current time: one run per section, a
polyline, or for a closed topology the one ring it is drawn as, a polygon.
That is the way to turn a boundary into a shape someone can edit.

The shape is held by the application rather than by the system clipboard, which
Copy and Paste use for whole features. Copying a shape therefore leaves the
clipboard alone, and a shape outlives the document it came from.

The feature tree selects one feature at a time. To gather the shapes of several
features into one, copy and paste them one after another: each paste appends a
part.

Paste Shape while the Draw tool is active works differently: the vertices of
every part of the shape are added, in order, to the points being drawn, and
nothing reaches the feature until Enter commits the drawing. A new feature arms
the Draw tool, so to paste straight into one, pick another tool first. The kind of the
drawing stays the one the feature's type gives, so a copied polygon can start
a polyline. Right click and Ctrl+Z take the pasted points back one at a time.
See [Draw](Draw.md#input-mapping).

## Snapping

**Edit > Snap to vertices** is a setting rather than a tool, so it is a check
item of the Edit menu and applies whichever tool is armed. It decides whether a
vertex dragged with the [Vertex tool](#the-vertex-tool) jumps onto a nearby one
when it is dropped, whether the [Pole tool](#turning-a-feature) puts its pole
on one, and whether the [Draw tool](Draw.md#input-mapping) places a point on
one. It is on to start with. Every vertex of every feature the current time
shows is a candidate, not only those of the feature being edited, so two
features can be made to meet exactly. The vertex being dragged is left out of
the candidates; it is always nearest to itself.

The reach is `Application.SNAP_PIXELS` in window pixels, and the nearest
candidate inside it wins. The setting is remembered between runs.

The [Draw tool](Draw.md#input-mapping) snaps too. A point clicked within reach
of a vertex of any shown feature is placed on that vertex, and the tool
remembers which feature, part and vertex it took. **Shift+LMB** on a second
vertex of the same ring then adds the vertices between the two, so a new
feature can follow the edge of an existing one exactly. A closed ring is
followed the way that passes fewer vertices; an open one has only one way.
Without a snapped point on that ring before it, Shift+LMB places one snapped
point, and with snapping off it is a plain click.

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
from, so both go on following the same parent. A child of the one that was
split follows the first half, which keeps the original's uuid, unless the
Split tool's [Children](#the-children) switch cuts it along.

## The Split tool

The Split tool cuts the selected polygon along a line drawn across it into two
features, the pieces on one side of the line and those on the other.
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

The ends do not have to be clicked on the edge. The polygon is cut wherever
the line runs inside it: each stretch from where the line crosses the outline
to where it crosses back cuts the piece it lies in, the crossing points
becoming new vertices and the points clicked in between going to both pieces.
What is clicked outside the polygon is dropped. An end stopped short inside
the outline is carried on, the way the line was going, to where it meets it.

A line that goes in and out, across both arms of a C or through a bay and out
of it, cuts several times and makes more than two pieces. They are sorted by
the side of the line they are on, in the direction it was drawn: the feature
keeps one side and `Laurentia 2` takes the other, each holding its side's
pieces as its parts. A line that goes in and out of the same edge takes a bite
out of it, which is a piece of its own. A feature of several polygons is cut
in every part the line crosses, and a part it misses goes to the side of the
line its middle is on; a line that crosses no part at all [divides](#dividing)
them instead.

A cut is refused, with the reason in the status bar, when it runs outside the
polygon altogether, crosses itself inside it, or crosses the coast an older
ridge lies along; see [Splitting a half again](#splitting-a-half-again).

A refused cut keeps its points and turns red on the globe until one of them
is taken back, another is added or Escape drops them, so the one at fault can
be taken back with Ctrl+Z.

The checks work on latitude and longitude as a flat plane. A polygon whose
stored vertices cross ±180° longitude or go round a pole, or a cut that crosses
±180°, is checked in a frame turned so the polygon's middle is at (0°, 0°)
instead, so a cut there splits like one anywhere else. The Vertex tool's split
and the cut through [children](#the-children) are checked the same way. A cut that is made records one undo version and goes back to the Move
tool, with the first half selected. The status bar names what the cut left
behind, `Split into Laurentia, Laurentia 2, Laurentia ridge, Laurentia crust,
Laurentia 2 crust`.

For a cut of one stretch each half's ring starts with the cut: its first
vertices are the two ends and the points between them, which is how the ridge
names that stretch. A cut of several stretches leaves no ridge and no crust
yet, and the status bar says so.

### The parent

A split feature that follows another, a continent following its craton, keeps
following it only on the craton's side. The half on the other side of the line
from the parent's middle stops following it at the age of the cut, standing
where it stood, so nothing moves; from then on it is a plate of its own and can
be given its own motion. Before that age it follows the parent as the whole
feature did. The status bar ends with `Laurentia 2 follows nothing from
100 Ma`. The parent itself is never cut.

### Dividing

A feature of several polygons can be split between its parts as well as
through one of them. A cut that touches no part — none of its points inside a
part, none of its stretches crossing a part's edge — divides the parts: each
goes to the side of the cut its middle lies on, the first part's side staying
with the feature and its title, and the parts on the other side going to the
second feature, `Laurentia 2`, as the second half of a cut would. The cut is
read as reaching on past both its ends, so it does not have to be drawn the
whole way past the outermost parts, and a bent cut sorts each part by the
stretch nearest to it. Which of the two Enter will do is in the status bar
while the points are being clicked: `Enter splits the polygon along them` or
`Enter divides the parts along them`.

A divide leaves no shared edge, so there is no ridge and no crust: the
**Ridge** and **Crust** switches are greyed out while the points would divide.
The **Children** switch works as for a cut, by the side each feature's middle
is on, and so does [the parent](#the-parent). A divide is refused when every part lands on one
side, `The cut leaves every part on one side`, and a cut beside a feature of
one part is refused as running outside the shape, as before. One undo version
either way. The sides are worked out in a frame turned to the parts when they
or the cut straddle ±180°. Implemented by `Document.divide_feature()` over
`GeometryEdit.touches()`, `sides()` and `far_parts()`.

### The ridge

With the **Ridge** switch on, which is how it starts, the cut also leaves the
rift or mid ocean ridge that opens between the two halves as they drift apart.
It is a [midway topology](#midway-topologies) named after the polygon,
`Laurentia ridge`, placed after the second half and drawn in the ridge color of
the [View settings](#view-settings), with no row in the feature tree; see [The feature tree](#the-feature-tree). Its two
sections are the two halves' sides of the cut: the first half's run from the
first vertex of its ring to the last point of the cut, and the same run on the
second half, walked back, because the second half holds the cut the other way
round. Its time range runs from the age of the cut to the present, since the
ridge did not exist before the continent broke.

Each vertex of the ridge is the pair of cut vertices taken back into their own
halves' frames and carried out by the rotation halfway between the two halves'
rotations. That is the half stage rotation GPlates reconstructs a ridge by, so
the line stays midway between the halves as they diverge and turns by half of
whatever either one does. Both halves have the polygon's own pose at the moment
of the cut, so the ridge starts out lying exactly on it. The ridge has no
keyframes and follows nothing; `Ridge.ring_at()` in `Logic/ridge.gd` works out
where it is at any age.

The ridge is part of the split's one undo version, so undo takes it away with
the halves. Deleting a half deletes the ridge and its crusts with it.

The ridge and the crusts are drawn under every other feature, crusts first and
the ridge over them, wherever they sit among the features, so a continent is
never hidden by the sea floor beside it. At the age of the split the ridge lies
under both halves and cannot be seen or clicked until they drift apart. The
group they sit in neither hides nor styles them: a crust shows while its half
does and the ridge while either half does, a half showing while it and every
group above it are enabled, and both are drawn in the colors of the View
settings. See `Planet._drawing_order()`. Splitting a half again
keeps the ridge on its cut; see [Splitting a half again](#splitting-a-half-again).

The **Ridges** switch in the View menu hides every ridge, and a hidden ridge
cannot be picked on the globe; see [Styling](Styling.md#the-visibility-switches).

With the switch off the cut leaves the two halves and nothing else, and the
Crust switch is greyed out.

### The crust

With **Crust** on as well, which is how it starts, the cut also leaves the sea
floor that opens between the ridge and each half, drawn the way GPlates shows
sea floor spreading: with isochrons and flowlines. New crust is next to the
ridge and older crust is next to the continent.

An **isochron** is a line of equal crust age: where the ridge was at that age,
carried along with the half since. The oldest one, at the age of the cut, is the
half's side of the cut, and the youngest, at the current time, is the ridge
itself. Between them there is one at every multiple of the crust's **Step
(My)**, the same setting a [hotspot](#hotspots) track is sampled at, and at
every multiple of the timeline's [Skip](Time.md#the-time-control) while the
step is 0. A **flowline** follows one vertex of the cut across every isochron,
from the continent to the ridge.

Each half gets one feature, `Laurentia crust`, placed after the ridge with the
ridge's time range. It holds the bands between two isochrons in a row, one
filled part each, with the oldest band against the continent, and it draws the
isochrons and a flowline for each vertex of the cut over them, as thin lines. So the order in the document is `Laurentia`,
`Laurentia 2`, `Laurentia ridge`, `Laurentia crust` and `Laurentia 2 crust`, and
the tree shows the first two.

Each band is filled by the age of the crust in it, the way an age grid reads in
GPlates. The age is the older of the band's two isochrons, counted from the
current time, so the crust beside the ridge is always the young color and a
band moves towards the old color as the time goes forward. The colors come from
the Sea floor section of the [View settings](#view-settings), one setting for
the whole document: Blue by default, light blue for the youngest crust to dark
ocean blue for the oldest, or Rainbow, or a custom ramp. Each is spread from
0 My to the oldest crust in the document at the current time, so the band
against the continent of the oldest split is the old end of the palette. No
group style reaches a crust, [Feature age](Styling.md#the-draw-styles)
included, and a crust has no Colour row in the Properties panel.

A feature is drawn in one color, so a crust carries a second one for its lines:
`Styling.line_color_of()` gives it the isochrons and flowlines color of the view
settings and everything else its own fill color, and the shader paints a
feature's segments and markers in that color and its filled triangles in the
first. The **Oceanic Crust** switch in the View menu
hides every crust, and **Isochrons and Flowlines** hides only their lines,
leaving the bands; a hidden crust cannot be picked on the globe. The bands themselves are drawn in as many colors as there are bands:
each band takes a column of its own in the [per feature
rows](Shader.md#per-feature-rotation) the shader already reads, so neither the
shader nor the geometry texture carries a color or an age per band. `Crust`
records the age of the crust in each band beside the rings and
`Styling.crust_color()` turns it into the color.

At the age of the cut there is only the one isochron, so the crust draws
nothing. As the time moves towards the present the halves drift and the bands
open, one more at each step. `Logic/crust.gd` rebuilds the crust after the
topologies whenever the tree, the time, the step or the Skip changes, and keeps
the bands in the feature's rings and the lines beside them, so only the bands
are filled and measured. A crust is a topology with no sections: the Properties
panel shows a line such as `Crust of Laurentia, 4 chunks` in place of the
section table, and the Area row is the sum of its bands. Copy Shape takes the
bands as a polygon of several parts. The crust is part of the split's one undo
version. A second split of its half keeps it on its coast; see [Splitting a half
again](#splitting-a-half-again).

The crust starts with a **Step (My)** of 0, which follows the timeline's Skip,
so the band count on a fresh split depends on how the Skip happens to be set.
Typing a step into the [Step row](Properties.md#the-step-row) pins the sampling
to the crust itself, where it is saved with the document. That is the one row
of a crust anyone edits; everything else about it comes from its half and its
ridge.

The cut between two vertices in the [Vertex tool](#the-vertex-tool) is the same
operation with no points between the ends, and `GeometryEdit` works both out
with the same functions.

### Splitting a half again

A ridge section names its side of the cut by part and vertex range, and a split
moves vertices around: its own cut goes to the front of each half's ring, the
parts are renumbered, and the piece holding an older cut may be the copy rather
than the original. So before a split changes any rings it notes the vertices
every topology section runs along, and afterwards it points each section at the
feature, part and range that now hold those same vertices, flipping the
direction when the run turned round. A crust whose half gave up the older cut
to the copy moves to the copy with it, so it goes on moving with the plate that
carries its coast, including after that piece goes free of its parent. The
older ridge and both of its crusts lie exactly where they did at every age.
The Vertex tool's split does the same, and it all belongs to the split's one
undo version.

A cut that crosses the coast an older ridge lies along would leave that coast
on two pieces, and a ridge section can only name one. The split tool refuses
such a cut and names the ridge in the status bar. A sibling the cut would cut
that way under [Children](#the-children) stays whole on its middle's side.
Splitting the older ridge there as well, a triple junction, is still to come.

### The children

With **Children** on, which is how it starts, the cut also goes through what
rides along with the feature: everything that follows its parent at the
current time, the orogeny across the craton as well as the continent around
it, or everything that follows the feature itself when it follows nothing, and
whatever follows those in turn, all the way down.

Each polygon and line the cut crosses is cut the same way as the feature: a
polygon into the pieces on either side, a line where the cut crosses it. The
feature keeps the pieces on the parent's side and a copy, `Orogeny 2`, is
placed right after it with the rest. What the cut misses goes whole to the side
of the cut its middle is on, and so does a polygon the cut would be refused on.
Circles, hotspots, ridges and crusts are left as they are, as is anything that
follows two parents.

Each piece then follows what stands in for its old parent on its own side:
the parent itself on the parent's side, and on the other side its piece there,
or for the craton the half that went free, or for something left whole on the
other side whatever stands in for its own parent. The span is cut at the age
of the cut and the older part still names the old parent, so no piece moves at
the cut, and as the halves drift apart each piece goes with its own side.

The pieces are part of the split's one undo version, and the status bar names
them after the halves, the ridge and the crust, as in
`Split into Laurentia, Laurentia 2, Range, Range 2` with Ridge off. The first feature of a
group is drawn on top of the ones after it, so a range meant to show over its
craton goes above it in the tree. Ridges and crusts are the exception: they are
drawn under everything; see [The ridge](#the-ridge).

With the switch off, nothing but the feature is cut and everything that follows
it goes on following the half that kept its title. The half away from the
parent still goes free. The Vertex tool's split has no such switch and leaves
everything alone.

## Drawing a circle

On a feature typed [Circle](Properties.md#the-type-is-picked-before-the-shape),
the Draw tool draws a circle instead of placing vertices one by one. The type
decides; there is no separate tool or key. Everything else about Draw, for
the other types, is in [Draw](Draw.md).

A **circle** is every point the same angular distance from one centre, which is
also the path a point follows while a plate turns about a fixed pole. A great
circle is the case where that distance is 90 degrees.

Draw takes the circle from the points clicked on the globe, and how many were
clicked says which construction is meant:

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

While a circle is being drawn, the status bar shows its centre, its radius in
degrees and the segment count, so the circle can be read before it is
committed. Snapping and Shift+click tracing do not apply to these points.

### Segments of a circle

The planet draws a circle as the curve it is, at every zoom, from its center
and radius; the preview while drawing is that curve too. A circle also keeps a
ring of straight edges, which is what measuring, Copy Shape, export, the
Python model and older readers use. A click picks the circle by the curve, as
it is drawn. The **Circle segments** box in the toolbar says how many edges
that ring has: from 3 to 720, starting at 36. It does not change how the circle
looks. Only a circle being drawn reads it, so the box is shown only while Draw
is armed on a Circle. The status bar follows it as it changes.

The box fits in the toolbar's spare width, so showing it does not push the
Properties panel aside or move the planet. That is why its label is not longer. The scripted session checks that the planet
stays put when the box appears.

### What it commits

A Circle keeps its **center**, its **radius** in degrees and its **segment
count**, and its ring is always rebuilt from those three by
`Feature.rebuild_circle()` with `Circle.vertices()`. Committing stores the
center and radius the clicks describe and the number the box holds. The ring is
an outline: a **polyline** with one vertex per segment plus the first one
repeated at the end, so the line goes all the way around. The planet draws the
curve rather than the ring (see [Shader](Shader.md#circles)), at half
the feature line width, as wide as the [Pole tool](#turning-a-feature)'s cross,
and the inside stays uncovered.

A Circle holds one circle. Drawing on a Circle that already has one replaces it,
and keeps the [Axis circles](#axis-circles) switch as it was. A filled circle
from a file written before circles were outlines stays filled when it is
redrawn.

The center is worked out in world coordinates and then mapped into the
feature's own frame, the same way the Draw tool maps vertices, so a circle drawn
while the current time has moved the feature lands where it was clicked.
Committing records one undo version and goes back to the Move tool. The feature
is a Circle before the first click and stays one.

Since the ring is derived, the Vertex tool is greyed out on a circle, Split is
not offered, and pasting a shape into one is refused. Move, Rotate and Pole
still turn it. Only an empty feature can be made a Circle; a Circle can be made
a Line (or a Polygon, if filled) again, and then keeps its ring as ordinary
vertices.

### Axis circles

The **Axis circles** checkbox in the [Properties panel](Properties.md#the-circle-rows)
draws the circle a second time around the antipode of its center, so the pair
sits at both ends of one axis. The first use is the auroral zones: the rows
start on the north pole with a radius of 23 degrees, where the auroral ovals
lie, 20 to 25 degrees from the geomagnetic poles. Earth's geomagnetic north pole
is near 80.7 N, 72.7 W, which can be typed in instead. GPlates has no paired
feature: its small circle tool makes one circle per radius around a clicked or
typed center.

The panel shows the checkbox and the rows under it for every circle, drawn or
not. Editing a row, or ticking the box, on a Circle with nothing drawn yet draws
the circle from the rows. Each edit rebuilds the rings as one undo version.
Axis circles take a radius of at most 90 degrees, where the two meet on the
great circle between the poles; a plain circle takes up to just under 180.

**Pick axis** in the panel arms the [Pole tool](#turning-a-feature) for one
click, with its cross on the current axis. The click, snapped to a vertex while
[snapping](#snapping) is on, becomes the new axis, and the tool goes back to Move. Escape or
another tool gives the pick up, and so does selecting another feature. The axis
is kept in the feature's own frame, so a click on a feature that keyframes have
turned is mapped back first, and the circle lands around the point clicked.

Keyframes move the feature like any other, both circles together. The file
keeps the rings as well as the parameters, so an older reader and the Python
side see polylines. When the file is loaded, the parameters win; see
[Persistence](Persistence.md#circles).

### A circle follows nothing

A circle takes no part in [coupling](Time.md#coupling). The Properties panel
shows no coupling rows for it, Couple is refused with "A circle follows
nothing.", and a circle is not offered as a feature to follow: the picker
leaves it out and a pick click on one says "A circle carries nothing." The
keyframe row stays, since Move and Rotate still turn a circle. A file written
before 0.26.0 could couple a circle; the spans are dropped when it is opened,
and the circle keeps everything else.

The construction itself is in `Logic/circle.gd` and is tested without a
window. How well three points settle a centre depends on how large the circle
is: a vertex is a pair of 32-bit floats and the centre comes out of differences
between three of them, so a circle a degree across lands its centre to about a
thousandth of a degree, and a larger one to much less.

## Hotspots

A **hotspot** is a plume fixed in the mantle. A plate drifting over it gets a
chain of volcanoes, the oldest farthest from the hotspot; Hawaii and the
Emperor seamounts are the textbook case. GPlates has a `HotSpot` point feature
and, separately, the motion path feature, and a hotspot track there is the
motion path of the plate point that sits over the hotspot today. Here both are
one feature of type Hotspot.

The hotspot sits still in the world frame, which is the mantle frame; see
[Time](Time.md#the-world-frame). The feature keeps two values: where the
hotspot is, as a latitude and longitude, and the plate it burns through, which
is any leaf feature holding vertices of its own. Its own time range says when
the hotspot is active, from the From age to the To age. A third value, the
**Step (My)**, says how far apart in time the track is sampled: 0, which is
what a new hotspot has, follows the timeline's
[Skip](Time.md#the-time-control), and anything above 0 is the hotspot's own
step, saved with the feature, so two hotspots in one document can be sampled
differently.

`Hotspot.rebuild()` in `Logic/hotspot.gd` gives the feature up to two
polylines:

- the **mark**, a closed ring one degree around the hotspot, cut into 24
  segments, so the hotspot shows whatever the plate does;
- the **track**, one vertex for every multiple of the step that is older than
  the current time and no older than the From age, oldest first, with the From
  age in front when it is not a multiple and the current time last. A 100 My
  range at a step of 30 is sampled at 100, 90, 60, 30 and 0 Ma when the current
  time is 0. A step below 0.1 My samples at 0.1 My. `Hotspot.step_of()` picks
  the step over the Skip and `Hotspot.sample_ages()` works the ages out. The vertex for age `t` is the plate
  point that was over the hotspot at `t`, carried with the plate to the current
  time: `B(T) * B(t)^T * H`, with `B` the plate's world rotation, `T` the
  current time and `H` the hotspot. Ages at which the plate does not exist are
  left out. With no plate, or fewer than two vertices, there is no track.

The oldest vertex is the farthest from the hotspot and the youngest is on it.
Both polylines are drawn at 0.35 of the feature line width, and every vertex
of the track gets a dot of its own in the feature's color, so the samples show
along the thin line.
The track depends on the plate, the time and the step, so it is rebuilt the
way a [topology](#topologies) is: before the geometry is collected, at every
time change and whenever the Skip box takes a new value. A new Skip redraws
every track still on a step of 0 and leaves the rest as they are.

Picking Hotspot in the Type selector of an empty feature arms the Draw tool
and draws nothing yet. The status bar says "Click to place <title>; click
again to move it". One left click puts the hotspot where it lands and, when
the click is on a feature that can be the plate, makes that feature the plate;
a click on nothing keeps the plate the hotspot had. Each click is one undo
version and the Draw tool stays armed, so the next click moves the hotspot.
Nothing is held, so there is no Enter to press, and the click does not snap to
vertices. Escape or another tool leaves Draw, and the Draw button arms it
again on a hotspot that is already placed.

A feature that holds a shape, or has keyframes or couplings, cannot become a
hotspot. A hotspot never moves on its own: the keyframe and coupling rows are
hidden, a Move drag does nothing, and the Vertex, Rotate and Pole tools are
greyed out. Pasting a shape into it and the Python bridge's ring edit are
refused.

Like a circle, a hotspot takes no part in [coupling](Time.md#coupling) either.
Couple is refused with "A hotspot follows its plate.", the picker does not offer
a hotspot as a feature to follow, and a pick click on one says "A hotspot
carries nothing." A file written before 0.26.0 could hold such a span; those are
dropped when it is opened.

The [Properties panel](Properties.md#the-hotspot-rows) picks the plate and
takes the step, one undo version each time. The plate comes from its selector
or from its pointer, the way the Follow row picks a parent. The plate is not a parent the hotspot follows: the
hotspot stays where it is in the mantle, and the track is the plate's motion
over it.

The file keeps the rings as well as the place, the plate and the step, so an
older reader and the Python side see two polylines. On load the values win and the
track is rebuilt; see [Persistence](Persistence.md#hotspots).

## Topologies

A **topology** is a feature whose geometry is borrowed rather than drawn: a
list of **sections**, each naming another feature, a range of that feature's
vertices and which way round to walk them. A plate boundary is the usual one —
it runs along the edges of the plates on either side of it, so it should move
when they do rather than have to be redrawn.

Nothing about it is stored as vertices. Every time the tree or the current time
changes, `Logic/topology.gd` finds the features the sections name, takes the
runs of vertices they cover and carries them through the rotation those features
have then. What comes out is what is drawn, hit tested and measured, so from
there on a topology is a polyline like any other, or a polygon when it is
[closed](#closed-topologies).

That is also why a topology has **no motion of its own** and no keyframe row
in the [Properties](Properties.md) panel: where it is comes from the features
under it.

### Building one

Select a feature typed Topology that holds nothing yet, press the **Pick**
toggle (the pointer under the section table in the
[Properties](Properties.md#the-section-table) panel), and click the features the
boundary runs along, in order. The toggle arms the Topology tool, which has no
toolbar button and no key. It stays armed for more clicks; Escape, selecting
another feature or picking a tool lets it go.

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
is a group, is the topology itself, is a topology that is not
[midway](#midway-topologies), or has no vertices. The feature being built on is
refused as well when it already holds vertices of its own, since a feature
cannot both draw its geometry and borrow it, when it is a midway topology that
has its two sections, and when it is a [crust](#the-crust).

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
feature and undoing it mends the topology by itself. A ridge is the exception:
it is deleted with either of its halves; see [The feature tree](#the-feature-tree).

That is what the persisted `uuid` is for. A section names its feature by an id
that survives a save and a load, and survives the tree being replaced by a clone
of itself — which is what undo, redo and every reload do; see
[Persistence](Persistence.md#feature-tree-serialization).

### The gap between two sections

Each section of an open topology becomes a **part of its own**, so nothing is
drawn between the end of one and the start of the next. An open topology is the
stretches it names, and a segment across the gap is one no feature ever drew.

### Closed topologies

The **Closed** switch in the [Properties](Properties.md#the-section-table)
panel joins the sections into one ring, which is drawn, filled, hit tested and
measured as a polygon, with its area in the Area row. Turning it on or off
is one undo version.

The runs go in section order, each one walked the way its section says. Where
the end of one run is the start of the next, that vertex is kept once, and
where the last run ends on the first one's start, the ring closes there. Where
two runs do not meet, the ring goes straight on to the next run, so the gap is
closed by a chord. Nothing is intersected or trimmed at crossings: each run is
the vertex range its section names. A broken section adds nothing to the ring
and stays reported in the section table.

A ring whose vertices all lie on one line encloses nothing and draws nothing.

### Midway topologies

A **midway** topology has exactly two sections of the same length and is the
line between them, vertex by vertex: each pair of vertices is taken back into
its own feature's frame and carried out by the rotation halfway between the two
features' rotations. For two features that have not moved apart, that is the
point halfway between the pair. The [ridge](#the-ridge) the Split tool leaves is
one, and the file marks it with `midway`.

A midway topology is drawn as one line. It has no Closed switch; the panel says
`Midway between two sections` above the section table instead. When the two
sections have different vertex counts, or one of them is broken, it draws
nothing and the section table says why. The Pick toggle refuses a third section.

A section of any other topology may run along a midway one, reading the line it
was last rebuilt into. Midway topologies are rebuilt before the others, wherever
they sit in the tree. A midway topology cannot run along another topology, and
no topology can run along one that is not midway.

## The light

The light is set in the [View settings](#view-settings) dialog: its elevation
and azimuth, and the ambient level. There is no tool for it.

## The Measure tool

The Measure tool measures the distance along a path of clicked points.

| Input | Action |
|-------|--------|
| **LMB** on the globe | Add a point to the path |
| **Enter** | Finish the path; the next click starts a new one |
| **RMB** or **Ctrl+Z** | Take the last point back |
| **Ctrl+Y** | Put it back |
| **Escape** | Start again with no points |

It is a measuring tool, not a drawing tool: nothing it holds reaches the
document, whatever the path is made of. A path takes any number of points.
With two or more the total is written in the status bar, and from the third
point on the last segment follows it, as in "2224.0 km, last
1112.0 km". The label beside the line shows the total, at the midpoint of the
last segment, so it stays near where the pointer is working; it follows the
camera and hides while that midpoint is round the back of the globe or off the
map. With one point the status bar says what to click next.

Enter finishes a measurement: the path and its numbers stay where they are,
and the next left click throws the path away and starts a new one from where
it fell. Escape clears the path at once.

Outside the Measure tool the same status field shows the length along the
selected feature's geometry: around the outline of a polygon, along a
polyline, and nothing for a multipoint, whose vertices are separate markers
rather than a path. A polygon also gets its area, as in "4430.9 km around
Laurentia, 1.23 million km²". The Area row of the
[Properties panel](Properties.md) shows the same area.

The clicked points and the line along them are drawn in the same white outline
overlay the Draw tool uses.

### Along a parallel

A **Parallel** switch sits in the tool strip beside the Split tool's switches
and is shown for the Measure tool alone. It starts off and goes back off
whenever the tool is left.

With the switch on, a click lands at the latitude of the previous point and
the longitude it was clicked at, and the segment it closes is measured and
drawn along that parallel, the shorter way round in longitude. The first point
of a path is placed where it was clicked whatever the switch says, since there
is no parallel to follow yet. Flipping the switch between clicks mixes the two
kinds of segment in one path.

A run along the parallel at latitude φ, over Δλ of longitude, is
`radius · cos φ · Δλ` with Δλ in radians: the parallel is a circle of radius
`radius · cos φ` rather than a great circle. The great circle between the same
two points is always the shorter of the two, because it bows towards the pole
instead of holding the latitude. At 60° N over 90° of longitude the parallel
runs 5004 km and the great circle 4605 km. Which number is wanted depends on
the question: a ship holding a due east course sails the parallel, while the
shortest way between the same two places is the great circle.

A parallel segment reaches the planet as a run of points sampled every degree
of longitude, drawn in the
[`OPEN_LINE`](Shader.md#outline-data-texture-layout) style, which marks no
vertex. The clicked points are drawn as markers over it, so the path shows
where it was clicked and not where it was sampled.

### The planet radius

Distances on a sphere are angles until a radius is put to them. The radius is a
**preference**, not part of a document: it says which planet the numbers are read
against, not anything about the features, so it neither dirties a document nor
needs a place in the file format. It defaults to Earth's mean radius, 6371 km,
the value the IUGG publishes.

The distance itself is worked out with the haversine formula rather than from
the dot product of the two points. The dot product of two nearly equal unit
vectors is 1 to within the rounding of the arithmetic, and taking its arc cosine
throws most of the digits away, and a short distance is what a measurement
usually is.

The Preferences dialog shows the planet's surface under the radius box and
updates it as the box changes. The root group's sentence in the Properties
panel gives the radius and the surface too: "The planet's radius is 6371 km
and its surface 510.06 million km²."

An area is spherical (`Measure.ring_area`). The ring is cut into a fan of
triangles from its first vertex, and the signed excess of each triangle is
added up, so a ring around a pole or across the date line needs no special
case. A ring splits the sphere into two sides, and the area is the smaller
one, which is also why the drawing direction makes no difference. The parts of
a polygon are separate outlines, so their areas add. An area under a thousand
square kilometers is written with one decimal, then in whole square kilometers
with a narrow no-break space between the thousands, and from a million on in
millions with two decimals.

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
| Grid spacing | How far apart its lines are, from 1 to 90 degrees. A line falls on every multiple of the spacing, counted from the equator and the prime meridian |
| Light elevation, light azimuth | Where the light comes from, away from the line of sight; `(0, 0)` shines from the camera |
| Ambient light | How much light reaches the night side; 0 is a black night, 1 no night at all |
| Planet color | The color of the planet where no raster covers it, ocean blue unless changed. The picker has no alpha, since the planet is never see-through |
| Raster shown, Raster opacity | Whether the image is drawn and how much of the planet color it covers |
| Raster | The image the planet wears, in PNG, JPEG, WebP or SVG. The field reads None when there is no image. **Browse...** picks a file, **Built in Earth** picks the Earth image that ships with Geotekton, and **Clear** takes the image away |
| Sea floor: Ridge | The color every [ridge](#the-ridge) is drawn in. A new document takes the Line color of the Feature colors in [Preferences](Shell.md#preferences) |
| Sea floor: Crust | What the [crust](#the-crust) is colored from by its age: **Blue** (the default), **Rainbow** or **Custom ramp**, which shows the ramp's colors below it, youngest first, with + and − to add and take away colors. Every choice is spread from 0 My to the oldest crust in the document |
| Sea floor: Isochrons and flowlines | The color of the lines drawn over every crust |

A new document has no raster, so its planet is the flat planet color. A file
saved before 0.17.0 that named no image opens wearing the built in Earth, which
is how it looked then; see
[Persistence](Persistence.md#0160-to-0170).

Apart from the sea floor, the dialog does not set what color the features come
out. That is set per group, with the Style, Colour, Palette and Ramp rows of the
[Properties panel](Properties.md#the-properties-panel), which is also where a
`.cpt` palette file is loaded. The root group's style is pinned to each
feature's own color at full opacity, so a feature under no group of its own is
drawn in its own color.

Which classes of geometry are drawn at all is in the View menu itself, one check
item each for polygons, polylines, points, circles, ridges and oceanic crust,
and one more for the isochrons and flowlines drawn over the crust. See
[Styling](Styling.md) for what is in each class, what the group styles resolve
to and which part of the palette format is read.

The settings belong to the document and are saved with it, so a map of a world
keeps the way its author drew it, and every change to them is one step of the
undo stack; see [Persistence](Persistence.md#view-settings).

**Save as default** makes the block, and the view being shown, what File > New
starts from. **Restore defaults** puts the open document back to them. An
opened file always wins over the default: what the file says is what that
document looks like.

An image that cannot be read — moved, renamed, or in a format Geotekton does
not read — is not an error the document has to be repaired from. The planet
shows its own color and the reason appears under the path.

## Preferences

File > Preferences carries three settings that belong to the tools:

| Setting | What it does |
|---------|--------------|
| Planet radius (km) | What distances and areas are read against, in whole kilometers, with the surface area it gives shown under it |
| Vertex marker size | How large the outline overlay draws its vertex markers |
| Outline line width | How wide it draws the lines between them |

The two sizes are multiples of what `planet.gdshader` draws at, from
`Config.MIN_SCALE` to `Config.MAX_SCALE`, 0.25 to 8. Since 0.29.0 a marker at 1
is half the size it was before, and a size saved by an older version reads as
twice what it said, so the markers look as they did. A multiple is easier to pick than the
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
