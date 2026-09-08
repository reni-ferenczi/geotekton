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

The undo stack is the only source of the dirty flag. Every edit calls
`Document.record()`, which stores a clone of the tree; the document remembers
which of those versions is on disk and is clean exactly while the stack sits on
it. So undoing back to the last save makes the document clean again, and redoing
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

The file is a JSON object with three top-level keys:

```json
{
  "application": "middle-earth",
  "version": "0.4.0",
  "features": { ... }
}
```

| Key           | Description                                                        |
|---------------|--------------------------------------------------------------------|
| `application` | Always `"middle-earth"`. Used to validate the file on load.        |
| `version`     | The application version that produced this file.                   |
| `features`    | The root group of the feature tree, serialized via `to_json()`.    |

### Feature tree serialization

The `features` value is the root "Planet" group. The JSON hierarchy mirrors the
tree hierarchy in the UI exactly: groups contain a `children` array with nested
groups and leaf features.

**Group node:**

```json
{
  "title": "Group Name",
  "enabled": true,
  "is_group": true,
  "type": "Group",
  "keyframes": [ ... ],
  "children": [ ... ]
}
```

**Feature (leaf) node:**

```json
{
  "title": "Feature Name",
  "enabled": true,
  "is_group": false,
  "type": "Feature",
  "feature_type": "craton",
  "color": [0.82, 0.41, 0.12, 1.0],
  "geometry_kind": "polygon",
  "rings": [[[45.0, 30.0], [46.0, 31.0], [45.0, 32.0]]],
  "keyframes": [{"time": 0.0, "rotation": [0, 0, 0]}],
  "time_range": [0, 2000]
}
```

`feature_type` is an id from the catalog in `Logic/feature_type.gd`; see
[Properties](Properties.md#the-type-catalog). `geometry_kind` is `"polygon"`,
`"polyline"` or `"multipoint"`, and `rings`
holds one array of `[latitude, longitude]` vertices per part. A ring is closed
only for a polygon, and several rings on one polygon are separate outlines
rather than holes. The vertices are in the frame of the feature itself, before
the rotation its keyframes give it at the current time is applied.

`keyframes` is where the node is over time: a list of `{time, rotation}`,
sorted with the youngest first, `time` an age in millions of years before
present and `rotation` the three angles above. A group has them as well, and
everything under it inherits its motion. The file is written at full float
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
a feature without the key loads as `unclassified`, which is the type that allows
every geometry kind, so a 0.2.0 file arrives whole and nothing in it is
reclassified by guesswork.

#### 0.3.0 to 0.4.0

Up to 0.3.0 a leaf carried one `rotation` and nothing moved in time. 0.4.0
keeps `keyframes` instead, on groups as well as on leaves.

The migration turns the one rotation into the keyframe at time zero: the
present, which is where a file written before this was drawn. A feature that
came in this way behaves as it did before the phase, because one keyframe holds
at every time. A group had no rotation to carry over and arrives without
keyframes, standing still until someone moves it.

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
| `panel_features`, `panel_properties`, `panel_timeline`, `panel_status_bar` | Which panels are shown |
| `animation`                        | The playback range, step, frame rate and the two switches |
| `planet_radius_km`                 | What distances are read against, Earth's mean radius by default |
| `vertex_marker_scale`, `line_width_scale` | How large the outline overlay is drawn, as multiples of the shader defaults |
| `snap_to_vertices`                 | Whether a dragged vertex snaps onto a nearby one |

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
