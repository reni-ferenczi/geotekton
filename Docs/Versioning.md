# Versioning

The application uses semantic versioning: **major.minor.patch** (e.g. `0.1.0`). The version is stored in `project.godot` under `application/config/version` and read at runtime via `Application.VERSION`.

## Version number rules

- **Patch** (e.g. 1.0.0 -> 1.0.1): Backwards and forwards compatible changes. Older application versions can still load files produced by the newer version.
- **Minor** (e.g. 1.0.0 -> 1.1.0): The file format changed in a way that older versions can no longer load it. A migration must be added to `Document.migrate()` in `Logic/document.gd`.
- **Major**: Reserved for complete redesigns of the application. Never increased automatically.

## Pre-release (major version 0)

While the major version is 0, the application is in pre-release. The file format may change freely without migrations. The first public release will have major version 1.

## Public releases (major version 1+)

Once version 1.0.0 is reached, a migration must be added to `Document.migrate()` whenever the file format changes. The `version` field stored in each `.middle-earth` file identifies which application version produced it, allowing the migration function to apply the necessary transformations on load.
