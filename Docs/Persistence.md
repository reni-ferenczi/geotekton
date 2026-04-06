# Save and Load

## Overview

The application supports explicit saving and loading of the feature tree to and from files. There is no autosave; saving must be triggered by the user.

### UI entry points

- **Toolbar buttons**: Save and Load buttons in the feature tree toolbar
- **File menu**: File > Open, File > Save As, File > Save
- **Keyboard shortcuts**: Ctrl+S (save), Ctrl+O (open/load)

## File Format

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

The `features` value is the root "Planet" group. The JSON hierarchy mirrors the tree hierarchy in the UI exactly: groups contain a `children` array with nested groups and leaf features.

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

Serialization is implemented in `Logic/feature.gd` via `Feature.to_json()` and `Feature.from_json()`.

## Format Migration

When a file is loaded, it is passed through the `Features.migrate()` function (`Scenes/Features/features.gd`). This function receives the parsed top-level dictionary and transforms it to match the current version's expected format, based on the `version` field in the file.

See [Versioning](Versioning.md) for the rules on when migrations are required and how version numbers relate to file format changes.

## Behavior on Load

- The entire feature tree is replaced with the loaded content.
- The undo/redo buffer is reset (you cannot undo back to the state before loading).
- The planet view is refreshed to reflect the loaded features.
- No warning is shown about unsaved changes before loading (planned for a future release).
