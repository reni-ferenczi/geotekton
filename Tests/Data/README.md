# Sample files

Hand-made `.geotekt` files used as fixtures by the tests. They are written in the
exact format `Document.save_to_file` produces: tab-indented JSON, keys sorted.
See `Docs/Persistence.md` for the formats themselves. All but one say
`"application": "geotekt"`, whatever format version they are written in;
`empty.middle-earth` keeps the name and the field the program wrote up to
0.26.0, as the standing check that such a file still opens, so leave it as it is.

Four of the eight are fixtures for the older formats. Three are still written in
**0.1.0**, where a feature stored a flat list of
triangles and no geometry kind. They are the fixtures for `Document.migrate()`, which
recovers the outline those triangles covered, so leave them as they are.
`mixed_geometry.geotekt` is written in **0.2.0**. None of those four carries
a `feature_type`, so all four are fixtures for what 0.3.0 does with an older
file: every feature in one takes its type from its geometry. None of them carries `keyframes`
either, so all four are fixtures for 0.4.0 as well: the one `rotation` a leaf
holds becomes its keyframe at time zero, and one keyframe holds at every time, so
the samples sit where they always did whatever the current time is.

Every sample is older than 0.17.0 and names no raster, so each one opens
wearing the built in Earth, which is what the probe points below were read
against.

Every feature in the samples carries a color of its own, so the green a new
polygon starts in, `Color(0.36, 0.60, 0.33)` in `Logic/feature_type.gd`, shows
in none of them. The tests that want that green draw a feature of their own,
and a feature read without a color comes out in it.

The other four are written in a format recent enough to need no geometry
migration.
`group_styles.geotekt` is the one written in **0.10.0**, the fixture for
group styles.
`craton.geotekt` is the fixture for a file the application saved rather
than one it had to recover: rings, a geometry kind, a feature type, a keyframe
list and a uuid on every node. `motion.geotekt` is the one whose keyframe
list holds more than one keyframe, which is what makes it the fixture for
motion over time.

