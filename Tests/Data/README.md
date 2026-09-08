# Sample files

Hand-made `.middle-earth` files used as fixtures by the tests. They are written in the
exact format `Document.save_to_file` produces: tab-indented JSON, keys sorted.
See `Docs/Persistence.md` for the formats themselves.

Four of the five are fixtures for the older formats. Three are still written in
**0.1.0**, where a feature stored a flat list of
triangles and no geometry kind. They are the fixtures for `Document.migrate()`, which
recovers the outline those triangles covered, so leave them as they are.
`mixed_geometry.middle-earth` is written in **0.2.0**. None of those four carries
a `feature_type`, so all four are fixtures for what 0.3.0 does with an older
file: every feature in one loads unclassified. None of them carries `keyframes`
either, so all four are fixtures for 0.4.0 as well: the one `rotation` a leaf
holds becomes its keyframe at time zero, and one keyframe holds at every time, so
the samples sit where they always did whatever the current time is.

`craton.middle-earth` is the exception and is written in the current **0.4.0**:
rings, a geometry kind, a feature type and a keyframe list, nothing to migrate.
It is the fixture for a file the application saved rather than one it had to
recover.

Every polygon is wound counter-clockwise as seen from outside the sphere, which is what
`Feature.faces_outwards` enforces on the triangles it derives and what both
`Planet.hit_test` and the geometry shader require. Note that the naive order
(-10, -10), (-10, 10), (10, 0) is the wrong way round; the files use
(-10, -10), (10, 0), (-10, 10).

## Probe points

Coordinates are (latitude, longitude) in degrees. `Tests/Unit/test_sample_files.gd`
checks each of them with `Planet.hit_test`; the rendered tests read the screen
pixel at the same points. The clear probes stay off the graticule, which is drawn on
multiples of 15 degrees.

### triangle.middle-earth (0.1.0)

Root group `Planet` > group `Cratons` > `Red Triangle`.

| Probe     | Expected feature | Color               |
| --------- | ---------------- | ------------------- |
| (-3, 0)   | Red Triangle     | red, `[1, 0, 0, 1]` |
| (5, 40)   | nothing          | not red             |

### two_cratons.middle-earth (0.1.0)

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

Root group `Planet` only, no features. Every probe hits nothing.

### craton.middle-earth (0.4.0)

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

### mixed_geometry.middle-earth (0.2.0)

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
