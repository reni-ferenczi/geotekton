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
  "version": "0.9.0",
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
| `graticule_color`   | `[r, g, b, a]`    | white at a third    | The colour of the grid |
| `graticule_spacing` | degrees, 1 to 90  | `15`                | How far apart its lines are |
| `light_direction`   | `[elevation, azimuth]` in degrees | `[0, 0]` | Where the light comes from, away from the line of sight |
| `ambient`           | 0 to 1            | `0`                 | How much light reaches the night side |
| `backdrop_path`     | string            | `""`                | The image the planet wears, if any |
| `backdrop_opacity`  | 0 to 1            | `1`                 | How much of the Earth it covers |
| `backdrop_visible`  | bool              | `true`              | Whether it is drawn at all |
| `hidden_classes`    | list of names     | `[]`                | Which classes of geometry are switched off |
| `draw_style`        | string            | `"feature"`         | How a feature's colour is chosen |
| `single_color`      | `[r, g, b, a]`    | light grey          | What the single colour style paints with |
| `palette`           | string            | `"age"`             | A built in palette's key, or the path of a `.cpt` file |

The last four are the [styling](Styling.md): which features are drawn and what
colour they come out.

Every key is optional. A block that does not name one gets the default, and a
value out of range is brought back into it, so a file from a version that knew
fewer settings still opens; see [0.5.0 to 0.6.0](#050-to-060) and
[0.6.0 to 0.7.0](#060-to-070).

The block is **on the undo stack** beside the tree: every version the stack
records holds both, so a change of light, palette or backdrop is undone the way
a change of geometry is, and the dirty flag comes from the stack alone.
`Document.view_edited()` is what records a view change. Up to 0.7.0 the block
was left off the stack as a matter of how the document was looked at rather
than what it held; the second round of developer feedback asked for one undo
buffer over every document change, and the current time and the animation
settings, which are not document changes, are what remain off it.

A colour picker in the View settings dialog applies every colour the cursor
is dragged over and records only the one left when the picker closes; a drag
with the Light tool records once, on release. Every other field is one version
per change.

#### The backdrop path

`backdrop_path` is stored relative to the file when the image sits beside it or
under it, so a project and its images can be moved together, and absolute
otherwise. `Document.save_to_file()` works that out against the path being
written, whichever way the image was picked and wherever the document was saved
before, and `Document.resolve_backdrop()` turns it back into a path to read.

A document naming an image that is not there still opens: the planet keeps the
built in Earth and the reason is recorded rather than thrown. See
[Shader](Shader.md#the-backdrop-image).

#### Defaults for new documents

The preferences hold a second copy of the same block, which is what File > New
starts a document from, together with the view it opens in. The View settings
dialog writes both with **Save as default** and puts the open document back to
them with **Restore defaults**. An opened file always wins over the preference:
the block in the file is what that document says about itself.

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
  "children": [ ... ]
}
```

**Feature (leaf) node:**

```json
{
  "uuid": "0f5b6c2a-7d84-4c19-8b3e-51b0a2c7d4e6",
  "title": "Feature Name",
  "enabled": true,
  "is_group": false,
  "type": "Feature",
  "feature_type": "polygon",
  "color": [0.82, 0.41, 0.12, 1.0],
  "geometry_kind": "polygon",
  "rings": [[[45.0, 30.0], [46.0, 31.0], [45.0, 32.0]]],
  "keyframes": [{"time": 0.0, "rotation": [0, 0, 0]}],
  "time_range": [0, 2000]
}
```

`uuid` is what the node is called in the file. It is written for groups as well
as for features and is kept across a save and a load, because a line topology
names the features its sections run along by it; see
[Editing](Editing.md#line-topologies). A duplicate and a paste each get a fresh
one, so no two nodes of a document share an id.

`feature_type` is an id from the catalog in `Logic/feature_type.gd`, or empty
for a feature holding nothing; see
[Properties](Properties.md#the-type-catalog). `geometry_kind` is `"polygon"`,
`"polyline"`, `"multipoint"` or `"topology"`, and `rings`
holds one array of `[latitude, longitude]` vertices per part. A ring is closed
only for a polygon, and several rings on one polygon are separate outlines
rather than holes. The vertices are in the frame of the feature itself, before
the rotation its keyframes give it at the current time is applied.

A **line topology** carries `sections` instead of `rings`, because its vertices
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
[Editing](Editing.md#line-topologies).

`keyframes` is where the feature is over time: a list of `{time, rotation}`,
sorted with the youngest first, `time` an age in millions of years before
present and `rotation` the three angles above. Only a leaf has them; a group
carries no motion since 0.8.0. The file is written at full float
precision, so a keyframe time comes back as the exact time it was written at;
see [Time](Time.md#precision).

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
carries none, and what rides on what is a coupling between two features
(GP-0046).

The migration folds the motion in. For every leaf under at least one moving
group, the rotations of the groups above it and its own are composed at every
time any keyframe along that chain sits at, and the result is written as the
leaf's own keyframes, so the feature is drawn where it was at each of those
times. Between two of them the interpolation of the composed rotations is not
quite the composition of the interpolations, so a feature that rode on a moving
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
| `animation`                        | The playback range, the speed and the loop switch    |
| `skip_increment`                   | How far the timeline's `<` and `>` buttons jump, in millions of years |
| `planet_radius_km`                 | What distances are read against, Earth's mean radius by default |
| `vertex_marker_scale`, `line_width_scale` | How large the outline overlay is drawn, as multiples of the shader defaults |
| `snap_to_vertices`                 | Whether a dragged vertex snaps onto a nearby one |
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
