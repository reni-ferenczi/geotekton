# The document, files and settings

## The document

`Logic/document.gd` owns everything about the open document: the feature tree,
the file it came from and the undo stack. `Application` creates one and hands it
to the `Features` panel, which edits that tree instead of holding one of its own.

Three signals tell the rest of the window what happened:

| Signal          | Emitted when                                    |
| --------------- | ----------------------------------------------- |
| `root_replaced` | The tree was rebuilt: by New, Open, undo or redo |
| `state_changed` | The path, the dirty flag or the undo depth moved |
| `time_changed`  | The current time moved                           |

The document also owns the current time, which is not part of what it holds:
moving it records no undo version and dirties nothing, and a file opens at the
present whatever time was being looked at before. See [Time](Time.md).

### Unsaved changes

The undo stack is the source of the dirty flag for everything in the tree. Every
edit calls `Document.record()`, which stores a clone of the tree; the document
remembers which of those versions is on disk and is clean exactly while the
stack sits on it. The one thing outside the stack is the
[view settings](#view-settings) block, which dirties the document through
`Document.view_edited()` and is cleared by a save like the rest. So undoing back to the last save makes the document clean again, and redoing
past it makes it dirty again. The stack keeps at most `MAX_UNDO_STEPS` (100)
versions; once the saved version falls off the bottom the document stays dirty,
because it can no longer be shown that the tree matches the file.

New, Open, a recent file and Quit ask before throwing unsaved changes away. The
prompt offers Save, Discard and Cancel: Save writes the file and then goes ahead
with what was asked for, Discard goes ahead without writing, Cancel does
nothing. When the document has no path yet, Save asks for one first.

### New, Open, Save and Save As

| Command | What it does                                                     |
| ------- | ---------------------------------------------------------------- |
| New     | Empty document, no path, empty undo stack                        |
| Open    | Ask for a file and load it, replacing the tree and the undo stack |
| Save    | Write to the document path; ask for one only when it has none    |
| Save As | Always ask for a path, appending `.middle-earth` when it is missing |

There is no autosave: a document reaches the disk only when one of these
commands writes it.

The file dialogs are the ones the platform provides
(`DisplayServer.file_dialog_show`), so nothing happens when one is cancelled.
Scripted runs answer them through `Application.file_dialog_hook` instead of
opening a window; see [Testing](Testing.md#the-automation-port).

## File format

- **Extension**: `.middle-earth` (used for all versions)
- **Encoding**: UTF-8 without BOM
- **Format**: Uncompressed JSON, tab-indented for readability

### Structure

The file is a JSON object with four top-level keys:

```json
{
  "application": "middle-earth",
  "version": "0.26.0",
  "features": { ... },
  "view": { ... }
}
```

| Key           | Description                                                        |
|---------------|--------------------------------------------------------------------|
| `application` | Always `"middle-earth"`. Used to validate the file on load.        |
| `version`     | The application version that produced this file.                   |
| `features`    | The root group of the feature tree, serialized via `to_json()`.    |
| `view`        | How the scene around the features is drawn. See [View settings](#view-settings). |

### View settings

`Logic/view_settings.gd` holds the block and reads it back. It belongs to the
document rather than to whoever is at the keyboard, because a map of a world is
drawn the way its author chose:

| Key                 | Type              | Default             | What it says |
|---------------------|-------------------|---------------------|--------------|
| `background_color`  | `[r, g, b, a]`    | black               | What is behind the planet |
| `star_field`        | bool              | `true`              | Whether the star field is drawn on it |
| `grid_color`        | `[r, g, b, a]`    | white at a third    | The color of the longitude and latitude lines |
| `grid_spacing`      | degrees, 1 to 90  | `15`                | How far apart its lines are; a line falls on every multiple of it, counted from the equator and the prime meridian |
| `light_direction`   | `[elevation, azimuth]` in degrees | `[0, 0]` | Where the light comes from, away from the line of sight |
| `ambient`           | 0 to 1            | `0`                 | How much light reaches the night side |
| `planet_color`      | `[r, g, b, a]`    | ocean blue, `[0.16, 0.36, 0.60, 1]` | The color of the planet where no raster covers it; the alpha is read as 1 whatever the file says |
| `raster_path`       | string            | `""`                | The image the planet wears, if any |
| `raster_opacity`    | 0 to 1            | `1`                 | How much of the planet color it covers |
| `raster_visible`    | bool              | `true`              | Whether it is drawn at all |
| `hidden_classes`    | list of names     | `[]`                | Which classes of geometry are switched off |

`hidden_classes` is the [styling](Styling.md#the-visibility-switches): which
features are drawn. Since 0.10.0 the color they come out is decided by the
styles of the groups above them; see
[Feature tree serialization](#feature-tree-serialization). The block has no
style keys, and the dialog that edits it has no style rows.

Every key is optional. A block that does not name one gets the default, and a
value out of range is brought back into it, so a file from a version that knew
fewer settings still opens; see [0.5.0 to 0.6.0](#050-to-060) and
[0.6.0 to 0.7.0](#060-to-070).

The block is **on the undo stack** beside the tree: every version the stack
records holds both, so a change of light, palette or raster is undone the way
a change of geometry is, and the dirty flag comes from the stack alone.
`Document.view_edited()` is what records a view change. Up to 0.7.0 the block
was left off the stack as a matter of how the document was looked at rather
than what it held; the second round of developer feedback asked for one undo
buffer over every document change, and the current time and the animation
settings, which are not document changes, are what remain off it.

A colour picker in the View settings dialog applies every colour the cursor
is dragged over and records only the one left when the picker closes. Every
other field is one version per change.

#### The raster path

`raster_path` is stored relative to the file when the image sits beside it or
under it, so a project and its images can be moved together, and absolute
otherwise. `Document.save_to_file()` works that out against the path being
written, whichever way the image was picked and wherever the document was saved
before, and `Document.resolve_raster()` turns it back into a path to read. A
`res://` path, such as the built in Earth's
`res://Assets/Textures/Earth.jpg`, names an image the application ships and is
stored and resolved as it is.

A document naming an image that is not there still opens: the planet shows its
own color and the reason is recorded rather than thrown. See
[Shader](Shader.md#the-raster).

#### Defaults for new documents

The preferences hold a second copy of the same block, which is what File > New
starts a document from, together with the view it opens in. The View settings
dialog writes both with **Save as default** and puts the open document back to
them with **Restore defaults**. The block holds the scene settings only. The
root's style is pinned, so there is no default to keep for it: a `style` key
that versions before GP-0066 wrote into the block is ignored, and so are the
three style keys of a block saved before 0.10.0. An opened file always wins over
the preference: the block in the file is what that document says about itself.

### Feature tree serialization

The `features` value is the root "Planet" group. The JSON hierarchy mirrors the
tree hierarchy in the UI exactly: groups contain a `children` array with nested
groups and leaf features.

**Group node:**

```json
{
  "uuid": "6b0d6b1e-2c1f-4a3d-9a7e-2f0f1d9c5b31",
  "title": "Group Name",
  "enabled": true,
  "is_group": true,
  "type": "Group",
  "style": {"mode": "inherit", "color": [0.9, 0.9, 0.9, 1.0], "opacity": 1.0, "palette": "ramp",
            "ramp_colors": [[0.0, 0.0, 0.0, 1.0], [1.0, 1.0, 1.0, 1.0]], "ramp_span": 300.0},
  "children": [ ... ]
}
```

`style` is how the group colors the features under it; see
[Styling](Styling.md#group-styles). `mode` is `inherit`, `feature`, `single`,
`age` or `type`, `color` what the single colour mode paints with, `opacity` 0 to
1 and multiplied into everything under the group, and `palette` `ramp`, a
built in palette's key or the path of a `.cpt` file. `ramp_colors` is the
[custom ramp](Styling.md#the-custom-ramp)'s two colors or more, each
`[r, g, b, a]`, and `ramp_span` the My between one and the next, at least 1. A
group without the key inherits at
full opacity, and so does one naming a mode this version does not know.

The **root group's style is pinned** to `GroupStyle.for_root()`: `feature` mode,
full opacity, and the default palette and ramp. `Document.load_from_file()`
reads the root's `style` like any other group's and then replaces it with the
pinned one, so a file's root style has no effect on what is drawn: a feature
under no group of its own is drawn in its own color. Saving writes the pinned
style back, which is the defaults, so an older version that still reads the
root's style finds a valid one and draws the same. Nothing in the application
edits the root's style, and `Document.set_style()` refuses the root. The key is
still written and still read, so this is not a format change and the version
number stays the same.

**Feature (leaf) node:**

```json
{
  "uuid": "0f5b6c2a-7d84-4c19-8b3e-51b0a2c7d4e6",
  "title": "Feature Name",
  "enabled": true,
  "is_group": false,
  "type": "Feature",
  "feature_type": "polygon",
  "color": [0.36, 0.6, 0.33, 1.0],
  "icon": "craton",
  "geometry_kind": "polygon",
  "rings": [[[45.0, 30.0], [46.0, 31.0], [45.0, 32.0]]],
  "keyframes": [{"time": 0.0, "rotation": [0, 0, 0]}],
  "couplings": [{"from": 500.0, "to": 200.0, "parent": "6b0d6b1e-2c1f-4a3d-9a7e-2f0f1d9c5b31"}],
  "time_range": [0, 2000]
}
```

`uuid` is what the node is called in the file. It is written for groups as well
as for features and is kept across a save and a load, because a topology
names the features its sections run along by it; see
[Editing](Editing.md#topologies). A duplicate and a paste each get a fresh
one, so no two nodes of a document share an id.

`feature_type` is an id from the catalog in `Logic/feature_type.gd`. A feature
holding nothing carries the type it was given, which says what the tools will
draw into it; empty is read as no type at all, which only a file written before
0.3.0 holds. See [Properties](Properties.md#the-type-catalog).
A `circle` is written as a `polyline` whose last vertex repeats its first. A
`circle` holding a `polygon` still reads as a Circle, filled, so both kinds are
valid for the type; see [Circles](#circles) for the keys it adds.
`icon` is the glyph the feature's tree row carries, an id from
`Logic/feature_icon.gd`. It is written only when there is one, and a feature
without it shows the same row icon it showed before there were any. Nothing but
the row reads it; see [Properties](Properties.md#the-icon).
`geometry_kind` is `"polygon"`,
`"polyline"`, `"multipoint"` or `"topology"`, and `rings`
holds one array of `[latitude, longitude]` vertices per part. A ring is closed
only for a polygon, and several rings on one polygon are separate outlines
rather than holes. The vertices are in the frame of the feature itself, before
the rotation its keyframes give it at the current time is applied.

#### Circles

A drawn leaf of type `circle` also carries the values its ring is built from:

```json
"feature_type": "circle",
"axis": [90.0, 0.0],
"radius": 23.0,
"circle_segments": 36,
"polar": true,
"geometry_kind": "polyline",
"rings": [[...], [...]]
```

`axis` is the latitude and longitude of the circle's center, in the feature's
own frame. `radius` is the radius in degrees and `circle_segments` how many
segments the ring is cut into. `polar` is written only when it is true, and
then the circle is drawn a second time around the antipode of `axis`; see
[Axis circles](Editing.md#axis-circles). The keys are written only for a circle
that holds a ring, so a leaf without them is some other type or a circle not
drawn yet. `rings` holds the closed polylines as usual, one or two, for a
reader that knows nothing about the parameters. On load the parameters win:
`Feature.from_json()` rebuilds the rings from them, and a missing `radius` or
`circle_segments` takes its default, 23 or 36.

A `circle` leaf with rings but no `axis`, which a script can write, is read the
way the 0.21.0 migration reads one; see [below](#0200-to-0210).

#### Hotspots

A leaf of type `hotspot` also carries the values its rings are built from:

```json
"feature_type": "hotspot",
"hotspot": [19.4, -155.3],
"plate": "6f1c...",
"time_step": 20.0,
"geometry_kind": "polyline",
"rings": [[...], [...]]
```

`hotspot` is the latitude and longitude of the hotspot in the world frame and
`plate` the uuid of the feature it burns through, empty for none. The keys are
optional and written only for this type. A hotspot the Draw tool has not
placed yet writes no `hotspot` and holds no rings, and a leaf without the key is read
as one not placed. `rings` holds the mark and, when there is one, the track,
for a reader that knows nothing about the type. On load the values win: the
track is rebuilt from them before the geometry is collected. See
[Editing](Editing.md#hotspots).

`time_step`, since 0.25.0, is how far apart in time the track is sampled, in
millions of years. It is written only when it is above 0, and a leaf without it
reads as 0, which follows the timeline's Skip. The Skip is a setting of the
machine, not part of the file, so a hotspot left at 0 can show a track with
more or fewer vertices on another machine, and one carrying a step of its own
draws the same everywhere.

#### Topologies

A **topology** carries `sections` instead of `rings`, because its vertices
are resolved from the features it runs along every time the tree or the current
time moves, and writing them down would be writing down a derived value:

```json
{
  "uuid": "9c4a1f77-0b2e-4d61-8a05-3c6d2e9f4b18",
  "title": "Ridge Boundary",
  "type": "Feature",
  "is_group": false,
  "enabled": true,
  "feature_type": "topology",
  "color": [0.58, 0.44, 0.86, 1.0],
  "geometry_kind": "topology",
  "sections": [
    {"feature": "0f5b6c2a-7d84-4c19-8b3e-51b0a2c7d4e6", "part": 0,
     "from": 0, "to": 20, "reversed": false}
  ],
  "keyframes": [],
  "time_range": [0, 2000]
}
```

Each section names a feature by its `uuid`, which part of it, the two vertex
indices the run goes between, both ends included and counted from zero, and
whether the run is walked backwards. A section whose feature is not in the file
is kept as it stands, so a topology loads and saves whole even while one of the
features it names is missing; see
[Editing](Editing.md#topologies).

A closed topology adds `"closed": true`, and the sections are then joined into
one filled ring; see [Editing](Editing.md#closed-topologies). An open topology
writes no `closed` key, and a topology without one is open.

A midway topology adds `"midway": true`: it has two sections and is the line
between them, the way a [ridge](Editing.md#the-ridge) is. A topology without
the key is not midway.

A [crust](Editing.md#the-crust) is a topology with no sections and a `crust`
object naming what it is built from:

```json
"feature_type": "topology",
"geometry_kind": "topology",
"closed": true,
"sections": [],
"crust": {"half": "3e1d...", "ridge": "77ab...", "edge": 3}
```

`half` is the uuid of the half of the split plate it lies beside, `ridge` the
uuid of the midway topology it opened from, and `edge` how many vertices the
cut had. A crust is closed and holds the bands, with the isochrons and the
flowlines drawn over them. It writes no rings: they are rebuilt from the half,
the ridge, the time and the step before the geometry is collected, and so are
the band ages the [age ramp](Editing.md#the-crust) colors them by. A crust
carries the same optional `time_step` as a hotspot, with the same meaning.

`keyframes` is where the feature is over time: a list of `{time, rotation}`,
sorted with the youngest first, `time` an age in millions of years before
present and `rotation` the three angles above. Only a leaf has them; a group
carries no motion since 0.8.0. The file is written at full float
precision, so a keyframe time comes back as the exact time it was written at;
see [Time](Time.md#precision).

`couplings` is what the feature follows and when: a list of
`{from, to, parent}`, `from` the older age where the span starts, `to` the
younger one where it ends, and `parent` the uuid of the feature followed, the
way a section names its feature. Inside a span the keyframes are relative to
the parent; see [Time](Time.md#coupling). Only a leaf has them, and spans on one
feature do not overlap. A span whose parent is not in the file is kept as it
stands, like a section whose feature is missing. A span naming a circle or a
hotspot is not: neither takes part in coupling, and such a span is dropped when
the file is opened; see [below](#0250-to-0260).

A span may carry `parent_b`, a second uuid. Its frame is then midway between
the two parents; see
[Time](Time.md#following-two-parents). The key is written only when there is
one, so an ordinary span reads the way it always did.

The triangles a polygon is filled with are not in the file. They are derived
from the rings on load, so the file keeps the shape and not the way it happened
to be cut up. See [Draw](Draw.md#data-model).

Serialization is implemented in `Logic/feature.gd` via `Feature.to_json()` and
`Feature.from_json()`.

### Format migration

A loaded file passes through `Document.migrate()`, which receives the parsed
top-level dictionary and transforms it into what the current version expects,
based on the `version` field in the file. See [Versioning](Versioning.md) for
when a migration is required.

#### 0.1.0 to 0.2.0

0.1.0 stored a leaf feature as `vertices`, a flat list where every three of them
were one triangle, and there was no `geometry_kind`. It also carried `invert`,
`single`, `wrap`, `resize` and `repeat`, five switches left over from the rule
editor this interface came from, which nothing ever read.

The migration drops the five switches and recovers the outline the triangles
covered: an edge two triangles share is inside the shape, an edge used by a
single triangle is on the boundary, and the boundary edges chain up into one
ring per polygon. A feature holding several separate polygons therefore comes
back as several rings. Triangles that do not chain up, which a file written by
hand can hold, are each kept as their own ring, so no vertex is lost.

The oldest files called the rotation angles `position`; the migration renames
that key as well.

#### 0.2.0 to 0.3.0

0.3.0 added `feature_type` to a leaf feature. There is no migration step for it:
a feature without the key takes its type from its geometry, so a 0.2.0 file
arrives whole.

#### 0.3.0 to 0.4.0

Up to 0.3.0 a leaf carried one `rotation` and nothing moved in time. 0.4.0
keeps `keyframes` instead, on groups as well as on leaves.

The migration turns the one rotation into the keyframe at time zero: the
present, which is where a file written before this was drawn. A feature that
came in this way behaves as it did before the phase, because one keyframe holds
at every time. A group had no rotation to carry over and arrives without
keyframes, standing still until someone moves it.

#### 0.4.0 to 0.5.0

0.5.0 added `uuid` to every node. There is no migration step for it: a node
without one is given a fresh id on load, the same way 0.3.0 treated a feature
without a `feature_type`. Nothing in a file written before 0.5.0 can be naming a
node, so an id invented on load loses nothing.

#### 0.5.0 to 0.6.0

0.6.0 added the `view` block. There is no migration step for it: a file without
one gets every default, and the defaults are the scene exactly as it was drawn
before the block existed, so an older file opens looking the way it always did.

#### 0.6.0 to 0.7.0

0.7.0 added the styling keys to the `view` block. There is no migration step for
them either: a block without them gets each feature drawn in its own colour with
every class of geometry shown, which is what every version before 0.7.0 drew.

#### 0.7.0 to 0.8.0

Up to 0.7.0 a group had `keyframes` and everything under it inherited that
motion. 0.8.0 keeps motion on leaf features alone: a group is organization and
carries none, and what follows what is a coupling between two features
(GP-0046).

The migration folds the motion in. For every leaf under at least one moving
group, the rotations of the groups above it and its own are composed at every
time any keyframe along that chain sits at, and the result is written as the
leaf's own keyframes, so the feature is drawn where it was at each of those
times. Between two of them the interpolation of the composed rotations is not
quite the composition of the interpolations, so a feature under a moving
group can differ slightly from what 0.7.0 drew between keyframes. A leaf under
no moving group is left exactly as it was, and every group loses its keyframe
list. The step is `Document._to_0_8_0()`.

#### 0.8.0 to 0.9.0

Up to 0.8.0 the type catalog had eight entries. 0.9.0 keeps five, the ones the
program treats differently, and the type follows the geometry. The migration
maps each old id onto a new one:

| Up to 0.8.0 | 0.9.0 |
| ----------- | ----- |
| `craton`, `terrane`, `coastline` | `polygon` |
| `ridge` | `line` |
| `marker` | `points` |
| `small_circle` | `circle` |
| `topology` | `topology` |
| `unclassified`, or a type no catalog had | left empty, so the geometry decides |

A mapped type that does not hold the feature's kind gives way to the kind's own
when the feature is read, so a coastline drawn as a line opens as a Line and an
unclassified multipoint as Points. The View menu switch for circles is stored
as `circles` in `hidden_classes` now, and the migration renames the old name in
the file's view block. The step is `Document._to_0_9_0()`.

The same switch in the preferences' `view_defaults` is not migrated: a default
that had the circles off shows them again until it is saved once more.

#### 0.9.0 to 0.10.0

Up to 0.9.0 the whole document had one draw style, in the `view` block. 0.10.0
gives every group a `style` in place of GPlates layer coloring, and the root
group's style is the document default. The migration takes `draw_style`,
`single_color` and `palette` out of the view block and writes them onto the root
group as `mode`, `color` and `palette`, at full opacity:

| Up to 0.9.0, `view` | 0.10.0, the root group's `style` |
| ------------------- | -------------------------------- |
| `draw_style`        | `mode`                           |
| `single_color`      | `color`, alpha and all           |
| `palette`           | `palette`                        |

A block that named none of the three leaves the root on each feature's own
colour, which is what it drew. Every other group arrives without a style and
inherits. The step is `Document._to_0_10_0()`. Since the root's style is
[pinned](#feature-tree-serialization), the loader replaces the style this step
writes onto the root: a file drawn in a single color opens with each feature in
its own color, and drawing it in one color again takes a group with that style.
The preferences' `view_defaults` are not rewritten, and the three keys in them
are ignored.

#### 0.10.0 to 0.11.0

0.11.0 added `ramp_from`, `ramp_to` and `ramp_span` to the group style, and the
`ramp` palette that reads them. There is no migration step: a style without
them takes the default ramp, which nothing drew with before.

The Feature age style also changed what it reads, from the age a feature came
into existence at to the age it has reached at the current time. Nothing in the
file changes for that. At the present the two are the same number, so a file
opens at the present looking the way it did.

#### 0.11.0 to 0.12.0

0.12.0 added `couplings` to a leaf feature. There is no migration step: a leaf
without the key follows nothing, and its keyframes are world rotations, which
is what every feature's keyframes were before.

#### 0.12.0 to 0.13.0

0.13.0 made the group style's ramp a list of colors rather than two ends.
`ramp_from` and `ramp_to` become the two stops of `ramp_colors` and are removed;
a style that named only one of them, or neither, takes the new default, black to
white. The palette list is Custom and Rainbow now, so a style naming one of the
three built in tables that went — `age`, `grayscale` and `steps` — takes the
custom ramp, which is what replaced them. A style naming a `.cpt` file keeps it.
The step is `Document._to_0_13_0()`.

#### 0.13.0 to 0.14.0

0.14.0 added `icon` to a leaf feature. There is no migration step: a leaf
without the key carries no icon, which is what every feature carried before.

#### 0.14.0 to 0.15.0

0.15.0 added `parent_b` to a coupling span. There is no migration step either:
a span without the key follows the one parent it names, which is what every
span did before 0.15.0.

#### 0.15.0 to 0.16.0

0.16.0 renamed five keys of the `view` block. The image the planet wears is a
raster, the word GPlates uses, so it is not confused with the background, and
the graticule is a grid:

| Up to 0.15.0, `view` | 0.16.0, `view`   |
| -------------------- | ---------------- |
| `backdrop_path`      | `raster_path`    |
| `backdrop_opacity`   | `raster_opacity` |
| `backdrop_visible`   | `raster_visible` |
| `graticule_color`    | `grid_color`     |
| `graticule_spacing`  | `grid_spacing`   |

The values are kept as they are. The step is `Document.rename_view_keys()`.
`Config.get_view_defaults()` renames the same keys in the preferences'
`view_defaults` and writes the file back on the first read, so the defaults
a user saved carry over.

#### 0.16.0 to 0.17.0

0.17.0 added `planet_color` to the `view` block and made the built in Earth,
which until then was drawn under every document, a raster like any other. A
block without `planet_color` reads as the default, ocean blue.

A file from before 0.17.0 whose `raster_path` is empty or missing, including a
file with no `view` block at all, showed the Earth. The step gives it
`raster_path` `res://Assets/Textures/Earth.jpg`, `raster_opacity` 1 and
`raster_visible` true, so it looks as it did; the opacity and the switch did
nothing while there was no image. A file naming an image keeps it with its
opacity and switch, and at an opacity under 1 the image now blends over the
planet color rather than over the Earth. The step is `Document._to_0_17_0()`.

The preferences' `view_defaults` have no step. A block without `planet_color`
takes the default, and one with an empty `raster_path` keeps it, so a new
document has no raster.

#### 0.17.0 to 0.18.0

0.18.0 added `axis`, `radius` and `circle_segments` to a leaf feature, for
the Polar circles type, which 0.21.0 folded into [Circle](#circles). The step
changes nothing but the version: a leaf without the keys is not polar circles,
and no file before 0.18.0 holds one.

#### 0.18.0 to 0.19.0

0.19.0 added `hotspot`, `plate` and `track_step` to a leaf feature, for
[hotspots](#hotspots). The step changes nothing but the version: a leaf
without the keys is not a hotspot, and no file before 0.19.0 holds one.

#### 0.19.0 to 0.20.0

0.20.0 added `closed` to a topology, for
[closed topologies](#topologies). The step changes nothing but the version: a
topology without the key is open, which is what every topology was before.

#### 0.20.0 to 0.21.0

0.21.0 dropped the `polar_circles` type and gave a [circle](#circles) its
center, radius, segment count and `polar` switch. The step,
`Document._to_0_21_0()`, changes two kinds of leaf:

- A `polar_circles` leaf becomes a `circle` with `polar` true. It keeps
  `axis`, `radius` and `circle_segments`, so it rebuilds the same two rings.
- A `circle` leaf without `axis` holding one ring, which is what Draw wrote,
  is given the circle that ring was cut from by `Circle.fit()`: the center is
  the direction of the mean of the vertices' unit vectors, the radius their
  mean angular distance from it, and the segment count the number of vertices,
  less the repeated last one. The ring rebuilt from them is the stored ring to
  within rounding. A ring of fewer than three distinct vertices is left alone,
  and so is the leaf.
- A `circle` leaf holding more than one ring was drawn more than once and is no
  single circle. It keeps its rings and becomes the type of its kind, `line`
  for polylines and `polygon` for polygons.

The Preferences' Feature colors drop a color kept for `polar_circles` when they
are read.

#### 0.21.0 to 0.22.0

0.22.0 samples a [hotspot](#hotspots) track at the timeline's Skip and lets a
hotspot be not placed yet. The step, `Document._to_0_22_0()`, removes
`track_step` from every `hotspot` leaf and leaves the rest alone. A 0.21.0
hotspot always has its `hotspot` key, so it stays placed.

#### 0.22.0 to 0.23.0

0.23.0 made the [ridge](Editing.md#the-ridge) a midway topology and the
[crust](Editing.md#the-crust) bands between isochrons with a lines feature. The
step, `Document._to_0_23_0()`, changes what the Split tool left at 0.22.0:

- A polyline leaf with one ring, one keyframe and one coupling span naming a
  `parent_b` is a ridge. It becomes a `topology` leaf with `"midway": true` and
  two sections covering vertices 0 to n - 1, where n is the ring's vertex count:
  one on `parent`, and one on `parent_b`, reversed, since the second half of a
  split holds the cut the other way round. The first section is on the part of
  `parent` that its crust names, or on part 0 without a crust. The ring, the
  keyframe and the span are dropped. The title, color and time range stay.
- A closed topology with two sections, the second on such a ridge, is a crust.
  Its sections go and it gets `"crust": {"half": ..., "ridge": ..., "edge": ...}`,
  with the half from the first section, the ridge from the second, and the
  first section's `to` plus one as the edge. A copy titled `<title> lines`, with
  a new uuid, the crust lines color, no `closed` key and `"lines": true`, is
  inserted before it.

Every other leaf, including closed topologies along anything else, is left
alone. The lines leaf this step inserts is what the next one takes away again;
each step is written for the format of its own version.

#### 0.23.0 to 0.24.0

0.24.0 moved the isochrons and the flowlines into the
[crust](Editing.md#the-crust) itself, so the leaf that held them alone is gone
from the tree. The step, `Document._to_0_24_0()`, drops every leaf whose `crust`
object carries `"lines": true` and leaves the crust beside it as it is, which
already says what it is built from. A 0.23.0 split that had four crust rows
loads with two, drawing the same bands, isochrons and flowlines.

#### 0.24.0 to 0.25.0

0.25.0 gave a [hotspot](#hotspots) and a [crust](Editing.md#the-crust) a
`time_step` of their own. Nothing but the version moves: a leaf from before has
no key, which reads as 0, and 0 follows the timeline's Skip, which is what both
did.

#### 0.25.0 to 0.26.0

0.26.0 took [circles](#circles) and [hotspots](#hotspots) out of
[coupling](Time.md#coupling) altogether. Until 0.25.0 a file could still name
one in a span, and the panel and the timeline marked such a span as broken. The
step, `Document._to_0_26_0()`, drops every span whose child, `parent` or
`parent_b` is a circle or a hotspot, and writes to the log how many it dropped.

The features themselves stay, and so do their keyframes: a feature left without
the span it had stops following whatever it followed and stands where its own
keyframes put it. Every other span is kept as it was written.

## The config file

`Logic/config.gd` keeps one JSON file per user, `%APPDATA%\MiddleEarth\config.json`,
outside the project. Every setter writes it immediately, so a crash cannot lose
more than the last change.

| Key                                | What it holds                                       |
| ---------------------------------- | --------------------------------------------------- |
| `last_directory`                   | Where the file dialogs open                          |
| `recent_files`                     | Paths, newest first, at most `MAX_RECENT_FILES` (10) |
| `restore_session`                  | Whether to reopen the last file on launch            |
| `window`                           | `x`, `y`, `width`, `height` and `maximized`          |
| `splitter_left`, `splitter_right`  | The two split offsets                                |
| `panel_features`, `panel_properties`, `panel_timeline`, `panel_kinematics`, `panel_console`, `panel_status_bar` | Which panels are shown. Everything but the kinematics graphs and the console is shown when the file says nothing |
| `kinematics_place` | Whether the kinematics panel graphs latitude and longitude above the rate. Off when the file says nothing |
| `highlight_children` | Whether the children of the selected feature are highlighted. Off when the file says nothing. When the key is absent, `highlight_riders`, the name an older version wrote, is read instead |
| `animation`                        | The playback range, the speed and the loop switch    |
| `skip_increment`                   | How far the timeline's `<` and `>` buttons jump, in millions of years, and how finely a hotspot track and a crust are sampled when they carry no step of their own |
| `planet_radius_km`                 | What distances are read against, Earth's mean radius by default |
| `vertex_marker_scale`, `line_width_scale` | How large the outline overlay is drawn, as multiples of the shader defaults |
| `snap_to_vertices`                 | Edit > Snap to vertices: whether a dragged vertex, a pole or a drawn point snaps onto a nearby vertex. On when the file says nothing |
| `split_ridge`, `split_crust`, `split_children` | Whether the Split tool leaves a ridge, crust beside it, and cuts the polygon's children along. All on when the file says nothing |
| `export_width`                     | How wide an exported picture or video is; the height follows from what is being shown |
| `ffmpeg`                           | Which ffmpeg encodes the frames of a video; the path is searched when unset |
| `feature_colors`                   | Feature type id to `[r, g, b, a]`, for the types whose color the Preferences dialog changed; a type missing here has its catalog color |
| `default_view`                     | Which view a new document opens in, by the name the projection selector shows |
| `view_defaults`                    | The [view settings](#view-settings) block a new document starts from |
| `python_interpreter`               | Which Python runs the scripting bridge; the project's own `.venv` when unset |
| `script_directories`               | Where scripts that become menu entries are looked for; the project's `Scripts` folder when unset. An empty list is a choice and stays empty |

### Recent files

Opening or saving a file puts it at the front of `recent_files`, removes any
earlier copy of it and drops the oldest entries beyond the cap. File > Open
Recent lists them in that order, with a Clear entry that empties the list.

### The session

On launch the window geometry, the splitter offsets and the panel visibility are
restored from the config, and the newest recent file is reopened unless
`restore_session` is off or the file is gone. Everything but the reopened file is
written back when the application quits.

A run that does not own the window skips all of this and keeps its settings in a
scratch folder under the user data directory: one started with
`--automation-port`, and one where a test runner hosts the application scene. So
a scripted run always starts from the same window and never touches the settings
of whoever is at the keyboard.
