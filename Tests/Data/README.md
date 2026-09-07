# Sample files

Hand-made `.middle-earth` files used as fixtures by the tests. They are written in the
exact format `Document.save_to_file` produces: tab-indented JSON, keys sorted, file
format version `0.1.0`. See `Docs/Persistence.md` for the format itself.

Every craton is wound counter-clockwise as seen from outside the sphere, which is what
`Application._ensure_front_winding` enforces when a polygon is drawn and what both
`Planet.hit_test_craton` and the craton shader require. Note that the naive order
(-10, -10), (-10, 10), (10, 0) is the wrong way round; the files use
(-10, -10), (10, 0), (-10, 10).

## Probe points

Coordinates are (latitude, longitude) in degrees. `Tests/Unit/test_sample_files.gd`
checks each of them with `Planet.hit_test_craton`; the rendered tests read the screen
pixel at the same points. (5, 40) stays clear of the graticule, which is drawn on
multiples of 15 degrees.

### triangle.middle-earth

Root group `Planet` > group `Cratons` > `Red Triangle`.

| Probe     | Expected feature | Color               |
| --------- | ---------------- | ------------------- |
| (-3, 0)   | Red Triangle     | red, `[1, 0, 0, 1]` |
| (5, 40)   | nothing          | not red             |

### two_cratons.middle-earth

The same red triangle plus two more features in the `Cratons` group.

| Probe      | Expected feature | Color                 |
| ---------- | ---------------- | --------------------- |
| (-3, 0)    | Red Triangle     | red, `[1, 0, 0, 1]`   |
| (30, 45)   | Blue Quad        | blue, `[0, 0, 1, 1]`  |
| (-3, -60)  | Green Moved      | green, `[0, 1, 0, 1]` |
| (5, 40)    | nothing          | none of the above     |

`Blue Quad` is the quad (20, 30), (40, 30), (40, 60), (20, 60) stored as two triangles.

`Green Moved` holds the same vertices as `Red Triangle` with `rotation` `[60, 0, 0]`.
A positive rotation around Y *decreases* the longitude, so the red probe point (-3, 0)
moves to (-3, -60). The test derives this with `Feature.apply_rotation` rather than
trusting the number written here.

### empty.middle-earth

Root group `Planet` only, no features. Every probe hits nothing.
