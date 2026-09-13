# Versioning

The application uses semantic versioning: **major.minor.patch** (e.g. `0.1.0`). The version is stored in `project.godot` under `application/config/version` and read at runtime via `Application.VERSION`.

## Version number rules

- **Patch** (e.g. 1.0.0 -> 1.0.1): Backwards and forwards compatible changes. Older application versions can still load files produced by the newer version.
- **Minor** (e.g. 1.0.0 -> 1.1.0): The file format changed in a way that older versions can no longer load it. A migration must be added to `Document.migrate()` in `Logic/document.gd`.
- **Major**: Reserved for complete redesigns of the application. Never increased automatically.

## Pre-release (major version 0)

While the major version is 0, the application is in pre-release and the file
format may change without keeping backwards compatibility. A migration is still
written whenever files in the old format exist, are worth reading, and cannot be
read as they are: 0.2.0 changed how a feature stores its geometry and reads
0.1.0 files through `Document.migrate()`; 0.3.0 only added a field and reads a
0.2.0 file without a step of its own; 0.4.0 replaced the single rotation
with a list of keyframes and has a step for it; 0.5.0 again only added fields,
so it too reads the version before it as it stands; 0.6.0 added the view
settings block, whose defaults are the scene as it was drawn before there was
one, so a file without it opens looking the way it always did; 0.7.0 added
the styling to that block, whose defaults are likewise how every file was drawn
before there were any styles; and 0.8.0 took motion off groups and folds the
keyframes of a moving group into the leaves under it, which has a step; and
0.9.0 cut the eight feature types down to five and maps the old ones onto them,
which has a step too.

The first public release will have major version 1.

## Public releases (major version 1+)

Once version 1.0.0 is reached, a migration must be added to `Document.migrate()` whenever the file format changes. The `version` field stored in each `.middle-earth` file identifies which application version produced it, allowing the migration function to apply the necessary transformations on load.
