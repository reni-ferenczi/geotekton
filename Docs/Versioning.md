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
which has a step too; and 0.10.0 gave groups a style and moves the draw style,
the single colour and the palette out of the view settings onto the root group,
which has a step as well; and 0.11.0 added the age ramp to the group style,
whose defaults nothing drew with before, so it reads a 0.10.0 file as it stands;
and 0.12.0 added couplings to a leaf feature, and a leaf without them follows
nothing, so it reads a 0.11.0 file as it stands too; and 0.13.0 made the group
style's ramp a list of colours and cut the built in palettes down to Rainbow,
which has a step for the two ends and the palettes that went; and 0.14.0 gave a
leaf feature the icon of its tree row, and a leaf without one carries none, so
it reads a 0.13.0 file as it stands; and 0.15.0 let a coupling span name a
second parent, and a span without one follows the parent it names, so it reads
a 0.14.0 file as it stands too; and 0.16.0 renamed five keys of the view block,
calling the backdrop image a raster and the graticule a grid, which has a step
that renames them; and 0.17.0 gave the planet a color of its own and made the
built in Earth a raster, which has a step that gives a file naming no raster the
Earth, so it looks as it did; and 0.18.0 gave a leaf the axis, radius and segment
count of polar circles, and a leaf without them is some other type, so it reads a
0.17.0 file as it stands; and 0.19.0 gave a leaf the place, plate and track step
of a hotspot, which a 0.18.0 leaf does not have either, so that file too is read
as it stands; and 0.20.0 let a topology be closed, and a topology without the
flag is open, so a 0.19.0 file is read as it stands as well; and 0.21.0 folded
Polar circles into Circle and gave a circle its center and radius, which has a
step that retypes a polar circles leaf and works out the center and radius of a
drawn circle from its ring; and 0.22.0 samples a hotspot track at the
timeline's Skip, which has a step that removes the track step from a hotspot
leaf, and lets a hotspot wait for its place, which a 0.21.0 hotspot always has;
and 0.23.0 made the ridge a midway topology and the crust bands between
isochrons, which has a step that turns a 0.22.0 ridge and its crusts into the
new ones and adds the lines feature beside each crust; and 0.24.0 gave the
crust its own isochrons and flowlines, which has a step that drops the leaf
that used to hold them; and 0.25.0 gave a hotspot and a crust a time step of
their own, and a leaf without one reads as 0, which is the timeline's Skip, so
a 0.24.0 file is read as it stands; and 0.26.0 took circles and hotspots out of
coupling, which has a step that drops every span naming one and says how many
it dropped; and 0.27.0 renamed the program to Geotekton, so the `application`
field says `geotekt` and the extension is `.geotekt`, and a file from before
it is not read; and 0.28.0 changed nothing in the file; and 0.29.0 gave a leaf
feature its line width, and a leaf without one is drawn at the width it always
was, so it reads a 0.27.0 file as it stands.

The first public release will have major version 1.

## Public releases (major version 1+)

Once version 1.0.0 is reached, a migration must be added to `Document.migrate()` whenever the file format changes. The `version` field stored in each `.geotekt` file identifies which application version produced it, allowing the migration function to apply the necessary transformations on load.
