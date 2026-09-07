# The document, files and settings

## The document

`Logic/document.gd` owns everything about the open document: the feature tree,
the file it came from and the undo stack. `Application` creates one and hands it
to the `Features` panel, which edits that tree instead of holding one of its own.

Two signals tell the rest of the window what happened:

| Signal          | Emitted when                                    |
| --------------- | ----------------------------------------------- |
| `root_replaced` | The tree was rebuilt: by New, Open, undo or redo |
| `state_changed` | The path, the dirty flag or the undo depth moved |

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
  "version": "0.1.0",
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
  "repeat": false,
  "is_group": true,
  "type": "Group",
  "children": [ ... ]
}
```

**Feature (leaf) node:**

```json
{
  "title": "Feature Name",
  "enabled": true,
  "repeat": false,
  "is_group": false,
  "type": "Feature",
  "color": [0.82, 0.41, 0.12, 1.0],
  "invert": false,
  "single": false,
  "wrap": false,
  "resize": 0,
  "vertices": [[45.0, 30.0], [46.0, 31.0]],
  "position": [0, 0, 0],
  "time_range": [0, 2000]
}
```

Serialization is implemented in `Logic/feature.gd` via `Feature.to_json()` and
`Feature.from_json()`.

### Format migration

A loaded file passes through `Document.migrate()`, which receives the parsed
top-level dictionary and transforms it into what the current version expects,
based on the `version` field in the file. It does nothing while the major
version is 0. See [Versioning](Versioning.md) for when a migration is required.

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

### Recent files

Opening or saving a file puts it at the front of `recent_files`, removes any
earlier copy of it and drops the oldest entries beyond the cap. File > Open
Recent lists them in that order, with a Clear entry that empties the list.

### The session

On launch the window geometry, the splitter offsets and the panel visibility are
restored from the config, and the newest recent file is reopened unless
`restore_session` is off or the file is gone. Everything but the reopened file is
written back when the application quits.

A run started with `--automation-port` skips all of this and keeps its settings
in a scratch folder under the user data directory, so a scripted run always
starts from the same window and never touches the settings of whoever is at the
keyboard.