`topology.geotekt` is the fixture for a
[line topology](../../Docs/Editing.md#topologies): two multipoints on the
equator, `West Points` in red at 40, 25 and 10 degrees west and `East Points` in
blue at 10, 25 and 40 degrees east, with a green `Boundary` running along all of
both. The features it names are multipoints on purpose, so the only thing drawn
between two of their vertices is the boundary itself: a probe there says which
feature painted the pixel rather than which one happened to be painted last. The
gap from 10 west to 10 east is where the two sections meet without being joined.

Every polygon is wound counter-clockwise as seen from outside the sphere, which is what
`Feature.faces_outwards` enforces on the triangles it derives and what both
`Planet.hit_test` and the geometry shader require. Note that the naive order
(-10, -10), (-10, 10), (10, 0) is the wrong way round; the files use
(-10, -10), (10, 0), (-10, 10).

## Rasters

`Rasters/` holds the fixtures for the image a document wears over the planet
color: the same picture as `quarters.png`, `quarters.jpg`,
`quarters.webp` and `quarters.svg`. Each is 64 by 32, split into four solid
quarters — red north-west, green north-east, blue south-west, yellow south-east
— so a probe says which part of the image landed where on the planet and a
format that arrived upside down or mirrored fails.

The folder carries a `.gdignore`. The files are read from disk at run time by
`Raster.load_from()`, the way any image on the machine is, and never imported
as project resources.

## Colour palettes

`Palettes/` holds hand-written `.cpt` fixtures for the GMT colour palette table
reader in `Logic/palette.gd`, one per shape of palette:

| File               | Contents                                                       |
| ------------------ | -------------------------------------------------------------- |
| `continuous.cpt`   | Two ramps meeting at 100 without a step, black to red to white. |
| `discrete.cpt`     | Three flat slices, with 20 to 30 left uncovered, and an annotation flag and a label to read past. |
| `categorical.cpt`  | A key, a quoted key with a space in it and a number used as a key. |
| `malformed.cpt`    | Two good slices around a line that names no colour, and a `B` with nothing after it. |

Between them they use every part of the format the palettes GPlates ships use.
Those are read where they lie, from `../gplates/sample-data`, rather than copied
in: they are GPL and this project is MIT. `Tests/Unit/test_palette.gd` checks
them when that checkout is beside this one and says so when it is not.

## Probe points

Coordinates are (latitude, longitude) in degrees. `Tests/Unit/test_sample_files.gd`
checks each of them with `Planet.hit_test`. The grid is drawn on multiples of
15 degrees, over the features, so a pixel read on a grid line shows the grid.
The clear probes stay off it, and the rendered and session tests that check a
feature's color read beside the listed points, off the lines: (-3, 3) in
`Red Triangle`, (5, 40) on `Blue Ridge`, (-29.5, -29.5) in the western marker of
`Green Stations` and (32.5, 47.5) in `Blue Quad`.

### triangle.geotekt (0.1.0)

Root group `Planet` > group `Cratons` > `Red Triangle`.

| Probe     | Expected feature | Color               |
| --------- | ---------------- | ------------------- |
| (-3, 0)   | Red Triangle     | red, `[1, 0, 0, 1]` |
| (5, 40)   | nothing          | not red             |

### two_cratons.geotekt (0.1.0)

**Three** features, despite the name: the same red triangle plus two more in the
`Cratons` group. It was two when it was written and gained the third before the
name caught up. Renaming it now would leave the ticket record pointing at a file
that no longer exists, so the name stands as the fixture it grew from rather than
as a count; see GP-0028. `test_sample_files.gd` holds the full list of titles, so
what is in the file cannot drift from what is expected of it.

Neither golden scene shows all three. Counting the pixels each colour dominates
inside the planet view:

| Feature       | `two_cratons` | `two_cratons_tilted`     |
| ------------- | ------------- | ------------------------ |
| Red Triangle  | 14,207 px     | 1,195 px                 |
| Blue Quad     | 4,350 px      | not drawn at all         |
| Green Moved   | 347 px, 14 wide by 105 tall | 5,700 px   |

In the default view `Green Moved` is a sliver at the limb, 14 pixels across;
tilting to latitude 30 and longitude -45 brings it out and carries `Blue Quad`
off the far side. The two scenes cover all three between them, which is what the
tilted one is for. A rendered check that wants a good look at `Green Moved`
belongs in the tilted view, and one that wants `Blue Quad` in the default one.

| Probe      | Expected feature | Color                 |
| ---------- | ---------------- | --------------------- |
| (-3, 0)    | Red Triangle     | red, `[1, 0, 0, 1]`   |
| (30, 45)   | Blue Quad        | blue, `[0, 0, 1, 1]`  |
| (-3, -60)  | Green Moved      | green, `[0, 1, 0, 1]` |
| (5, 40)    | nothing          | none of the above     |

`Blue Quad` is the quad (20, 30), (40, 30), (40, 60), (20, 60), stored as the two
triangles it was cut into. The loader puts the quad back together, so what reaches
the application is one ring of four vertices.

`Green Moved` holds the same vertices as `Red Triangle` with `rotation` `[60, 0, 0]`,
which loads as the one keyframe at time zero. A positive rotation around Y
*decreases* the longitude, so the red probe point (-3, 0) moves to (-3, -60). The
test derives this with `Feature.apply_rotation` rather than trusting the number
written here.

### empty.middle-earth (0.1.0)

Root group `Planet` only, no features. Every probe hits nothing. The one sample
under the old extension, with `"application": "middle-earth"`; see above.

### topology.geotekt (0.5.0)

Root group `Planet` > group `Plates` > `West Points`, `East Points`, and
`Boundary` beside the group.

| Probe      | Expected feature | Colour |
| ---------- | ---------------- | ------ |
| (0, -32.5) | Boundary         | green  |
| (0, 17.5)  | Boundary         | green  |
| (0, 3)     | none             | Earth  |
| (0, -40)   | West Points      | red    |
| (0, 40)    | East Points      | blue   |

The two probes on the boundary sit between markers, where nothing but the
resolved topology is drawn. The one at (0, 3) is in the gap between the two
sections, off the grid, and shows the Earth: the sections are not joined
up. The two on the markers are at vertices the boundary also runs through, and
the marker wins there, so they say the features are still drawn under it.

### craton.geotekt (0.5.0)

Root group `Planet` > group `Cratons` > `Old Shield`, the one outline in the
suite shaped like something real rather than a triangle or a quad on whole
degrees. Twenty-one vertices, so ear clipping gives nineteen triangles, and it
was built to have the parts that are awkward to handle:

- a **bay** cut into the east coast, at vertex `(0, 6)`, so the shape is
  properly concave and a point in the mouth of it is outside the feature;
- a **narrow neck** joining a northern lobe, 4.3 degrees across at its
  narrowest, between the vertices at `(12.5, 4)` and `(11, 8)`;
- a **close pair** of vertices half a degree apart, `(10.4, 25.3)` and
  `(10, 25)`, against a longest edge of 18 degrees, a ratio of 36 to 1.

`Tests/Unit/test_craton_sample.gd` measures each of those, so a sample that
quietly became convex or lost its neck fails rather than going on passing the
probe checks while testing much less than it looks.

The outline is made up rather than traced from a published craton: it was drawn
to have those three awkward parts, and to face the camera in the default view so
that none of it runs off the limb. It spans latitude -22 to 24 and longitude -26
to 26.

`Old Shield` is a `craton`, the first sample feature to name a type at all, and
it keeps the blue the file picks rather than the tan the type would give it. A
saturated colour is what the probe helpers can recognise; the shape is what makes
it craton-like, not the colour.

| Probe      | Expected feature | Where it is                     |
| ---------- | ---------------- | ------------------------------- |
| (-10, -8)  | Old Shield       | deep in the body                |
| (19, 4)    | Old Shield       | the northern lobe               |
| (13, 6)    | Old Shield       | inside the neck                 |
| (2, 19)    | nothing          | the mouth of the bay            |
| (-3, -37)  | nothing          | well clear to the west          |
| (-15.64, -19.48) | Old Shield | out towards the southwest rim, 30° from the middle |

The middle of the outline, which is what the
[Rotate tool](../../Docs/Editing.md#turning-a-feature) turns it about, is at
(3.05, 4.68). The southwest probe is far enough out that a quarter turn about
that middle carries the outline off it: it lies 3.7° inside the outline before
the turn and 4.1° outside it after, which is what `run_rotate_session` reads off
the pixel there.

### motion.geotekt (0.7.0)

Root group `Planet` > group `Plates` > `Drifting Craton`, the fixture for
anything about motion over time: the only sample whose feature has more than one
keyframe, and so the only one whose
[kinematics graphs](../../Docs/Kinematics.md) have anything in them.

The feature is a red quad spanning latitude -12 to 12 and longitude -12 to 12,
plain on purpose: what it is for is the three keyframes, not the outline.

| Ma   | Rotation        | Where it puts the middle |
| ---- | --------------- | ------------------------ |
| 0    | (0, 0, 0)       | (0, 0), where the vertices are |
| 600  | (-30, 10, 0)    | east and a little north  |
| 1400 | (-100, -20, 0)  | further east and south   |

A positive rotation about Y decreases the longitude, so the negative first
angles carry the quad east. The two spans between the three keyframes turn at
clearly different rates — the older one is about twice the younger — so the two
bars of the rate graph cannot be told apart only by where they are.
`Tests/Unit/test_kinematics.gd` checks that they still differ, and the rest of
what the file is for is derived rather than written down here.

| Probe     | Expected feature | Colour              |
| --------- | ---------------- | ------------------- |
| (-4, 5)   | Drifting Craton  | red, `[1, 0, 0, 1]` |
| (5, 40)   | nothing          | not red             |

The probes are at the present, where the first keyframe leaves the quad
unrotated. At any other time it has moved.

### mixed_geometry.geotekt (0.2.0)

Root group `Planet` > group `Shapes`, holding one feature of each geometry kind.
They are laid out so that all of them fit the default view at once, which is what
the `mixed_geometry` golden scene renders.

| Probe       | Expected feature | Kind       | Color                 |
| ----------- | ---------------- | ---------- | --------------------- |
| (-3, 0)     | Red Triangle     | polygon    | red, `[1, 0, 0, 1]`   |
| (0, 40)     | Blue Ridge       | polyline   | blue, `[0, 0, 1, 1]`  |
| (-30, -30)  | Green Stations   | multipoint | green, `[0, 1, 0, 1]` |
| (30, -30)   | Green Stations   | multipoint | green, `[0, 1, 0, 1]` |
| (5, 17)     | nothing          |            | none of the above     |

`Blue Ridge` runs from (-25, 40) to (25, 40). A meridian is a great circle, so the
arc really passes through (0, 40) and a probe can sit there. The rendered tests also
read (3, 33) beside the line and (-27, -33) beside a marker, both far enough off to
show the Earth.

### group_styles.geotekt (0.10.0)

The three features of `mixed_geometry.geotekt`, at the same places, spread
over group styles: root group `Planet` on the feature type style > group
`Continental Crust` on a single colour, `[0.1, 0.6, 0.9, 1]`, holding
`Red Triangle`; group `Cratons` on own colours holding `Blue Ridge`; and
`Green Stations` straight under the root. The root's style in the file is
read and then pinned to own colors on load (GP-0066), so the file is also the
fixture for a root style that no longer counts. Each probe is drawn by a
different rule: the nearest group's single colour, a feature's own color under
a group that says so, and the root's pinned style.

| Probe       | Expected feature | Colour                               |
| ----------- | ---------------- | ------------------------------------ |
| (-3, 0)     | Red Triangle     | Continental Crust's `[0.1, 0.6, 0.9]` |
| (0, 40)     | Blue Ridge       | its own blue, `[0, 0, 1]`            |
| (-30, -30)  | Green Stations   | its own green, `[0, 1, 0]`           |
| (5, 17)     | nothing          | the Earth                            |
