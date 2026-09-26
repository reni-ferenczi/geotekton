# Feature types and the Properties panel

## The type catalog

`Logic/feature_type.gd` holds the whole catalog as one constant dictionary.
Geotekton is a world building tool and does not carry the GPGIM over. The
catalog lists only what the program treats differently:

| Id              | Name          | Geometry kinds    | Default color  |
| --------------- | ------------- | ----------------- | -------------- |
| `polygon`       | Polygon       | polygon           | green, `Color(0.36, 0.60, 0.33)` |
| `line`          | Line          | polyline          | crimson        |
| `points`        | Points        | multipoint        | gold           |
| `circle`        | Circle        | polyline, polygon | dark turquoise |
| `topology`      | Topology      | topology          | medium purple  |
| `hotspot`       | Hotspot       | polyline          | orange red     |

The colors in the table are the ones the catalog comes with. The Feature colors
section of the [Preferences](Shell.md#preferences) dialog can put another color
in place of any of them, and `FeatureType.color()` answers with whichever is in
effect. That color is what a feature of the type starts in and goes back to
below, and what the [Feature type](Styling.md#the-draw-styles) draw style
paints.

Two more colors are kept the same way under ids that are not types, `crust` and
`crust_lines`: the steel blue a [crust](Editing.md#the-crust) starts in, which
is the old end of the ramp its bands are colored by, and the light steel blue of
its isochrons and flowlines. A crust is a Topology and takes the Topology color
under the Feature type style; these two are its own. The dialog offers a picker
per catalog type only, so either is changed by writing the `feature_colors` key
of the [config file](Persistence.md#the-config-file).

The first kind listed is the one the tools draw into an empty feature of the
type. The kinds are written as the names the file uses, so the catalog needs nothing
from `Feature` to be read and says the same words the `geometry_kind` field
does.

### The type is picked before the shape

A new feature is a Polygon. The Type selector of the Properties panel is the one
place the type is picked, and on a feature holding nothing it takes any of the
six, because the type is what the tools then draw: Polygon a polygon, Line a
polyline, Points a multipoint, Circle a closed polyline built from a center and
a radius, which [Draw draws as a circle](Editing.md#drawing-a-circle) and the
[circle rows](#the-circle-rows) set, and Topology a boundary picked
together with the [section table](#the-section-table)'s Pick toggle. A Hotspot is
placed by one click of Draw, which picking the type arms; see
[Hotspots](Editing.md#hotspots).

Once a feature holds a shape, its type has to hold that shape's kind. A polygon
is a Polygon or a Circle, a polyline a Line or a Circle, a multipoint Points and
a topology a Topology; anything else is refused. Circle and
Hotspot are picked on an empty feature only, since they replace whatever rings
the feature holds, and Hotspot only on one without keyframes or couplings. A
Circle can still become a Line or a Polygon, and keeps its rings. A type the feature carries
that does not hold its kind, or that the catalog does not know, gives way to the
kind's own, so a hand-written file cannot make a polyline a Polygon.

`Feature.feature_type` works this out every time it is read, through
`FeatureType.resolve()`. On a feature holding nothing the stored type is what
comes back, so a Line stays a Line until something is drawn into it, and so it
does through an undo that takes the geometry off again.

### What the type restricts

- **Which type can be picked.** Any of the six on a feature holding nothing;
  once it holds a shape, only one that holds that kind, and never Circle or
  Hotspot.
- **Which tool draws the feature.** Draw for a Polygon, a Line, Points and a
  Circle, which it draws from two or three clicks, and a Hotspot, which it
  places with one, and Topology for a Topology. The
  Vertex tool is greyed out on a Circle and a Hotspot. A hotspot
  greys out the Rotate and Pole tools as well, and the Move tool does not drag
  it. The other buttons are
  greyed out, and picking a type arms the tool it calls for; see
  [Tools](Editing.md#tools).
- **The color.** A new feature starts in the Polygon color, green unless
  the preferences say otherwise. A feature read from a file without a color
  gets the catalog's green too. Changing the type changes the color to the new
  type's color, but only while the color is still the one the old type gives.
  A feature keeps the color it holds when the preferences change. A color someone picked is never overwritten. Drawing
  the first shape leaves the color alone.
- **The class.** A Circle, axis circles included, is switched on and off with the circles in the View
  menu rather than with the polygons or the polylines; see
  [Styling](Styling.md#the-visibility-switches).

## The icon

A feature's tree row can carry one of eleven built in glyphs, so that a
mountain range and a continent are told apart at a glance. The Icon row of the
Properties panel lists them with their pictures, None first, and a feature
starts with none.

| Id              | Name          | What it shows                          |
| --------------- | ------------- | -------------------------------------- |
| `antarctica`    | Antarctica    | The continent, also the rule icon      |
| `africa`        | Africa        | The continent                          |
| `australia`     | Australia     | The continent                          |
| `eurasia`       | Eurasia       | The continent                          |
| `north_america` | North America | The continent                          |
| `mountain`      | Mountain      | Peaks, which is also an orogeny        |
| `volcano`       | Volcano       | A cone with a plume                    |
| `heart`         | Heart         | A heart                                |
| `moon`          | Moon          | A crescent                             |
| `shield`        | Shield        | A heraldic shield                      |
| `star`          | Star          | A star                                 |

`Logic/feature_icon.gd` holds the catalog. Nothing else in the program reads
the icon: it changes what the row shows and no more. A group's row says whether
the group is open, as before, and takes no icon of its own.

An icon is one of the Geotekton icons, a PNG under `Assets/Geotekton Icons`
at whatever size it was painted. It is shrunk to 32 by 32 pixels, the size of
the group and rule icons beside it, the first time it is asked for. To add or
replace one:

1. Drop the PNG into `Assets/Geotekton Icons`. The default import is the
   right one, and Godot imports the file on the next launch.
2. Name the id in `FeatureIcon.CATALOG`, with the name the Icon selector shows,
   and the file's stem against the id in `FeatureIcon.FILES`.

A file written by hand can name an icon this version does not know. Such a
feature keeps the name, shows the rule icon on its row, and the Icon row of the
panel stands empty until something is picked.

## The Properties panel

`Scenes/Application/properties.gd` builds the panel in code; the scene is the
`PanelContainer` it is attached to and nothing else. What the panel shows
follows the feature tree selection, through
`Application._on_feature_selected()`.

| Row        | Control            | On a group |
| ---------- | ------------------ | ---------- |
| Name       | Line edit          | yes        |
| Type       | Selector           | no         |
| Icon       | Selector           | no         |
| Style      | Selector           | only       |
| Colour     | Colour picker, opacity | yes    |
| Palette    | Selector           | only       |
| Ramp       | Colour pickers, +, −, span | only |
| Line width | Number             | no, features drawn with lines only |
| Enabled    | Switch             | yes        |
| From (Ma)  | Number             | no         |
| To (Ma)    | Number             | no         |
| Area       | Label              | no, polygons only |
| Axis circles | Checkbox         | no, Circle only |
| Axis latitude, Axis longitude | Number | no, Circle only |
| Radius (°) | Number             | no, Circle only |
| Segments   | Number             | no, Circle only |
| Pick axis  | Button             | no, Circle only |
| Plate      | Selector, pointer  | no, Hotspot only |
| Step (My)  | Number             | no, Hotspot and crust only |
| Keyframes  | Count, Key, Delete | no         |
| Coupled to | Parent, Decouple   | no         |
| Follow     | Picker, Couple, pointer | no    |
| Couplings  | List, Remove       | no         |
| Sections   | Table, Reverse, Remove, Pick | no |

The panel lists no coordinates. Geotekton is for building worlds, and a
vertex is placed, moved, inserted and deleted on the globe with the
[Draw](Draw.md) and [Vertex](Editing.md#the-vertex-tool) tools. Nor does it
count vertices or parts.

The Area row is there only for a feature drawn as a polygon: a polygon, a
closed topology and a crust, whose area is the sum of its bands. Lines,
markers, open topologies, a ridge, the crust's lines, groups and
features with no geometry yet do not have it. It has two lines, the area on the
first and the share of the planet it covers on the second:

```
1.23 million km²
0.2 % of planet
```

The share has one decimal and a no-break space before the percent sign, so the
line never breaks there. Below 0.05 % the second line is left out. The area is
read against the [planet radius](Editing.md#the-planet-radius) preference, so
the row changes when the Preferences dialog is closed with another radius.

A feature shows either the keyframe and coupling rows or the section table,
never both: a [topology](Editing.md#topologies) borrows its vertices
instead of holding them, and where it is comes from the features its sections
run along.

With nothing selected the panel says so and shows no rows at all, and so does
the root group, which has no name of its own to change and no switch, the same
as on its tree row. The root's sentence gives the planet's radius and surface
area instead. The root's style is pinned to each feature's own color and
is not edited anywhere; see [Styling](Styling.md#group-styles).

The panel keeps one width, `CONTENT_WIDTH`, whatever it is showing. Letting its
content set the width would let the split container hand the difference to the
planet view, so the globe would move under the pointer every time the selection
changed. `CONTENT_WIDTH` is 220 px, which is also as narrow as the panel can be
dragged. Every row fits in that: the selectors and the text fields shrink and
clip their text, the Enabled switch wraps its label, and the Keyframes, Follow
and Ramp rows move the buttons or the span box that no longer fit onto a line
of their own.

The button on the Colour row shows the colour and opens Godot's colour picker on
it, with the screen sampler, the hex field, the colour modes, the sliders and a
row of presets. A left click on the feature's [tree row
swatch](Editing.md#the-feature-tree) opens the same picker, so a colour can be
picked where it is shown while the panel stays the one place it is edited.
`Helpers.color_button()` builds every button that opens a picker, which is why
the ramp stops and the View settings dialog offer the same things.

The presets start as the default colour of each feature type, and every colour
committed to a feature or a group since the application started is added to
them, so a palette built for one feature is a click away on the next. Every
picker reads the same list, which lives for the session and is not written to
the settings file.

### The colour picker

The popup is Godot's own, and is held to the width its contents need. Godot
sizes it when the button is pressed, before the presets go in, and a popup
window that has once been made wider keeps that width, so `color_button()`
puts it back to the picker's minimum width after every opening and again
should anything widen it while it is open; the height is left alone, since it
grows when the swatches or the recent colours are unfolded. This answers a
report of the picker coming up stretched sideways, wider on each opening until
it nearly filled the window (GP-0112). The stretch was not reproduced on the
development machine, so the guard is a bound rather than a fix at the cause;
`run_color_picker_checks` in `Tests/session.py` opens the picker from the
button and from the swatch by turns with a full row of presets and checks
that the width is the same each time. The automation port reports the popup's
size as `color_picker_size` and the button's place as `color_button_rect`.

The box beside the color picker is the feature's opacity, from 0 to 100
percent. It is the alpha of the same color, so it is saved with the color and
undone with it, and the picker itself leaves the alpha alone. At 0 the planet
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

- **Style** is the mode: Same as parent, which colors the features the way
  the group above does, or one of the four draw styles, which decide for
  themselves. The row's tooltip says so; see
  [Styling](Styling.md#group-styles) for how the two differ under nested
  groups.
- **Colour** is the color the Single colour mode paints with, and the box beside
  it is the group's opacity, multiplied into every feature under the group.
- **Palette** is what the Feature age mode reads. It lists the built in palettes
  and the file the style names, if it names one, with Custom first. **Load...**
  beside it reads a GMT `.cpt` file and gives it to the group, which adds the
  file to the list; see [Styling](Styling.md#the-chooser).
- **Ramp** is the [custom ramp](Styling.md#the-custom-ramp): a color picker per
  stop, a **+** that adds another stop and a **−** on every one past the second,
  and the span between two of them in My. Only the Custom palette reads it.

Every row is shown whatever the mode, since the opacity applies in all of them
and a color or a palette picked ahead is kept for when the mode is switched.
Each change is one edit and one undo version, and dragging the picker previews
the color on the globe the way it does on a feature.

### The line width row

**Line width** is how wide the feature's lines are drawn, as a multiple of what
its type draws at: 1 is the width every feature had before there was a row,
which is what a feature read from a file without a width shows. The box runs
from 0.1 to 20 in steps of 0.05, and the row and its label carry the tooltip
"How wide the feature's lines are drawn, as a multiple of what its type draws
at". A new feature starts at the Default line width of the
[Preferences](Shell.md#preferences) dialog and keeps its own width from then
on, whatever the preference is later set to.

The row is there only for a feature drawn with lines: a Line, a Circle, a
Hotspot, whose mark and track both widen, an open Topology and a crust, whose
isochrons and flowlines widen while its bands do not. A Polygon is a fill and
Points are dots, so neither shows the row, and closing a topology takes it
away until the topology is opened again; `Feature.draws_lines()` says which is
which. A type's own thinness stays under the width, so a circle at 2 is drawn
as wide as a plain line at 1; see [Shader](Shader.md#shader-uniforms). The
halo of a selected line follows the width, as it is sized from the line. The
outline overlay is not touched: its lines follow the Outline line width
preference alone.

Every edit goes through `Document.set_line_width()`, which refuses a group, a
feature with no lines to widen and a width outside the range, and is one undo
version. The automation port's `set_property` drives the row as `line_width`,
and `get_properties` reports it under the same name while the row is shown,
with its tooltip under `tooltips`.

### The circle rows

A Circle shows no Area row, since it is an outline. In its place is the **Axis
circles** checkbox ("Draw the circle at both poles of an axis"), and under it
four rows and a button: the latitude and longitude of the axis, which is the
circle's center, in the feature's own frame; the radius in degrees, from just
above 0 to just under 180, or to 90 with the box ticked; and how many segments
the circle is cut into, 3 to 720. **Pick axis** arms a one click pick on the
planet. The rows keep the "Axis" captions whether the box is on or off: the
center of a circle is the point its axis comes out of. See
[Axis circles](Editing.md#axis-circles).

Every edit, the checkbox included, goes through `Document.set_circle()`,
rebuilds the rings and is one undo version. The automation port's
`set_property` drives the rows as `polar` (true or false), `axis` (a latitude
and longitude pair), `radius` and `circle_segments`, and `get_properties`
reports them under `circle`, with `pick_axis` saying whether the button can be
pressed.

### The hotspot rows

A hotspot shows two more rows under To (Ma) instead of the keyframe and
coupling rows: Plate, a selector and a pointer toggle, and
[Step (My)](#the-step-row). The Draw tool places the hotspot itself, so where
it is has no row; see [Hotspots](Editing.md#hotspots). The selector lists None
first and then, in tree order, every leaf feature holding vertices of its own.
The pointer, "Click a feature on the planet to burn through it", arms the same
one shot pick as the Follow row's pointer: the next click on the planet makes
the feature under it the plate, a click on something that cannot be the plate
says why and leaves the pick on, and Escape or selecting another feature ends
it. The plate can be picked before the hotspot is placed. Each change rebuilds
the rings and is one undo version. The automation port's `set_property` drives
the selector as `plate` (a title it shows, or `None`), and `get_properties`
reports the row under `hotspot`: the `position` (null until placed), the
`plate` and the `plates` offered, the number of track `samples` at the current
time and step, the `time_step` itself, whether the pointer can be pressed
(`pick`) and whether it is on (`picking`). The port's `properties` command
flips the pointer by its node name, `PickPlate`.

### The step row

**Step (My)** is how far apart in time the feature is sampled, and a hotspot
and a [crust](Editing.md#the-crust) are the two that are sampled: the track has
a vertex per step and the crust a band between each pair of steps. The box runs
from 0 to 1000 in whole millions of years. 0, which is what a feature starts
with, follows the timeline's [Skip](Time.md#the-time-control); the tooltip on
the row says so. Anything above 0 is the feature's own step and the Skip no
longer reaches it, so two hotspots in one document can be sampled differently
and a file draws the same wherever it is opened.

A hotspot's step goes through `Document.set_hotspot()` with its place and
plate, a crust's through `Document.set_crust_step()`. Either way the rings are
rebuilt and the edit is one undo version. A crust is generated rather than
drawn, but the step is a setting on it, so this is the one row of a crust that
can be edited. The automation port drives both as `set_property` field
`time_step`; `get_properties` reports a hotspot's under `hotspot.time_step`
and a crust's as `crust_step`, beside `crust_chunks`.

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

On a feature that [follows another](Time.md#coupling) at the current time,
`Key` records the pose relative to the parent, which is what holds it where it
stands.

### Coupling

Two rows and a list, all about which feature this one
[follows](Time.md#coupling). A Circle has none of them: it follows nothing and
carries nothing, so the panel hides the rows and keeps only the keyframe row,
and `get_properties` reports what the hidden rows hold under `coupling` with
`hidden: true`. A Hotspot has neither the coupling rows nor the keyframe row,
since it never moves, so there is no `coupling` in what the panel reports at
all.

- **Coupled to** names the parent in effect at the current time, or says
  `nothing`. `Decouple` beside it ends that span at the current time and is
  greyed out while the feature follows nothing.
- **Follow** is a picker of every feature this one could follow, in tree
  order: every leaf but itself, the topologies, the circles and the
  hotspots. `Couple` starts a span on the
  picked feature at the current time and is greyed out while the feature
  already follows something then. The pointer button beside them fills the
  picker from the planet instead of from the list: press it and the next left
  click on the globe or the map names whatever it lands on. The status bar says
  `Pick the feature to follow` while it is armed. A click on the ocean, on the
  feature itself, on a topology, on a circle or on a hotspot says so in the
  status bar and leaves the
  pointer armed, so only a click the picker can take ends it. So do Escape and
  pressing the button again. Nothing else moves: the selection, the current
  tool and the globe are where they were, and the picked parent is still
  coupled with `Couple`.
- **Couplings** lists every span: the parent, `From` and `To` in Ma. `Remove`
  takes the selected span away, or the last one when none is selected, and
  leaves every keyframe where it was on the globe.

To see the other side of a coupling, the children of the selected feature,
switch on View > Highlight children; see
[Highlighting children](Editing.md#highlighting-children).

A span that follows two features at once, which only a file can give, is named
in both rows the way `Laurentia and Laurentia 2, midway` does. The picker makes
single parent spans only; see
[Following two parents](Time.md#following-two-parents). The
[ridge](Editing.md#the-ridge) a split leaves is a topology, so it has no
coupling rows.

`Couple` and `Decouple` are a [cut in time](Time.md#a-coupling-edit-is-a-cut-in-time):
they change nothing older than the current time and drop the keyframes the span
covers younger than it, so the feature is rigid from there until it is moved
again. `Remove` is the exception and keeps them all.

A span whose parent cannot be followed, because it was deleted, is kept in the
list and drawn in the warning colour a broken section has, with the reason as
its tooltip. The Coupled to row takes the same colour while the time is inside
that span. Undo brings the parent back and the colour goes. A span naming a
circle or a hotspot is never marked this way, since a file holding one loses it
when it is opened; see [Persistence](Persistence.md#0250-to-0260).

A refused Couple, such as a parent that already follows this feature, shows
the reason in an error dialog and changes nothing. The rows follow the current
time, since the parent in effect changes with it.

### The section table

Only a [topology](Editing.md#topologies) has one, and a feature typed Topology
that holds no section yet shows it empty. Above it, the **Closed**
switch joins the sections into one filled ring; see
[Closed topologies](Editing.md#closed-topologies). Switching it is one undo
version, and a closed topology shows the Area row with the ring's area and
share of the planet, which follow the current time. Below the switch, one row per section: the feature it runs along,
the two vertices it runs between, counted from one, and `on` or `back` for which
way round it is walked.

`From` and `To` are editable, so a section added by clicking a whole feature can
be trimmed to the stretch that belongs to the boundary. This table is the only
place that can be done. `Reverse` turns the selected section round and `Remove`
takes it out; with no row picked both work on the last section.

**Pick**, the pointer beside them, is a toggle that arms the Topology tool for
the topology shown: each click on a feature on the planet adds the part of it
that was clicked as the next section, and a right click takes the last one back;
see [Building one](Editing.md#building-one). The toolbar has no button for that
tool, so the toggle is how it is reached. It stays pressed while the tool is
armed, and Escape, selecting another feature or picking another tool lets it go.

A section whose feature cannot be followed — deleted, or not there at the
current time — is shown in a warning colour with the reason as its tooltip,
rather than being dropped. The table is filled again whenever the current time
moves, since a section can be followed at one time and not at another.

A [midway topology](Editing.md#midway-topologies), such as a ridge, has no
Closed switch. A line above the table says `Midway between two sides`, and
Pick refuses a section once both sides are there. A [crust](Editing.md#the-crust) has neither the
switch nor the table, since it is built from its half and its ridge. The line
says which half it lies beside and how many bands it has at the current time and
step, as in `Crust of Laurentia, 4 chunks`. Above the form a crust has the
[Step (My)](#the-step-row) row, the one thing about it that is edited.
Neither a ridge nor a crust has a row in the feature tree, so the panel shows one
after it is clicked on the globe; see
[The feature tree](Editing.md#the-feature-tree).
`get_properties` reports the line as `topology_note` and, on a crust, the count
as `crust_chunks` and the step as `crust_step`.

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
| `set_icon`              | a group, and an icon the catalog does not have      |
| `set_time_range`        | a range that ends older than it starts             |
| `set_line_width`        | a group, a feature with no lines to widen, and a width outside 0.1 to 20 |
| `set_vertex`            | a part or vertex that is not there, a point off the planet |
| `insert_vertex`         | the same                                           |
| `remove_vertex`         | a part or vertex that is not there                 |
| `split_feature`         | a group, a topology, a part that is not there, a multipoint, and a cut that would leave half a shape or run outside it |
| `split_feature_along`   | anything but a polygon, a part that is not there, fewer than two points, both ends on one edge, and a cut that runs outside the shape or crosses an edge or itself |
| `set_keyframe`          | a group; the time it names replaces or is added    |
| `remove_keyframe`       | a group, and a keyframe that is not there          |
| `couple`                | a group or a topology on either side, the feature itself, a feature already following something at that time, a parent that follows the feature down any chain, and a parent not there over the whole span |
| `decouple`              | a feature following nothing at that time, and the present on a span that runs to it |
| `remove_coupling`       | a span that is not there                           |
| `add_section`           | a group, a feature holding vertices of its own, a crust, a midway topology that has both its sides, and a target that is a group, a topology that is not midway (any topology for a midway one), the topology itself or has no vertices |
| `remove_section`        | anything but a topology, and a section that is not there |
| `reverse_section`       | the same                                           |
| `set_section_range`     | the same, and a vertex number below one            |
| `set_topology_closed`   | anything but a topology, a midway topology and a crust |

A method that can refuse returns the message saying why and changes nothing;
the panel puts the widget back and shows the message in an error dialog.

The colour picker is the one exception to one edit, one version. While the
picker is open the feature takes every colour the cursor is dragged over, so the
globe shows what is being picked, but only the colour left when the picker
closes reaches the undo stack.

## Edit commands

The **Edit** menu in the menu bar holds Undo, Redo, Cut, Copy, Paste,
Duplicate and Delete with their shortcuts, so they work wherever the focus is.
A text field still keeps Ctrl+C and Ctrl+V for its own text, because a focused
control is offered a key before a menu accelerator is. The feature tree toolbar
repeats Undo, Redo and Duplicate as buttons; Cut, Copy and Paste are in the
menu alone.

**Copy Shape** (`Ctrl+Shift+C`) and **Paste Shape** (`Ctrl+Shift+V`) are on the
same menu, under a separator of their own. They carry the vertices of one
feature into another rather than the feature itself, and the paste leaves the
Vertex tool armed on what it added; see
[Editing](Editing.md#copying-a-shape).

A right click on the globe or the map selects whatever is under the pointer and
offers Duplicate and Delete on it. Only in the Move tool: in the Draw tool a
right click takes the last placed vertex back, and in the Measure tool it takes
back the last point measured to.

Undo and Redo have the same exception. While the Draw or Measure tool
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

From 0.29.0 a leaf also carries `line_width`, written only when it is not 1:

```json
"line_width": 2.0
```

A feature without the key is drawn at the width it always was; see
[Persistence](Persistence.md#feature-tree-serialization).
