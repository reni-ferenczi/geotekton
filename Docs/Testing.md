# Testing

The test suite has seven modes, and one more that is run on purpose rather than
on every change. `Tests/run.py` starts all of them.

| Mode       | Command                       | What it covers                                            |
| ---------- | ----------------------------- | --------------------------------------------------------- |
| `headless` | `python Tests/run.py headless` | Pure logic: rotation math, triangulation, hit testing, the file format. No window. |
| `rendered` | `python Tests/run.py rendered` | The real application window: what is drawn, where clicks land, screen to world coordinates. |
| `session`  | `uv run Tests/run.py session`  | A scripted end-to-end session driving the running application over the automation port. |
| `cli`      | `python Tests/run.py cli`      | What `--version` and `--help` print, from a headless start with no window. |
| `self-check` | `python Tests/run.py self-check` | The runner itself: that it reports a test which hits a runtime error as a failure, and that it fails a run whose application script did not compile. |
| `python`   | `uv run Tests/run.py python`   | The scripting package under pytest: the file model, the API against a fake application, the bridge server and the GPlates import. No engine. |
| `golden`   | `uv run Tests/run.py golden`   | Full window screenshots diffed against reference images. |
| `all`      | `uv run Tests/run.py all`      | All seven in the order above, stopping at the first failure. |
| `performance` | `uv run Tests/run.py performance` | The frame time during playback, and what one hit test costs with and without the bounding cap, on a document of a chosen triangle count. Not part of `all`. |

`headless`, `rendered`, `cli` and `self-check` run under any Python 3.13 or
newer. `self-check` opens a window for the second of its two cases, the way
`rendered` does. `session` and `golden` need Pillow and `python` needs pytest, so
run those through `uv run`; under a plain interpreter without them each prints a
hint and exits with code 2. `session` reads the pictures it exported back with
Pillow, which is what puts it on that list. `uv run Tests/run.py <mode>` works for every mode, so `uv run`
is the safe default.

`session` starts a Python interpreter of its own, because the application it
launches does. `headless` and `rendered` do not: the application only starts one
when it is the scene that was started, and a test runner hosting it is not that.
See [Scripting](Scripting.md).

`headless` and `rendered` accept `--filter=SUBSTRING` to run only the test files
whose name contains the substring, for example
`python Tests/run.py headless --filter=rotation`.

