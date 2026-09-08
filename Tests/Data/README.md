# Sample files

Hand-made `.middle-earth` files used as fixtures by the tests. They are written in the
exact format `Document.save_to_file` produces: tab-indented JSON, keys sorted.
See `Docs/Persistence.md` for the formats themselves.

Three of them are still written in **0.1.0**, where a feature stored a flat list of
triangles and no geometry kind. They are the fixtures for `Document.migrate()`, which
recovers the outline those triangles covered, so leave them as they are.
`mixed_geometry.middle-earth` is written in **0.2.0**. None of them carries a
`feature_type`, so all four are fixtures for what 0.3.0 does with an older file:
every feature in one loads unclassified. None of them carries `keyframes` either,
so all four are fixtures for 0.4.0 as well: the one `rotation` a leaf holds
becomes its keyframe at time zero, and one keyframe holds at every time, so the
samples sit where they always did whatever the current time is.

Every polygon is wound counter-clockwise as seen from outside the sphere, which is what
`Feature.ensure_front_winding` enforces on the triangles it derives and what both
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

The same red triangle plus two more features in the `Cratons` group.

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
