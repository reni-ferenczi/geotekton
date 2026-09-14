# Feature types and the Properties panel

## The type catalog

`Logic/feature_type.gd` holds the whole catalog as one constant dictionary.
Middle Earth is a world building tool and does not carry the GPGIM over. The
catalog lists only what the program treats differently:

| Id         | Name     | Geometry kinds    | Default color  |
| ---------- | -------- | ----------------- | -------------- |
| `polygon`  | Polygon  | polygon           | chocolate      |
| `line`     | Line     | polyline          | crimson        |
| `points`   | Points   | multipoint        | gold           |
| `circle`   | Circle   | polygon, polyline | dark turquoise |
| `topology` | Topology | topology          | medium purple  |

The kinds are written as the names the file uses, so the catalog needs nothing
from `Feature` to be read and says the same words the `geometry_kind` field
does.

### The type is picked before the shape

A new feature is a Polygon. The Type selector of the Properties panel is the one
place the type is picked, and on a feature holding nothing it takes any of the
five, because the type is what the tools then draw: Polygon a polygon, Line a
polyline, Points a multipoint, Circle either of the first two through the
[Circle tool](Editing.md#the-circle-tool) and Topology a boundary built with the
[Topology tool](Editing.md#line-topologies).

Once a feature holds a shape, its type has to hold that shape's kind. A polygon
is a Polygon or a Circle, a polyline a Line or a Circle, a multipoint Points and
a line topology a Topology; anything else is refused. A type the feature carries
that does not hold its kind, or that the catalog does not know, gives way to the
kind's own, so a hand-written file cannot make a polyline a Polygon.

`Feature.feature_type` works this out every time it is read, through
`FeatureType.resolve()`. On a feature holding nothing the stored type is what
comes back, so a Line stays a Line until something is drawn into it, and so it
does through an undo that takes the geometry off again.

### What the type restricts

- **Which type can be picked.** Any of the five on a feature holding nothing;
  once it holds a shape, only one that holds that kind.
- **Which tool draws the feature.** Draw for a Polygon, a Line and Points,
  Circle for a Circle and Topology for a Topology. The other two buttons are
  greyed out, and picking a type arms the tool it calls for; see
  [Tools](Editing.md#tools).
- **The color.** A new feature starts in chocolate. Changing the type changes
  the color to the new type's default, but only while the color is still the
  one the old type gave. A color someone picked is never overwritten. Drawing
  the first shape leaves the color alone.
- **The class.** A Circle is switched on and off with the circles in the View
  menu rather than with the polygons or the polylines; see
  [Styling](Styling.md#the-visibility-switches).

## The Properties panel

`Scenes/Application/properties.gd` builds the panel in code; the scene is the
`PanelContainer` it is attached to and nothing else. What the panel shows
follows the feature tree selection, through
`Application._on_feature_selected()`.

| Row        | Control            | On a group |
| ---------- | ------------------ | ---------- |
| Name       | Line edit          | yes        |
| Type       | Selector           | no         |
| Style      | Selector           | only       |
| Colour     | Colour picker, opacity | yes    |
| Palette    | Selector           | only       |
| Ramp       | Two colour pickers, span | only |
| Enabled    | Switch             | yes        |
| From (Ma)  | Number             | no         |
| To (Ma)    | Number             | no         |
| Geometry   | Label              | no         |
| Keyframes  | Count, Key, Delete | no         |
| Coupled to | Parent, Decouple   | no         |
| Ride on    | Picker, Couple     | no         |
| Couplings  | List, Remove       | no         |
| Sections   | Table, Reverse, Remove | no     |

The panel lists no coordinates. Middle Earth is for building worlds, and a
vertex is placed, moved, inserted and deleted on the globe with the
[Draw](Draw.md) and [Vertex](Editing.md#the-vertex-tool) tools. The Geometry row
still says what the feature holds.

A feature shows either the keyframe and coupling rows or the section table,
never both: a [line topology](Editing.md#line-topologies) borrows its vertices
instead of holding them, and where it is comes from the features its sections
run along.

With nothing selected the panel says so and shows no rows at all, and so does
the root group, which has no name of its own to change and no switch — the same
as on its tree row. The root's style is the document default and is edited in
the View settings dialog.

The panel keeps one width, `CONTENT_WIDTH`, whatever it is showing. Letting its
content set the width would let the split container hand the difference to the
planet view, so the globe would move under the pointer every time the selection
changed.

The box beside the color picker is the feature's opacity, from 0 to 100
percent. It is the alpha of the same color, so it is saved with the color and
undone with it, and the picker itself leaves the alpha alone. At 0 the Earth
shows through the feature, which can still be selected by clicking where it is.
The other styles supply their own color, so the box shows on the globe while
the group deciding the feature's color is on Feature colour. The opacity of
every group above the feature is multiplied in whatever the style; see
[Styling](Styling.md#group-styles).

The time range is two ages in millions of years before the present, the same
axis the timeline slider runs on, read the way the work runs: `From` is the age
the feature appears at, the older end, and `To` the age it disappears at, 0 at
the present. Both boxes carry that as a tooltip, on the number and on its label.
A range whose `To` is older than its `From` is refused, with the reason in a
dialog. A feature outside its range at the current time is neither drawn nor hit
tested, and its tree row is greyed out. See
[Time](Time.md#being-there-at-all).

The file keeps the pair younger first, and so does `time_range` in what
`get_properties` answers with. The two boxes are `time_from` and `time_to`,
which is what `set_property` drives and what `get_properties` reports beside
the pair.

A group has no keyframe row, since a group carries no motion. It has its
[style](Styling.md#group-styles) instead: how the features under it are colored.

- **Style** is the mode: Inherit, which leaves the choice to the group above,
  or one of the four draw styles.
- **Colour** is the color the Single colour mode paints with, and the box beside
  it is the group's opacity, multiplied into every feature under the group.
- **Palette** is what the Feature age mode reads. It lists the built in palettes
  and the file the style names, if it names one, with Two colour ramp first.
- **Ramp** is the [two colour ramp](Styling.md#the-two-colour-ramp): the color
  at age zero, the color at the end of the span, and the span in My. Only the
  Two colour ramp palette reads it.

Every row is shown whatever the mode, since the opacity applies in all of them
and a color or a palette picked ahead is kept for when the mode is switched.
Each change is one edit and one undo version, and dragging the picker previews
the color on the globe the way it does on a feature.

### The keyframe row

One row: how many keyframes the feature has, and two buttons that work at the
current time.

- `Key` holds where the feature is now as a keyframe at the current time. The
  rotation it records is the one the keyframes around that time already give,
  so nothing on the globe moves. This is how a keyframe is made without
  dragging.
- `Delete` removes the keyframe at the current time. It is greyed out while the
  time is between keyframes. The timeline's keyframe marks and its `<<` and
  `>>` buttons land on a keyframe exactly; see
  [Time](Time.md#the-time-control).

The panel does not list the keyframes' times or angles. A keyframe is placed by
dragging with the Move tool.

On a feature that [rides on another](Time.md#coupling) at the current time,
`Key` records the pose relative to the parent, which is what holds it where it
stands.

### Coupling

Two rows and a list, all about which feature this one
[rides on](Time.md#coupling).

- **Coupled to** names the parent in effect at the current time, or says
  `nothing`. `Decouple` beside it ends that span at the current time and is
  greyed out while the feature rides on nothing.
- **Ride on** is a picker of every feature this one could ride on, in tree
  order: every leaf but itself and the topologies. `Couple` starts a span on the
  picked feature at the current time and is greyed out while the feature
  already rides on something then.
- **Couplings** lists every span: the parent, `From` and `To` in Ma. `Remove`
  takes the selected span away, or the last one when none is selected, and
  leaves every keyframe where it was on the globe.

`Couple` and `Decouple` are a [cut in time](Time.md#a-coupling-edit-is-a-cut-in-time):
they change nothing older than the current time and drop the keyframes the span
covers younger than it, so the feature is rigid from there until it is moved
again. `Remove` is the exception and keeps them all.

A span whose parent cannot be followed, because it was deleted, is kept in the
list and drawn in the warning colour a broken section has, with the reason as
its tooltip. The Coupled to row takes the same colour while the time is inside
that span. Undo brings the parent back and the colour goes.

A refused Couple, such as a parent that already rides on this feature, shows
the reason in an error dialog and changes nothing. The rows follow the current
time, since the parent in effect changes with it.

### The section table

Only a [line topology](Editing.md#line-topologies) has one. One row per section:
the feature it runs along, the two vertices it runs between, counted from one,
and `on` or `back` for which way round it is walked.

`From` and `To` are editable, so a section added by clicking a whole feature can
be trimmed to the stretch that belongs to the boundary. This table is the only
place that can be done. `Reverse` turns the selected section round and `Remove`
takes it out; with no row picked both work on the last section.

A section whose feature cannot be followed — deleted, or not there at the
current time — is shown in a warning colour with the reason as its tooltip,
rather than being dropped. The table is filled again whenever the current time
moves, since a section can be followed at one time and not at another.

### Every edit goes through the document

The panel never writes to a feature. Each edit calls one of the editing methods
of `Logic/document.gd`, which validates it, applies it and records exactly one
undo version:

| Method                  | Refuses                                            |
| ----------------------- | -------------------------------------------------- |
| `rename`                | nothing; a long title is cut down the way the tree cuts it |
| `set_enabled`           | nothing                                            |
| `set_color`             | nothing                                            |
| `set_style`             | a leaf, which has no style                         |
| `set_feature_type`      | an unknown type, and one that does not hold the kind the feature holds |
| `set_time_range`        | a range that ends older than it starts             |
| `set_vertex`            | a part or vertex that is not there, a point off the planet |
| `insert_vertex`         | the same                                           |
| `remove_vertex`         | a part or vertex that is not there                 |
| `split_feature`         | a group, a topology, a part that is not there, a multipoint, and a cut that would leave half a shape or run outside it |
| `split_feature_along`   | anything but a polygon, a part that is not there, fewer than two points, both ends on one edge, and a cut that runs outside the shape or crosses an edge or itself |
| `set_keyframe`          | a group; the time it names replaces or is added    |
| `remove_keyframe`       | a group, and a keyframe that is not there          |
| `couple`                | a group or a topology on either side, the feature itself, a feature already riding on something at that time, a parent that rides on the feature down any chain, and a parent not there over the whole span |
| `decouple`              | a feature riding on nothing at that time, and the present on a span that runs to it |
| `remove_coupling`       | a span that is not there                           |
| `add_section`           | a group, a feature holding vertices of its own, and a target that is a group, a topology, the topology itself or has no vertices |
| `remove_section`        | anything but a topology, and a section that is not there |
| `reverse_section`       | the same                                           |
| `set_section_range`     | the same, and a vertex number below one            |

A method that can refuse returns the message saying why and changes nothing;
the panel puts the widget back and shows the message in an error dialog.

The colour picker is the one exception to one edit, one version. While the
picker is open the feature takes every colour the cursor is dragged over, so the
globe shows what is being picked, but only the colour left when the picker
closes reaches the undo stack.

## Edit commands

The commands that were on the feature tree toolbar are also on an **Edit** menu
in the menu bar — Undo, Redo, Cut, Copy, Paste, Duplicate and Delete — with the
shortcuts the feature tree used to handle by itself. The menu owns them now, so
they work wherever the focus is, and a text field still keeps Ctrl+C and Ctrl+V
for its own text, because a focused control is offered a key before a menu
accelerator is.

A right click on the globe or the map selects whatever is under the pointer and
offers Duplicate and Delete on it. Only in the Move tool: in the Draw tool a
right click takes the last placed vertex back, and in the Measure tool it takes
back the last point measured to.

Undo and Redo have the same exception. While the Draw, Circle or Measure tool
holds points it has not committed, Ctrl+Z takes the last of them back and
Ctrl+Y puts it down again, and the document's stack is reached only once no
point is held; see [Draw](Draw.md#visual-feedback). The feature tree toolbar's
Undo and Redo buttons always go to the document.

## The file

A leaf feature carries `feature_type` in the file from 0.3.0 on:

```json
"feature_type": "circle"
```

A feature without the key, as in a 0.2.0 file, takes its type from its
geometry. A file written before 0.9.0 names one of the eight types the catalog
had then, which the migration maps onto the five; see
[Persistence](Persistence.md#080-to-090).