`performance` takes `--triangles=N` (default 5000) and `--budget=MS` (default
one frame at 60 frames a second). See [Frame time](#frame-time).

Set the `GODOT` environment variable to use an engine binary other than
`C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe`.

## Fresh checkout

`Tests/run.py` imports the project before it starts Godot, so a clean checkout
needs no extra step. The import fills `.godot/` with the imported assets and the
script class cache; without it the textures, scenes and `class_name` scripts are
missing. Only when running Godot by hand, do it once yourself:

```
C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --import --quit
```

## The principle

Rendering is verified by pixel probes and image diffs, never by a person looking at
a screenshot. A test states the colour it expects at a lat/lon and the port answers
with the pixel; a golden run states that the window is unchanged and the diff
answers with a number. The only time anyone looks at an image is when the golden
references are regenerated on purpose, and even then only to approve the new
references once.

## How the tests are structured

GDScript tests live in two directories and are discovered by file name:

- `Tests/Unit/test_*.gd` — headless mode, extend `TestCase`.
- `Tests/Rendered/test_*.gd` — rendered mode, extend `RenderedCase`, which extends
  `TestCase` and adds helpers for loading a sample file, turning the globe, reading
  pixels and injecting clicks.

`Tests/Rendered/test_sea_floor.gd` splits a square with Ridge and Crust on and
checks that the ridge and crusts have no rows, that one is selected with no row
selected, that Cut, Copy and Duplicate refuse it and Delete takes it to its
half, that a click on a band selects the crust, and that a red square over a
band draws red with the crust at the top of the tree. It also draws the bands
band by band in Blue and in Rainbow, and the ridge in a changed ridge color. Last, it
cuts the eastern half at 50 Ma across its crust to the ridge, turns one piece
away, and checks at 25 Ma that crust, not the planet, is drawn between the two
pieces.

`Tests/Rendered/test_feature_tree.gd` drags tree rows with the mouse. While a
drag is on, Godot finds the control under it from the real pointer rather than
from injected motion, so that test moves the system pointer with
`Input.warp_mouse`. Moving the mouse during a rendered run can break those
tests.

`Tests/Python/test_*.py` is the `python` mode: plain pytest over
`src/geotekt`, with no engine involved. `pythonpath` and `testpaths` are set
in `pyproject.toml`, so `uv run pytest` from the project root finds them.

The [import](Import.md) tests are the one place a test reads something this
repository does not carry. Feature collections and rotation files that mean
anything are far too large to keep here, so those tests read the ones an
installed GPlates brings with it, at `GPLATES_GEODATA` or the default install
directory, and are skipped when there is none. Everything they could check
without that — the type mapping, the geometry kinds, the time ranges, the
sampling, the project archive — is checked against data the tests build
themselves, so a machine with no GPlates still runs almost all of them.

Every method named `test_*` is one test. The runner (`Tests/run_tests.gd`) creates a
fresh instance of the test class per method, so tests do not share state. Helper
methods must not start with `test_` or the runner calls them as tests.

Do not declare a script level `static var` in a rendered test. On Godot 4.6.2 it
made the engine segfault during shutdown, after every test had passed and the
summary had been printed, so the run failed with nothing to point at. Godot 4.7.2
no longer crashes, but the teardown is still wrong: the same file leaks 168
`ObjectDB` instances and 38 resources, which the engine reports as errors on its
way out. A `const` array of `Vector2`, turned into a `PackedVector2Array` where it
is used, does the same job without any of it. The file is quiet when it is the
only one being run, which is what makes this easy to miss; `Tests/Unit` is
unaffected. See GP-0025.

Do not connect a signal in a `.tscn` from a node of an instanced child scene,
such as a button of `feature_tree_toolbar.tscn` from `features.tscn`. The
text loader keeps the connection, so it works from the editor; the export
converts the scene to binary and drops it, so the button is dead in a release
build and nothing reports it. Connect it from the script in `_ready()`.
`Tests/Unit/test_scene_connections.gd` fails the headless run on any such
connection. See GP-0110.

Assertions collect failures instead of aborting: `assert_true`, `assert_eq`,
`assert_close` and `fail` append to `TestCase.failures`, so one test method reports
every problem it finds. Never use GDScript's built-in `assert()`, it aborts the run
and is stripped from release builds.

A runtime error is different: the engine prints it, abandons the method and
returns, leaving the failure list empty. The runner registers a `Logger` through
`OS.add_logger` and turns every script and shader error printed during a test
into a failure of that test, so a method that stops halfway cannot report `PASS`.

What the setup prints is read the moment the setup is over and reported against
`setup`, and no test is run after that. A script the application scene depends
on failing to compile arrives this way. The engine hands back what it did
manage to compile rather than nothing, so the window still comes up and the
tests used to run against it and pass, which is what GP-0029 was. Anything
printed later but outside a test, by the discovery or by work a test left
running after it returned, is reported against `run`.

Warnings and engine level errors are left alone. An engine error is not always
a defect and not always the run's doing: `DisplayServer.clipboard_get()`, which
the Edit menu calls to decide whether Paste is available, reports one whenever
another process holds the clipboard.

`Tests/session.py`, `Tests/cli.py`, `Tests/self_check.py` and `Tests/golden.py` are
Python and can also be run on their own, and so is `Tests/Python` under pytest:

```
python Tests/session.py [--port N]
python Tests/cli.py
python Tests/self_check.py
uv run pytest
uv run Tests/golden.py check|update [--port N]
```

`session.py` runs several scenarios against one launch of the application: the
globe, which checks what is drawn and what a click selects; the document, which
checks New, Open, Save, Save As, the unsaved changes prompt, the recent file list,
a View toggle and that a new or opened document opens at the oldest age of the
animation; drawing, one feature of each geometry kind; the Properties
panel, which checks what selecting a feature fills in, that `From` is the older
end of the time range and `To` the younger, that a feature added at 1500 Ma
exists from 1500 Ma to the present, what an edit does to the
tree row and the globe, a group's style set through the panel, probed on the
globe and undone, what the document refuses, `Key` between two keyframes
leaving the feature where it is and `Delete` working only on a keyframe's time,
Duplicate and Delete from the
right click menu on the globe, and the Edit menu running the same commands;
coupling, described below; and time, which moves a feature at two times and
reads it back in between.

The coupling scenario opens `two_cratons.geotekt` and couples the blue quad
to the red triangle at 500 Ma. It checks the span, that the quad did not move,
one undo version, the panel's rows, the bar on the timeline and that the planet
stayed where it was. At 200 Ma it drags the triangle and checks that the quad
moved with it and kept its distance, decouples the quad there, and drags the
triangle again to check that the quad now stays. At 350 Ma, inside the span, it
drags the quad itself, which lands where it was dropped. Coupling the triangle
to the quad is refused as a cycle with the reason in a dialog; deleting the
triangle leaves the span listed as broken and undo mends it. It then saves,
loads, removes the span, and checks that undo, redo and undo give the spans
back each time.

The pick checks arm the pointer on the Follow row and click the planet with
it. A click on the ocean, shown to be empty by a pixel probe first, leaves the
pointer armed with the reason in the status bar; a click on the green craton
names it in the picker and puts the pointer away, with the selection, the tool
and the globe where they were; `Couple` then follows what was clicked; and
Escape puts an armed pointer away too.

Last it opens the sample again for the
[cut in time](Time.md#a-coupling-edit-is-a-cut-in-time). The triangle is dragged
at 1000 and at 0 Ma, so it turns the whole way through, and the quad is coupled
to it at 900 Ma. A quad that is not dragged keeps its distance from the triangle
exactly, at 800, 700, 600 and 500 Ma. Dragging the quad at 200 Ma moves it
against the triangle over all of that stretch; decoupling at 500 Ma then drops
the keyframe at 200 Ma, leaves the distance at each of those times as the drag
left it, and the quad holds its world pose from 500 Ma to the present. Pixel
probes at 900 and 500 Ma show each feature drawn at the middle its world
vertices give.

The time scenario draws a triangle whose middle sits on the equator, so that
turning it about the poles keeps it there and the path between two of its
positions is a stretch of the equator itself. It is moved at one time and again
at another, and halfway between them its middle is halfway along that stretch,
with a pixel probe there showing the feature colour. Outside its time range the
same probe shows the planet, and widening the range brings it back, so the probe
point is shown to be the right one either way.

The icon scenario picks a glyph for a feature through the panel and reads the
picture the tree row is actually showing, not the field behind it: `get_features`
answers with the stem of the row's texture, so a row that kept the rule icon
fails there. It saves, loads, undoes and redoes, and checks that a glyph nobody
offers and a group are both refused.

The feature color preference checks draw a green polygon in a new group,
then set the Polygon color to blue through `set_preferences`. A new feature's
Colour row and swatch are blue, the old polygon's swatch stays green, the
group on the Feature type style paints the old polygon blue at an off-grid
probe, and a right click on its swatch gives it blue. The `CatalogColors`
button then puts green back in `get_preferences` and on the planet, which
is also what leaves the preferences as a golden run expects them.

The line width checks that follow select the polygon and the multipoint of the
mixed geometry sample and find no `line_width` in the panel, then the line,
which shows 1 with its tooltip. The line is made magenta and a probe 1.6
degrees off its middle reads the planet, since the shader draws 0.69 degrees
to either side; `line_width` 4 through `set_property` is one undo step, the
feature reports the width and the same probe now reads the line, lighter for
being selected, and undo takes both back. The default line width checks change
the preference through `set_preferences`, find a new feature typed Line
starting at it, the same feature keeping its width when the preference moves
on and the next feature starting at the new value, and put the preference
back to what it was.

The Edit menu scenario copies a feature, so a run puts a `.geotekt` feature
on the clipboard of whoever is running it. It then presses Ctrl+C and Ctrl+V
with the feature tree focused and finds the pasted copy in the tree, and presses
Ctrl+A and Ctrl+C in the focused Name field and reads the name, not the feature,
back from the clipboard. Nothing in a golden scene depends on the clipboard.

The styling scenario first checks that the View settings dialog refuses the six
style fields it used to have and that the root has nothing to edit. It then sets
each draw style on the group holding the three features and probes what it
paints on the globe. It loads a palette from a `.cpt` file through that group's
Load button, and a malformed one the same way, which names its bad lines in an
error dialog. It switches each class of geometry off through the View menu and
checks that only its own class left the screen. Last it saves the document,
checks that the root's style in the file is the pinned one, and reads the
group's styling back; see [Styling](Styling.md).

The circle scenario draws circles with the Draw tool on a feature typed
Circle. A fresh feature arms Draw for a polygon, with the Segments box hidden;
picking the Circle type keeps Draw armed and `get_tool` reports `drawing:
"circle"`. The tool strip has no Circle button, the port has no `circle` tool,
C picks nothing and D arms Draw again, which shows the box. A circle is built
from a centre and a point on the rim and, in a later document, from three
points on the rim with the centre never clicked. Both give the same centre and
radius back. The committed polyline holds one vertex more than it has segments,
every vertex is checked against the angular radius it was asked for, the
feature stays a Circle and Move comes back. The segment count is set in the
Move tool, where its box is hidden, and the circle is cut into that many. On
the committed circle the panel keeps the keyframe row and hides the coupling
rows, which `get_properties` reports with `hidden: true`, and `coupling` is
refused with "A circle follows nothing." A polygon added beside it is not
offered the circle in its picker, and a pick click on the rim says "A circle
carries nothing." and leaves the pointer armed. A third click followed by a
right click leaves the centre and rim describing the circle again.

After the commit, `get_properties` reports the stored `circle`: its center is
the first click, its radius reaches the second, its segment count is the
toolbar's and Axis circles is off. The Vertex tool is not offered on it.

The axis circles scenario types an empty feature as Circle and checks that it
holds nothing yet, while the panel shows the circle rows with the auroral
defaults, the box off and no Area row. Changing the radius and the segment
count through the panel draws the circle, one undo version each, and the Vertex
tool is not offered. Pick axis arms the Pole tool with its cross on the axis;
Escape gives the pick up, and a click moves the axis to the clicked point and
brings Move back. Ticking Axis circles is one undo version and adds the ring
around the antipode: the rim and a vertex of the far ring are probed for the
Circle color, with the circle still selected, since the highlight is a halo
beside the line and leaves the line its own color. Unticking is one more
version, and the same pixel no longer shows that color. With the box ticked again, a Pole tool drag writes a keyframe, and
both world rings sit the radius from the turned axis and its antipode. A second
pick on the turned feature lands the circle around the point clicked, and undo
puts it back. A feature holding a line cannot become a Circle, the refusal is
shown in a dialog, and `set_property` refuses `polar` on it.

The hotspot scenario draws a plate at 100 Ma, keys it at 30 Ma and drags it
east at the present, then draws a second plate that never moves. A new feature
typed Hotspot, with the Move tool armed, holds nothing, arms the Draw tool, and
the status bar tells the user to click. It shows the Plate and Step (My) rows,
offering both plates and the pointer, without the keyframe, coupling and Area
rows. One click
on the moved plate is one undo version that places the hotspot there and makes
that plate its plate, Draw stays armed, and the mark is a ring a degree around
the click whose pixel is probed for the type's color. At a Skip of 50 the
100 My track has three samples; `set_skip` to 20 gives six and to 10 twice
as many steps, eleven samples, the oldest as far from the hotspot as the plate
moved. A color set through the panel is what a pixel on the track shows while
the hotspot is still selected. A Step (My) of 20 set through `set_property` is
one undo version and leaves six samples whatever the Skip is set to after it,
on the globe as well as in the panel; undo puts the step back to 0 and the
count follows the Skip again. At 10 Ma the track has ten vertices, and at
100 Ma there is no track. A second click, off both plates, is one more version
that moves the hotspot and keeps its plate, and Escape leaves Draw. The Vertex,
Rotate and Pole tools are refused on it, a Move drag leaves it where it is and
Paste Shape says why it will not. The Plate row's pointer arms the pick, a
click on nothing leaves it on, and a click on the second plate makes that the
plate in one version and ends the pick; Escape ends it too. Taking the plate
away is one version, undo brings it back, and `set_property` still refuses the
`track_step` that 0.22.0 took away. The first plate cannot become a hotspot.
Last it checks that the hotspot takes no part in coupling: the panel reports no
coupling at all, `coupling` is refused with "A hotspot follows its plate.", a
polygon added beside it is not offered the hotspot in its picker, and a pick
click on the mark says "A hotspot carries nothing." and leaves the pointer
armed.

The projection scenario asks each of the six views — the globe and the five
map projections — where the red triangle is, probes the pixel there, reads the
place back out of it and clicks it, so a projection whose forward and inverse
disagree fails on the pixel and one the shader draws differently fails on the
click. It then steps the zoom in and out, types one in, zooms out as far as it
goes, turns the view each way and resets the camera, checking the toolbar fields follow.

The export scenario writes pictures of the two cratons sample and reads them
back with Pillow. On the globe the menu item is greyed out and the command says
to pick a map projection, and nothing is written. In the rectangular projection
a 720 wide export is 720 by 360, all three features are drawn where the
projection puts them, no pixel of the four edges is the colour the window's own
panels are drawn in, and the corners are the polar ice the map has there, since
a rectangular sheet reaches all four of them. Each of the five projections is
exported in turn and comes out at the size its own extent asks for. The
rectangular picture has no transparent pixel. The
Mollweide picture says the sheet is not letterboxed: its corners are
transparent, with neither the background nor a star in them, while the ends of
both axes and the middle are opaque sheet. The Export width preference is read at its default of 3600, set to
400, and an export that names no width comes out 400 by 200. Afterwards the
zoom, the field of view, the camera, the projection and the window are all where
they were before.

The video scenario makes videos of the same sample. Nothing in it moves, so the
green craton is given 1950 Ma as the age it appears at and the frames have to
show the difference. The ffmpeg preference is pointed at a file that is not
there, which is how a machine says it has no encoder: an export of 2000 to 1900
Ma at 100 My a second and ten frames a second then leaves eleven 240 by 120
PNGs in a folder named after the video and no video, the first frame is not the
last, the craton is missing from the first and drawn in the last, and every
frame is opaque. The time and the view are where the export found them
afterwards. A video of the globe comes out square and opaque, the background
around the globe included. The globe itself cannot be exported as a picture, so
the rendered test `test_scene.gd` checks transparency there: it calls
`PlanetView.render_export()` on the globe and on all five projections with the
star field on, and checks that a corner outside the planet has alpha 0, that the
middle has alpha 255, and that a rectangular or Mercator sheet has no clear
pixel. It also checks that an opaque export keeps the background and that the
view draws opaque again, with its stars, afterwards. An export started with `wait: false` is watched through
`get_export` and stopped with `cancel_export`, which leaves neither frames nor
file. Last the preference is cleared so the application looks for an ffmpeg of
its own: where it finds one the video is on disk and not empty and the frames
are gone, and where it does not the eleven frames are what is checked, since the
suite may not depend on this machine having an encoder.

The scene scenario edits every setting of the scene block, saves the document,
reads it back and checks each one survived, with the raster beside the
project so the path in the file is the relative one. Built in Earth then puts
the shipped image on the planet, which is saved as its `res://` path rather than
made relative, and a planet color given with an alpha comes back opaque. It then
checks that the tool strip has no Light button, raises the light to 60 degrees
through the View settings elevation field, which is one undo version, and probes
that the north of the globe is now brighter than the south, and the other way
round at -60 degrees. Finally it stores the block as the default, checks that a new document
starts from it and that an opened file wins over it, and puts the preferences
back, with no raster, so the scenarios after it open the documents they expect.

The topology scenario types an empty feature as Topology, which leaves Move
armed, and checks that the tool strip has no Topology button. It presses the
section table's Pick toggle, which arms the Topology tool, clicks one drawn
polyline and ends the pick with Escape, which lets the toggle go; it arms the
tool again through `set_tool`, clicks the second polyline and picks another
tool, which lets the toggle go too. It then reverses one section from the panel, moves one of the
two at a later time and reads back a resolved geometry that has followed it, and
then deletes that feature to check that the section is reported as broken rather
than dropped and that an undo mends it.

The kinematics scenario shows the panel from the View menu, selects the moving
feature and checks what the graphs hold: the span they cover, that the path runs
from the oldest end to the youngest, that there is one rate per pair of
keyframes, and that the place and the rate at the current time agree with where
the globe has actually drawn the feature. It then moves the time and checks that
the cursor lands at that fraction across the plotting area, selects the group to
check the panel empties, and hides the panel again. See
[Kinematics](Kinematics.md).

The vertex scenarios come last: `run_vertex_session` drags a vertex, inserts one
on an edge and deletes one, all at a time that has moved the feature away from
where its vertices are stored, so an edit that forgot to map the click back into
the feature's own frame would be caught even though the globe looked right;
`run_vertex_delete_checks` Ctrl+clicks a vertex of a square, which leaves a
triangle that one undo turns back into the square, and Ctrl+clicks an edge,
which does nothing. It presses the physical Delete key with the pointer on a
vertex, which takes the vertex out and leaves the feature in the tree. A
Ctrl+click on the triangle is refused with the reason in the status bar, and
Delete with no vertex held deletes the feature;
`run_snap_session` checks that the tool strip has no Snap button and drops a
vertex a few pixels from one belonging to another feature, with snapping on and
then off; `run_draw_from_geometry_session` has
the Draw tool snap a point onto a vertex, take a pasted triangle as held points
and trace along a hexagon with Shift+click, switches snapping off with
`menu item=snap_to_vertices` while the Draw tool is armed, and checks that
Shift+click is then a plain click. Both switch snapping through the Edit menu; `run_measure_session` reads a distance
off the status bar and checks it against the arc it was told to measure, on two
planet radii, carries the path on to a third point, where the status bar names
the last segment beside the total and the label sits at that segment's
midpoint, finishes it with Enter and starts another with the next click, and
turns the Parallel switch on to check that a click two degrees short of 60° N
lands on the parallel and that the run along it is measured, 5003.8 km rather
than the great circle's 4604, with the flags read back from
`get_tool.measure_parallel` and the switch off again after the tool is left; `run_area_session` draws a ten degree square and checks its
area and share on the two lines of the Area row and in the status bar, and the planet's area in the
Preferences dialog and the root group's sentence, at 6371 and at 3000 km, then
draws a line and checks that it has no Area row;
`run_split_session` cuts a polygon in two between two vertices and
checks that both halves kept the type, the colour, the time range and the
keyframes; and `run_split_tool_session` picks the Split tool on the craton
sample, checks the planet did not move, takes a point back with Ctrl+Z, has a
cut that crosses the edge refused with the reason in the status bar, then cuts
the craton along three points. It checks one undo version, two features holding
the original vertices once and the cut twice, a blue pixel inside each half,
and that undo brings back the one outline.

`run_ridge_session` cuts the same craton at 400 Ma with the Ridge switch on
and Crust off. It
checks that the switch is shown with the tool alone, that the cut and the ridge
are one undo version, that the status bar names all three features, and that the
ridge is a midway topology there from 400 Ma to the present, with no keyframes
or couplings, whose two sections name the halves, the second walked back. The
panel says `Midway between two sides` and has the section table but no
Coupled to row or Closed switch, and a Pick click on a half leaves the ridge
with two sections and a status bar saying why. Every
vertex of the ridge is on both halves at the cut. The second half is then held
with a keyframe at 400 Ma and dragged 24 degrees away at the present, and at
200 Ma, where the two are about 12 degrees apart, each ridge vertex is within a
degree of the great circle midpoint of the matching vertices on the two halves.
The pixels say the same: the ridge's own crimson in the middle of the gap and
the craton's blue a couple of degrees inside either edge of it. Three undos
leave the one craton.

`run_crust_session` draws a square at 100 Ma and picks the Split tool with
Ridge off, where the Crust switch is shown but greyed out and refuses to be
turned on. With both on, one cut leaves five features in one undo version,
the two halves, the ridge and one crust per half, and the status bar names all
five. Each crust is a topology from the split to the present whose panel line
reads `Crust of Plate, 0 chunks`, with no area, no section table and no Closed
switch. Both halves are keyed at the split and dragged apart at the present.
The skip is then set to 25 My; the application reads the user's configuration,
so the scenario puts the old skip back at the end. Each crust then has four
chunks, an area, and four band rings of six vertices, two isochrons each. A pixel
inside each band reads the age ramp: the band against the continent is the
crust's steel blue, the one against the ridge is that lightened by 55 percent of
the way to white, and each band between is lighter than the one before it. A
pixel on the 75 Ma isochron is its lines' light steel blue. The pointer is moved
away for all of them, so no hover highlight is read. A crust has no row in the
feature tree, so a click on its second band is what selects it. A skip of 50 My leaves two chunks. A Step (My) of
25 on the first crust, which is one undo version, brings its four bands back
and holds them through a skip of 10, while the other half, still at 0, follows
that skip to ten bands; undo puts the first one back on the skip. Last, a topology clicked together from two
lines fills nothing until the Closed switch is set through `set_property`,
which is one undo version, gives one ring of four, shows the Area row, which
the open topology did not have, and fills the square between the lines in the Topology
color. A line has no Closed switch.

`run_split_children_session` draws a magenta range, then a square plate below
it in the tree, at 200 Ma, and couples the range to the plate. At 100 Ma it
turns the Split tool's Children switch off and on, checking it is shown with
the tool alone, and cuts both along the crust scenario's line. The cut is one
undo version, the tree reads `Range`, `Range 2`, `Plate`, `Plate 2`, and the
status bar names all four. The two pieces follow different halves, one of them
still the original. Both halves are keyed at the split and dragged apart at the
present. Each piece moves as far as the half it follows did, a pixel at its
middle is magenta, and the pixel where the cut ran through the range is no
longer magenta. Five undos leave the range and the plate.

`run_copy_shape_session` copies the shape of `Blue Quad` on the two cratons
sample and pastes it into a feature added for it. It checks that Copy Shape
records nothing and says what it took, that the paste records one version, arms
the Vertex tool and lands the same number of vertices on the same world points
the original holds, that a second paste appends a second part and two undos
leave the feature as empty as the paste found it, and that the copy, given a
colour of its own and probed with the original switched off, paints the middle
of the quad. A Line feature already holding a polyline then refuses the polygon
shape, with the reason in the status bar and nothing recorded.

`run_rotate_session` turns the sample craton, first about its own middle and
then about a pole. `R` picks the Rotate tool and a drag from a point out towards
the rim turns the craton a quarter of the way about its middle: the status bar
says so, one version is recorded, one keyframe is written, the middle is where
it was to within half a degree, the pixel there is still the craton's blue and
the pixel out towards the rim is not. Undo puts the craton back over that point.
`P` then picks the Pole tool, a click west of the craton places the pole, and a
drag turns the craton about it; where the middle lands is held against the place
the same turn about the same pole gives it, worked out in the test, and probed
on the globe. Escape takes the pole away. Last it presses each tool key in turn,
checks that the key of a tool the toolbar greys out does nothing, and neither
do L and T, and types
three of those letters into the name field, which takes them as characters and
leaves the tool alone.

The Python scenarios run last against the interpreter the application started.
`run_python_session` builds a feature and two keyframes entirely from the
console and then asks the port what the document holds, so the check is the
application's own answer rather than the script's; it plays and pauses from the
console, types a block over two lines, walks the history with the arrow keys and
completes a name the session made a moment before. `run_script_menu_session`
drops a script in a scratch directory, adds it to the preferences, rescans and
runs it from the menu and from a path, and checks that a file without a
docstring is not listed. `run_export_from_console` exports a picture from the prompt, checks that
`app.export_image` answers with the size and that the file is on disk, and that
the globe is refused as an `AppError` a script can catch. It then exports a two
frame video of the globe, which is not refused, and checks the frame count it
answers with and that a video or the frames of one were left.
`run_bad_interpreter_checks` points the preferences at
a path that is not an interpreter and checks that the reason reaches the console
and that the application carries on. `run_no_python_session` launches a second
application with `--no-python` and checks it comes up with no interpreter, no
port and a dead prompt, while the scripts are still listed. See
[Scripting](Scripting.md).

`run_import_session` writes a GPlates feature collection holding one plate's
outline and a rotation file that moves it, imports both from File > Import and
checks the tree it built, that the document opens Untitled and unsaved, and that the outline is
drawn where `pygplates` reconstructs it at fifty million years and where it
stands at the present day. The probes go by hue rather than by the colour
itself, because the planet lights what it draws and lets the raster beneath
through, which lifts every channel towards white. See [Import](Import.md).

`cli.py` reads the switch list out of `Logic/cli.gd`, so a new switch that
`--help` forgets to list fails the run. It also runs `--help-command` in both of
its forms against a script the project ships and checks that what it prints is
the docstring in the file.

`Tests/Unit/test_shader_constants.gd` reads `planet.gdshader` as text and holds
the numbers it carries twice — the Robinson tables, the extent of the Robinson
sheet, the edge slack and the number of each projection — against
`MapProjection`. Nothing in either file makes the other follow, so a change to
one alone fails there rather than as a map drawn slightly wrong.

`self_check.py` runs the runner twice over `Tests/SelfCheck`, once per case.
The first holds one deliberately broken test beside an intact one, and checks
that the run fails with the broken one reported as a failure and the intact one
still passing. The second hosts `broken_application.tscn` instead of the
application, whose script depends on one that does not compile, and checks that
the parse error is reported against `setup` and that the intact test beside it
is not reported as passed. That folder is reached with the runner's
`--dir=res://...` switch and is never discovered by `headless` or `rendered`;
the stand-in scene is reached with `--scene=res://...`.

## Sample files

`Tests/Data` holds hand-written `.geotekt` files used as fixtures:

| File                      | Contents                                                   |
| ------------------------- | ---------------------------------------------------------- |
| `empty.geotekt`           | The root group only, no features.                          |
| `triangle.geotekt`   | One red triangle around lat/lon (-3, 0).                   |
| `craton.geotekt`     | One blue outline of 21 vertices with a bay, a narrow neck and a close pair, facing the camera. Written in the current format. |
| `topology.geotekt`   | Two multipoints on the equator and a line topology running along both, with a gap between the two sections. Written in the current format. |
| `Rasters/quarters.*`      | The same four colored quarters as a PNG, a JPEG, a WebP and an SVG, for the raster. |
| `two_cratons.geotekt` | Three features despite the name: the red triangle plus a blue quad at (30, 45) and a green triangle rotated to (-3, -60). See `Tests/Data/README.md`. |
| `mixed_geometry.geotekt` | One feature of each geometry kind: a polygon at (-3, 0), a polyline through (0, 40) and markers at (-30, -30) and (30, -30). |
| `group_styles.geotekt` | The same three features under group styles: the polygon in a group on a single colour, the polyline in a group on own colours, and the markers straight under a root whose style in the file says feature type, which the loader pins to own colors. Written in 0.10.0. |
| `motion.geotekt`     | One red quad with three keyframes, which is the fixture for anything about motion over time. Written in the current format. |
| `Palettes/*.cpt`          | A continuous, a discrete, a categorical and a malformed colour palette table. |

`Tests/Data/Rasters` holds a `.gdignore`, like `Tests/Golden`: the images
there are read from disk at run time by `Raster.load_from()`, never imported
as project resources, so the engine has no business with them.

`Tests/Unit/test_palette.gd` also reads every `.cpt` file under
`../gplates/sample-data`, the sibling checkout of the GPlates sources, when it is
there. They are read where they lie rather than copied in: they are GPL and this
project is MIT. The fixtures in `Tests/Data/Palettes` use every part of the
format those files use, so the reader is covered whatever else is on the machine.

`Tests/Data/README.md` lists the probe points and the colour expected at each one.
Points near the limb of the globe are lit at a glancing angle and read much
darker than the colour the file asks for, so tests turn the globe to bring a
probe point to the front before reading its pixel.

## Frame time

`uv run Tests/run.py performance` builds a document of a given triangle count,
every feature of it moving between two keyframes, and reports the frame time
three times: standing still, playing the animation, and playing again with the
group that holds every feature on the Feature age style over the custom ramp. Standing still
comes first so that what playback adds can be told apart from what drawing that
much geometry costs whether anything moves or not. The third reading is what
recoloring every feature on every frame adds; it is reported, not held against
a budget. A fourth plays a copy of the document in which every feature but the
first [follows the first](Time.md#coupling) over the whole animation, which is
what resolving every rotation through a parent adds. It is reported the same
way. The numbers come from the engine's own
counters, never from how the animation looks.

It is not part of `all`, because a frame time depends on the machine and on what
else it is doing. The engine's processor time counter is not reported either:
reading it is a request per frame, and the port traffic turned out larger than
the work being measured.

What it found on the development machine is in
[Shader](Shader.md#measured): 60 frames a second holds to about 2,000
triangles, playing costs almost nothing over standing still, and the limit is
the per-fragment loop over the triangles rather than anything the time control
does.

The same run then hit tests two thousand points spread over the whole globe,
twice: once against the [bounding caps](Shader.md#the-bounding-cap) the geometry
was built with, and once against caps widened to the whole sphere, which is what
the hit test faced before there were any. Widening a cap is not a switch put in
for the benchmark; a feature spanning more than a hemisphere gets exactly that
cap. The run fails if the caps do not make the hit test at least five times
faster.

## Golden images

The references are the PNGs in `Tests/Golden`, each a full 1800x900 window:

| Scene                | File                       | View                       |
| -------------------- | -------------------------- | -------------------------- |
| `triangle`           | `triangle.geotekt`    | default                    |
| `two_cratons`        | `two_cratons.geotekt` | default                    |
| `two_cratons_tilted` | `two_cratons.geotekt` | latitude 30, longitude -45 |
| `empty`              | `empty.geotekt`       | default                    |
| `mixed_geometry`     | `mixed_geometry.geotekt` | default                 |
| `craton`             | `craton.geotekt`      | default                    |
| `map_rectangular`    | `two_cratons.geotekt` | the map, rectangular       |
| `map_mercator`       | `two_cratons.geotekt` | the map, Mercator          |
| `map_mollweide`      | `two_cratons.geotekt` | the map, Mollweide         |
| `map_robinson`       | `two_cratons.geotekt` | the map, Robinson          |
| `map_orthographic`   | `two_cratons.geotekt` | the map, orthographic      |
| `scene_no_stars`     | `two_cratons.geotekt` | the star field off, over a blue background |
| `scene_light_east`   | `empty.geotekt`       | the light 45° to the east  |
| `scene_light_high`   | `empty.geotekt`       | the light high to the west, with ambient |
| `scene_raster`       | `empty.geotekt`       | the raster at full opacity |
| `scene_raster_half`  | `empty.geotekt`       | the same image at half, over the planet color |
| `planet_colour`      | `empty.geotekt`       | no raster, the planet in a brown of its own |
| `kinematics`         | `motion.geotekt`      | default, with the kinematics panel up showing the rate row only, the feature selected and the time at 500 Ma |

`two_cratons.geotekt` holds three features and no globe view shows all of
them: the default one has the green feature as a sliver at the limb, and the
tilted one carries the blue one off the far side. The map scenes show all three,
since a projection draws the whole planet at once. `Tests/Data/README.md` has
the pixel counts and says which view to write a check against.

The five map scenes are what says the inverse projection in the shader agrees
with the one in `MapProjection`: a grid drawn through the wrong inverse is
wrong everywhere at once, which no tolerance hides.

A scene states more than its view: whether the kinematics panel is up, what is
selected and what the time is. Loading a document clears the selection and puts
the time at the [oldest age](Time.md#the-time-control) the animation covers, so
a scene only has to name what it wants beyond that, and no scene depends on the
one before it. Only `kinematics` names a time of its own; the other nineteen
references show the timeline at 2000 Ma.

A scene that wants its own view settings is rendered from a copy of the sample
with the block already in the file, written into the run's temporary folder.
Setting them through the dialog would leave the document dirty, and a dirty
document writes a marker into the title and the status bar, which would be the
only difference between half the references. A copy whose block names the
raster is written in the current format: the samples are older than 0.17.0,
and a file that old naming no raster opens wearing the built in Earth, which
`planet_colour` must not.

Every sample is older than 0.17.0, so every scene that says nothing about the
raster shows the built in Earth, as it did before the planet had a color of its
own.

A run launches the application once, loads and renders every scene and compares the
screenshots with the references. Two images are compared per pixel on the largest
absolute channel difference: a pixel counts as different above `PIXEL_TOLERANCE`
(8 out of 255) and a scene fails when more than `MAX_DIFFERENT_FRACTION` (0.002) of
its pixels differ. A failing scene writes its screenshot next to the reference as
`Tests/Golden/<scene>.actual.png`, which is git-ignored.

`Tests/Golden` holds a `.gdignore`, so the engine leaves the whole folder
alone. The references are read by `Tests/golden.py` in Python and never by the
engine, and without it every one of them would be imported as a texture, with a
`.png.import` file beside it and a compressed copy under `.godot/imported` that
churned whenever the references were regenerated.

Every `check` run ends with a negative control: the fresh `triangle` screenshot is
compared with the `empty` reference and has to fail. If that comparison ever
passes, the diff has gone blind and the whole run fails, whatever the scenes said.

To regenerate the references after an intended visual change:

```
uv run Tests/golden.py update
```

Look at the PNGs once to confirm they show what the change intended, then
commit them. They are reviewed in the pull request that changes them.

## The automation port

The application opens a test automation port when started with the user argument
`--automation-port=<port>`:

```
Godot ... --path . -- --automation-port=45455
```

It listens on 127.0.0.1, accepts one client and exchanges newline delimited JSON:
one request object per line, one response object per line, handled one at a time.
A response is `{"ok": true, ...}` or `{"ok": false, "error": "..."}`.
`Tests/automation_client.py` wraps this: `launch_app(port)` starts the application
and `AutomationClient(port).call(cmd, **params)` sends one command and raises on an
error response. Commands that change the scene await two frames before answering, so
a round trip is also a wait for the screen to catch up.

| Command                              | Answers with                                                     |
| ------------------------------------ | ---------------------------------------------------------------- |
| `ping`                               | `version`, the application version                               |
| `load {path}`                        | loads a `.geotekt` file, absolute path                      |
| `get_features`                       | `features`, the whole tree as `pnid`, `title`, `is_group`, `depth` and `row_icon`, the glyph id or else the file stem of the picture the row is showing, and for a feature `swatch`, the color its row's swatch shows |
| `select {title\|pnid}`               | selects a feature; `title: null` or `pnid: -1` selects the root  |
| `get_selected`                       | `feature` with `pnid`, `uuid`, `title`, `enabled`, `feature_type`, `time_range`, `color`, `line_width`, `rotation`, `keyframes`, `couplings`, `geometry_kind`, `rings`, `world_rings`, the derived `triangles` and, on a topology, its `sections` with what each one resolved to |
| `get_properties`                     | `properties`, what the Properties panel is showing and how wide it is, read off its widgets, with the `types` the type selector offers, the `icon` the feature carries and the `icons` the selector offers, whether the colour picker is open (`color_picker_open`) and the `color_presets` it offers, the `time_range` in the file's order, the `time_from` and `time_to` the two boxes show with their `tooltips`, on a feature drawn with lines the `line_width` its row shows, with its tooltip among the `tooltips`, the `area_km2` the feature's polygon encloses (0 for anything else) and, while the Area row is shown, its two line text as `area`, and, on a feature with motion, `keyframes`: the `count` and whether `key` and `delete` can be pressed, and `coupling`: the `caption` of the row with the picker, what it is `coupled_to` now, the `parents` the picker offers and the `parent` it shows, whether `couple`, `decouple`, `remove` and the `pick` pointer can be pressed, whether the pointer is `picking`, and the `spans` listed with whether each is `broken`, and `hidden`, true on a Circle, whose panel shows no coupling rows. A Hotspot has no keyframe row either, so nothing is reported under `coupling` for one at all. A Circle adds `circle`: whether Axis circles is ticked (`polar`), the `axis`, `radius` and `circle_segments` the rows show and whether `pick_axis` can be pressed. A topology, or a feature typed Topology, adds `closed`, whether its Closed switch is on, and `picking_sections`, whether its section Pick toggle is pressed. A hotspot adds `hotspot`: the `position`, the `plate` and the `plates` offered, the number of track `samples` at the current time and step, the `time_step` the Step row shows, whether the Plate pointer can be pressed (`pick`) and whether it is on (`picking`); `position` is null until the Draw tool places the hotspot. A crust adds `crust_chunks`, how many bands it has, and `crust_step`, the same Step row. On the root, the `placeholder` sentence and the `planet_area_km2`. On a group, its `style` (`mode`, `color`, `opacity` 0 to 100, `palette`, `ramp_colors` and `ramp_span`), the `style_label` the Style selector shows and its `tooltips` entry `style`, and the `styles` and `palettes` its selectors offer |
| `set_property {field, value}`        | drives one panel field: `name`, `feature_type`, `icon` (a glyph id or empty for none), `color`, `opacity` (0 to 100), `enabled`, `time_from` (the older end of the time range) and `time_to` (the younger one), on a Circle `polar` (the Axis circles box), `axis` (`[lat, lon]`), `radius` and `circle_segments`, on a hotspot `plate` (a title, or `None`), on a hotspot or a crust `time_step` (0 to 1000 My, 0 for the timeline's Skip), on a feature drawn with lines `line_width` (0.1 to 10, a multiple of what its type draws at), on a topology `closed`, and on a group `style`, `palette`, `ramp_colors` (a list of two colours or more) and `ramp_span`, where `color` and `opacity` are the style's |
| `keyframes {button}`                 | presses `Key` or `Delete` in the panel's keyframe row, both of which work at the current time |
| `coupling {button, parent, index, pick}` | presses `Couple` with the `parent` picked by title, `Decouple`, both at the current time, or `Remove` on the span at `index` in the panel's list. `pick: true` arms the pointer instead, so the next `click` on the planet names the parent, and `pick: false` puts it away. Refused on a feature typed Circle with "A circle follows nothing." and on one typed Hotspot with "A hotspot follows its plate." |
| `sections {button, index}`            | selects a section row of a topology and presses `Reverse` or `Remove` in the panel, or flips the `Pick` toggle, which arms or ends the Topology tool; refused while the panel does not show the button |
| `get_tool`                           | `tool` (`move`, `rotate`, `pole`, `draw`, `vertex`, `measure`, `topology` or `split`), the node names of what the tool strip holds (`tool_strip`), the Pole tool's `pole` as `[lat, lon]` or null, whether that click is picking the axis of a circle (`picking_axis`), whether the Move tool drags the selection (`move_enabled`), how many vertices the shape being drawn holds (`drawing_vertices`), what the Draw tool draws (`drawing`: `"circle"` on a feature typed Circle, `"hotspot"` on a hotspot, otherwise the kind it commits, `polygon`, `polyline` or `multipoint`; null in any other tool), which of the two drawing tools the selected feature's type offers (`draw_enabled`, `topology_enabled`), the Vertex tool's `selected_vertex`, `split_from`, `snapping` (Edit > Snap to vertices), `can_split` (whether its `S` would split now), whether the Split tool is offered (`split_enabled`), its `split_points`, whether they are a cut it refused and draws in red (`split_refused`), its `ridge` switch and whether that switch is shown (`ridge_visible`), its `crust` switch, whether that one is shown (`crust_visible`) and whether it can be pressed (`crust_enabled`), its `children` switch and whether that one is shown (`children_visible`), the Measure tool's `measure_points`, the `measure_parallel` flag of each of them, saying whether the segment ending there follows a parallel, its `measure_label` (text, visibility and window position), its `parallel` switch and whether that switch is shown (`parallel_visible`), and, for a circle being drawn, its `circle_points` (empty otherwise), the `segments` count, whether that box is shown (`segments_visible`) and the `circle` the clicks describe |
| `set_tool {tool, segments, ridge, crust, children, parallel}` | picks the tool (`move`, `rotate`, `pole`, `draw`, `vertex`, `measure`, `topology` or `split`; any other name is refused as an unknown tool), the segment count, the Split tool's Ridge, Crust and Children switches, Crust refused while Ridge is off, and the Measure tool's Parallel switch, refusing what the toolbar itself would not allow. `topology` has no button: it is refused unless a feature typed Topology is selected, and arms the tool the way the section Pick toggle does. Snapping is switched with `menu item=snap_to_vertices`. What the Draw tool produces, a circle included, comes from the feature's type, which `set_property` sets |
| `vertex {action}`                    | what the Vertex tool does without a mouse: `split_from`, `split` or `delete`. Picking and dragging go through `press`, `mouse_move` and `release`, since picking is the thing being checked |
| `get_status`                         | `status` with the three status bar fields: `coordinates`, `measure` and `file` |
| `get_preferences` / `set_preferences {preferences, button}` | the settings the Preferences dialog holds, driven through its own fields, `export_width`, `ffmpeg`, `default_line_width`, `rate_unit` (`cm_per_year` or `km_per_my`) and `feature_colors` (type id to `[r, g, b, a]`) among them; only the keys given are changed. `button` names a button of the dialog to press first, such as `CatalogColors`. `get_preferences` also reports the `feature_colors` in effect for every type, the `default_view` and the `view_defaults` a new document starts from, the `planet_area_km2` the radius gives and the `planet_area_label` the dialog shows under the radius box |
| `get_view_settings` | `view_settings`, the scene block the open document carries, and `raster_error`, why the image it names is not on the planet |
| `set_view_settings {view_settings, button}` | drives the View settings dialog through its own fields; only the keys given are changed. A key the dialog has no field for is refused with `no view setting called`, including the six style fields it once had (`draw_style`, `single_color`, `opacity`, `palette`, `ramp_colors`, `ramp_span`); a group's style is set with `set_property`. `hidden_classes` goes through the View menu switches instead, since that is where they are. `button` presses `SaveAsDefault`, `RestoreDefaults`, `BuiltInEarth` or `ClearRaster`. The `planet_color` field keeps a color opaque whatever alpha it is given. `crust_palette` takes `blue`, `rainbow` or `ramp`, and `crust_ramp_colors` a list of at least two colors |
| `get_time` / `set_time {time}`       | the current time of the document, an age in millions of years    |
| `get_timeline`                       | the slider and its range, the typed time, whether it is playing, the skip, the keyframe markers with where each is on screen, the `couplings` bars of the selected feature with both ends and where the bar is drawn, and the animation settings |
| `get_kinematics`                     | `kinematics`, what the motion graphs hold: the `span` they cover, the `samples` of the path, one entry per `segments` between two keyframes, what both come to at the current time, what the top of the rate row reads (`peak_labels`), and where the `cursor` is drawn across the plotting area |
| `timeline {button}`                  | presses a time control button: `Play`, `Pause`, `Reset`, `Older`, `Younger`, `OlderKeyframe`, `YoungerKeyframe`, `Configure` |
| `set_animation {animation}`          | changes the animation settings the dialog holds, refusing what cannot be played; only the keys given are changed |
| `set_skip {skip}`                    | types a skip into the box beside the timeline's `<` and `>` buttons |
| `get_performance`                    | the frame rate, how much there is to draw, and whether it is playing |
| `get_view` / `set_view {lat, lon, angle, zoom, show_map, projection}` | where the camera looks, how far it is zoomed in, and whether the globe or one of the five map projections is drawn. `get_view` also reports the derived `fov`, the `window_size` and what the view toolbar fields read |
| `view {button}` / `view {projection}` | presses a view toolbar button (`zoom_in`, `zoom_out`, `rotate_clockwise`, `rotate_anticlockwise`, `camera_reset`), or picks a view in the projection selector: `"globe"` or the number of a projection |
| `mouse_move {x, y}`                  | moves the mouse                                                  |
| `click {x, y, button, ctrl, shift}`  | presses and releases a mouse button: `left`, `right`, `middle`, `wheel_up` or `wheel_down`, with Ctrl or Shift held if asked |
| `press {x, y, button}` / `release {x, y, button}` | half a click each, so a drag can be scripted: press, `mouse_move`, release |
| `key {key, ctrl, shift}`             | presses and releases a key. A printable key carries its character too, so a focused text field types it |
| `focus {widget\|release}`             | `focus`, the node name of whatever holds the keyboard focus, after giving it to the named widget or letting it go. Single key shortcuts read the focus, so a run has to be able to set it |
| `latlon_to_screen {lat, lon}`        | `screen: [x, y]`, or `null` where the view does not draw that place: the far side of the globe, or a latitude the projection leaves off the map |
| `screen_to_latlon {x, y}`            | `latlon: [lat, lon]`, or `null` where there is no planet under the pixel |
| `get_pixel {x, y}`                   | `color: [r, g, b, a]` in the range 0 to 1                        |
| `screenshot {path}`                  | writes a PNG and answers `size: [width, height]`                 |
| `export_image {path, width}`         | File > Export Image without the dialog: writes the map at the current age and answers `size: [width, height]`. A width of zero or none is the Export width preference; refused while the globe is shown |
| `export_video {path, from, to, speed, fps, width, wait}` | File > Export Video without the dialogs: renders the animation and answers `frames`, `encoded`, `cancelled`, `path` and `folder`, the folder the frames were left in when no ffmpeg was found. Whatever is left out is the animation's own setting. `wait: false` starts the export and answers at once, so the run can watch it |
| `get_export`                         | `export` with whether one is `running`, how many `frames` are done of the `total`, whether it was `cancelled` and the `result` the last one answered with |
| `cancel_export`                      | stops a running export at its next frame                         |
| `get_document`                       | `document` with `path`, `name`, `dirty`, `title`, `can_undo`, `can_redo` and `undo_depth`, the number of versions applied, so a run can check that an edit recorded exactly one |
| `benchmark_hit_test {samples}`       | `hit_test` with the microseconds one hit test costs with and without the bounding caps; see [Frame time](#frame-time) |
| `menu {item}`                        | runs a menu item, refusing a disabled one: `new`, `open`, `import`, `save`, `save_as`, `export_image`, `export_video`, `run_script`, `preferences`, `quit`, `undo`, `redo`, `cut`, `copy`, `paste`, `duplicate`, `delete`, `copy_shape`, `paste_shape`, `snap_to_vertices` (a check item, which the command flips), `features`, `properties`, `timeline`, `kinematics`, `kinematics_place`, `highlight_children`, `console`, `status_bar`, `view_settings`, `full_screen`, `about`, and `polygons`, `polylines`, `points`, `circles` and `topologies`, the geometry class switches |
| `get_context_menu`                   | `context_menu` with whether the globe right click menu is open and what it offers |
| `context_menu {item}`                | closes that menu and runs one of its items by label |
| `properties {button}`                | presses a button of the Properties panel by node name, such as `LoadPalette` on a group's Palette row, refusing one the panel does not show, and flips a toggle such as `PickPlate` the way a click does |
| `toolbar {button}`                   | presses a feature tree toolbar button by node name, `AddFeature` and the rest |
| `swatch {title\|pnid, button}`        | presses the colour swatch of a feature's tree row, opening the groups above it first and checking that the swatch is under the point before it presses. A `left` press selects the feature and opens the picker, a `right` one puts the type's default colour back |
| `get_panels`                         | `panels`, which of the six panels are shown, `kinematics_place`, whether the kinematics panel graphs latitude and longitude, and `highlight_children`, whether the View menu highlights children |
| `get_python`                         | `python` with the interpreter's `state`, the `reason` it is not running, the `interpreter` path, the `port` it was given and whether it is `ready` |
| `get_console`                        | `console` with whether the panel is `visible`, the `prompt`, what is typed in it, whether it is `editable`, the whole `transcript` and the `history` |
| `console {line}`                     | types one line at the prompt and answers when the interpreter has finished with it, with the `transcript` and the `prompt` it left behind |
| `console_clear`                      | empties the transcript, so a check reads only what came after it |
| `console_recall {step}`              | the Up and Down arrows at the prompt; answers with the `input` they left |
| `console_complete {source}`          | types `source` and presses Tab; answers with the `completions` and the `input` |
| `get_scripts` / `rescan_scripts`     | the script catalog behind File > Scripts, as `name`, `title`, `doc` and `path`, and a reread of the configured directories |
| `run_script {name\|path}`            | runs one script, by catalog name or by path, and answers when it has finished, with the `transcript` |
| `get_dialog`                         | `dialog` with `name`, `title`, `text` and `buttons`, or `null`   |
| `dialog {button}`                    | presses a dialog button by its label                             |
| `expect_file_dialog {path\|paths}`    | answers the next file dialog with a path, or with several for the Import dialog, or cancels it when neither is given |
| `get_file_dialog`                    | `file_dialog` with `mode` and `title` of the last one asked for, and forgets it |
| `get_recent` / `open_recent {index}` / `clear_recent` | the recent file list                    |
| `get_clipboard` / `set_clipboard {text}` | `text`, what the clipboard holds, and a way to put text there, so a run can read what Ctrl+C copied and state what the Edit menu's Paste is greyed out by |
| `quit`                               | closes the application                                           |

A run with the port open starts from a fixed shell: the window geometry, the
panel visibility and the last file are neither restored nor remembered, and the
settings go to a scratch folder instead of the config file of whoever is at the
keyboard. File dialogs do not open either; `expect_file_dialog` answers the next
one and `get_file_dialog` reports what was asked for, which is how a script can
tell that Save As asks for a path and Save on an open file does not.

Screen coordinates are window pixels in a 1800x900 window, so what
`latlon_to_screen` returns can be passed straight to `click`, `get_pixel` and
`screen_to_latlon`. Pick a port other than the one another run is using; the drivers
default to 45455 (`session.py`) and 45456 (`golden.py`) and both take `--port`.
