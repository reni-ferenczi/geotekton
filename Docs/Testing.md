# Testing

The test suite has seven modes, and one more that is run on purpose rather than
on every change. `Tests/run.py` starts all of them.

| Mode       | Command                       | What it covers                                            |
| ---------- | ----------------------------- | --------------------------------------------------------- |
| `headless` | `python Tests/run.py headless` | Pure logic: rotation math, triangulation, hit testing, the file format. No window. |
| `rendered` | `python Tests/run.py rendered` | The real application window: what is drawn, where clicks land, screen to world coordinates. |
| `session`  | `python Tests/run.py session`  | A scripted end-to-end session driving the running application over the automation port. |
| `cli`      | `python Tests/run.py cli`      | What `--version` and `--help` print, from a headless start with no window. |
| `self-check` | `python Tests/run.py self-check` | The runner itself: that it reports a test which hits a runtime error as a failure, and that it fails a run whose application script did not compile. |
| `python`   | `uv run Tests/run.py python`   | The scripting package under pytest: the file model, the API against a fake application, the bridge server and the GPlates import. No engine. |
| `golden`   | `uv run Tests/run.py golden`   | Full window screenshots diffed against reference images. |
| `all`      | `uv run Tests/run.py all`      | All seven in the order above, stopping at the first failure. |
| `performance` | `uv run Tests/run.py performance` | The frame time during playback, and what one hit test costs with and without the bounding cap, on a document of a chosen triangle count. Not part of `all`. |

`headless`, `rendered`, `session`, `cli` and `self-check` run under any Python 3.13
or newer. `self-check` opens a window for the second of its two cases, the way
`rendered` does. `golden` needs Pillow and `python` needs pytest, so run those
through `uv run`; under a plain interpreter without them each prints a hint and
exits with code 2. `uv run Tests/run.py <mode>` works for every mode, so `uv run`
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

`Tests/Python/test_*.py` is the `python` mode: plain pytest over
`src/middle_earth`, with no engine involved. `pythonpath` and `testpaths` are set
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
checks New, Open, Save, Save As, the unsaved changes prompt, the recent file list
and a View toggle; drawing, one feature of each geometry kind; the Properties
panel, which checks what selecting a feature fills in, what an edit does to the
tree row and the globe, a group's style set through the panel, probed on the
globe and undone, what the document refuses, `Key` between two keyframes
leaving the feature where it is and `Delete` working only on a keyframe's time,
Duplicate and Delete from the
right click menu on the globe, and the Edit menu running the same commands; and
time, which moves a feature at two times and reads it back in between.

The time scenario draws a triangle whose middle sits on the equator, so that
turning it about the poles keeps it there and the path between two of its
positions is a stretch of the equator itself. It is moved at one time and again
at another, and halfway between them its middle is halfway along that stretch,
with a pixel probe there showing the feature colour. Outside its time range the
same probe shows the Earth, and widening the range brings it back, so the probe
point is shown to be the right one either way.

The Edit menu scenario copies a feature, so a run puts a `.middle-earth` feature
on the clipboard of whoever is running it. A golden run empties it, for the same
reason: the Paste button of the feature tree toolbar is greyed out by what the
clipboard holds, and an unknown clipboard is a 40 by 40 difference in every
scene.

The styling scenario probes what each draw style paints on the globe, reads a
palette out of a `.cpt` file and a malformed one out of another, switches each
class of geometry off through the View menu and checks that only its own class
left the screen, then saves the document and reads the whole styling back; see
[Styling](Styling.md).

The circle scenario builds a circle twice over: from a centre and a point
on the rim, and from three points on the rim with the centre never clicked. Both
give the same centre and radius back, the polygon holds one vertex per segment
and the polyline one more, every committed vertex is checked against the
angular radius it was asked for, and both features come out typed as a Circle.
The segment count is set in the Move tool, where its box is hidden, and the
Circle tool shows the box and cuts the circle into that many.

The projection scenario asks each of the six views — the globe and the five
map projections — where the red triangle is, probes the pixel there, reads the
place back out of it and clicks it, so a projection whose forward and inverse
disagree fails on the pixel and one the shader draws differently fails on the
click. It then steps the zoom in and out, types one in, resets it, turns the
view each way and resets the camera, checking the toolbar fields follow.

The scene scenario edits every setting of the scene block, saves the document,
reads it back and checks each one survived, with the backdrop image beside the
project so the path in the file is the relative one. It then drags the light
with the Light tool and probes that the planet is brightest under where the drag
ended, and finally stores the block as the default, checks that a new document
starts from it and that an opened file wins over it, and puts the preferences
back so the scenarios after it open the documents they expect.

The topology scenario builds a line topology by clicking two drawn polylines
with the Topology tool, reverses one section from the panel, moves one of the
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
`run_snap_session` drops a vertex a few pixels from one belonging to another
feature, with snapping on and then off; `run_measure_session` reads a distance
off the status bar and checks it against the arc it was told to measure, on two
planet radii; `run_split_session` cuts a polygon in two between two vertices and
checks that both halves kept the type, the colour, the time range and the
keyframes; and `run_split_tool_session` picks the Split tool on the craton
sample, checks the planet did not move, takes a point back with Ctrl+Z, has a
cut that crosses the edge refused with the reason in the status bar, then cuts
the craton along three points. It checks one undo version, two features holding
the original vertices once and the cut twice, a blue pixel inside each half,
and that undo brings back the one outline.

The Python scenarios run last against the interpreter the application started.
`run_python_session` builds a feature and two keyframes entirely from the
console and then asks the port what the document holds, so the check is the
application's own answer rather than the script's; it plays and pauses from the
console, types a block over two lines, walks the history with the arrow keys and
completes a name the session made a moment before. `run_script_menu_session`
drops a script in a scratch directory, adds it to the preferences, rescans and
runs it from the menu and from a path, and checks that a file without a
docstring is not listed. `run_bad_interpreter_checks` points the preferences at
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
itself, because the planet lights what it draws and lets the Earth texture
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

`Tests/Data` holds hand-written `.middle-earth` files used as fixtures:

| File                      | Contents                                                   |
| ------------------------- | ---------------------------------------------------------- |
| `empty.middle-earth`      | The root group only, no features.                          |
| `triangle.middle-earth`   | One red triangle around lat/lon (-3, 0).                   |
| `craton.middle-earth`     | One blue outline of 21 vertices with a bay, a narrow neck and a close pair, facing the camera. Written in the current format. |
| `topology.middle-earth`   | Two multipoints on the equator and a line topology running along both, with a gap between the two sections. Written in the current format. |
| `Backdrops/quarters.*`    | The same four coloured quarters as a PNG, a JPEG, a WebP and an SVG, for the backdrop image. |
| `two_cratons.middle-earth` | Three features despite the name: the red triangle plus a blue quad at (30, 45) and a green triangle rotated to (-3, -60). See `Tests/Data/README.md`. |
| `mixed_geometry.middle-earth` | One feature of each geometry kind: a polygon at (-3, 0), a polyline through (0, 40) and markers at (-30, -30) and (30, -30). |
| `group_styles.middle-earth` | The same three features under group styles: the polygon in a group on a single colour, the polyline in a group on own colours, and the markers under a root on the feature type style. Written in the current format. |
| `motion.middle-earth`     | One red quad with three keyframes, which is the fixture for anything about motion over time. Written in the current format. |
| `Palettes/*.cpt`          | A continuous, a discrete, a categorical and a malformed colour palette table. |

`Tests/Data/Backdrops` holds a `.gdignore`, like `Tests/Golden`: the images
there are read from disk at run time by `Backdrop.load_from()`, never imported
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
root group on the Feature age style over the two colour ramp. Standing still
comes first so that what playback adds can be told apart from what drawing that
much geometry costs whether anything moves or not. The third reading is what
recoloring every feature on every frame adds; it is reported, not held against
a budget. The numbers come from the engine's own
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
| `triangle`           | `triangle.middle-earth`    | default                    |
| `two_cratons`        | `two_cratons.middle-earth` | default                    |
| `two_cratons_tilted` | `two_cratons.middle-earth` | latitude 30, longitude -45 |
| `empty`              | `empty.middle-earth`       | default                    |
| `mixed_geometry`     | `mixed_geometry.middle-earth` | default                 |
| `craton`             | `craton.middle-earth`      | default                    |
| `map_rectangular`    | `two_cratons.middle-earth` | the map, rectangular       |
| `map_mercator`       | `two_cratons.middle-earth` | the map, Mercator          |
| `map_mollweide`      | `two_cratons.middle-earth` | the map, Mollweide         |
| `map_robinson`       | `two_cratons.middle-earth` | the map, Robinson          |
| `map_orthographic`   | `two_cratons.middle-earth` | the map, orthographic      |
| `scene_no_stars`     | `two_cratons.middle-earth` | the star field off, over a blue background |
| `scene_light_east`   | `empty.middle-earth`       | the light 45° to the east  |
| `scene_light_high`   | `empty.middle-earth`       | the light high to the west, with ambient |
| `scene_backdrop`     | `empty.middle-earth`       | the backdrop image at full opacity |
| `scene_backdrop_half`| `empty.middle-earth`       | the same image at half     |
| `kinematics`         | `motion.middle-earth`      | default, with the kinematics panel up, the feature selected and the time at 500 Ma |

`two_cratons.middle-earth` holds three features and no globe view shows all of
them: the default one has the green feature as a sliver at the limb, and the
tilted one carries the blue one off the far side. The map scenes show all three,
since a projection draws the whole planet at once. `Tests/Data/README.md` has
the pixel counts and says which view to write a check against.

The five map scenes are what says the inverse projection in the shader agrees
with the one in `MapProjection`: a graticule drawn through the wrong inverse is
wrong everywhere at once, which no tolerance hides.

A scene states more than its view: whether the kinematics panel is up, what is
selected and what the time is. Loading a document clears the selection and puts
the time back to the present, so a scene only has to name what it wants beyond
that, and no scene depends on the one before it.

A scene that wants its own view settings is rendered from a copy of the sample
with the block already in the file, written into the run's temporary folder.
Setting them through the dialog would leave the document dirty, and a dirty
document writes a marker into the title and the status bar, which would be the
only difference between half the references.

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
| `load {path}`                        | loads a `.middle-earth` file, absolute path                      |
| `get_features`                       | `features`, the whole tree as `pnid`, `title`, `is_group`, `depth` |
| `select {title\|pnid}`               | selects a feature; `title: null` or `pnid: -1` selects the root  |
| `get_selected`                       | `feature` with `pnid`, `uuid`, `title`, `enabled`, `feature_type`, `time_range`, `color`, `rotation`, `geometry_kind`, `rings`, `world_rings`, the derived `triangles` and, on a line topology, its `sections` with what each one resolved to |
| `get_properties`                     | `properties`, what the Properties panel is showing and how wide it is, read off its widgets, with the `types` the type selector offers and, on a feature with motion, `keyframes`: the `count` and whether `key` and `delete` can be pressed. On a group, its `style` (`mode`, `color`, `opacity` 0 to 100, `palette`, `ramp_from`, `ramp_to` and `ramp_span`) and the `styles` and `palettes` its selectors offer |
| `set_property {field, value}`        | drives one panel field: `name`, `feature_type`, `color`, `opacity` (0 to 100), `enabled`, `time_from`, `time_to`, and on a group `style`, `palette`, `ramp_from`, `ramp_to` and `ramp_span`, where `color` and `opacity` are the style's |
| `keyframes {button}`                 | presses `Key` or `Delete` in the panel's keyframe row, both of which work at the current time |
| `sections {button, index}`            | selects a section row of a line topology and presses `Reverse` or `Remove` in the panel |
| `get_tool`                           | `tool` (`move`, `draw`, `vertex`, `measure` or `circle`), `kind`, whether the kind is locked, the `allowed_kinds` the selected feature's type permits, how many vertices the shape being drawn holds, the Vertex tool's `selected_vertex`, `split_from`, `snapping`, `can_split` (whether its `S` would split now), whether the Split tool is offered (`split_enabled`) and its `split_points`, the Measure tool's `measure_points` and its `measure_label` (text, visibility and window position) and the Circle tool's `circle_points`, `segments`, whether that box is shown (`segments_visible`) and the `circle` its clicks describe |
| `set_tool {tool, kind, snap, segments}` | picks the tool (`move`, `draw`, `vertex`, `measure`, `circle`, `topology`, `light` or `split`), the geometry kind, the snap switch and the segment count, refusing what the toolbar itself would not allow |
| `vertex {action}`                    | what the Vertex tool does without a mouse: `split_from`, `split` or `delete`. Picking and dragging go through `press`, `mouse_move` and `release`, since picking is the thing being checked |
| `get_status`                         | `status` with the three status bar fields: `coordinates`, `measure` and `file` |
| `get_preferences` / `set_preferences {preferences}` | the settings the Preferences dialog holds, driven through its own fields; only the keys given are changed. `get_preferences` also reports the `default_view`, the `view_defaults` and the `style_defaults` a new document starts from |
| `get_view_settings` | `view_settings`, the scene block the open document carries, `style`, the root group's style the same dialog edits, `backdrop_error`, why the image it names is not on the planet, and `palette_errors`, what could not be read of the palette the root names |
| `set_view_settings {view_settings, button}` | drives the View settings dialog through its own fields; only the keys given are changed. The root group's style is set through the dialog's `draw_style`, `single_color`, `opacity`, `palette`, `ramp_from`, `ramp_to` and `ramp_span` fields. `hidden_classes` goes through the View menu switches instead, since that is where they are. `button` presses `SaveAsDefault` or `RestoreDefaults` |
| `get_time` / `set_time {time}`       | the current time of the document, an age in millions of years    |
| `get_timeline`                       | the slider and its range, the typed time, whether it is playing, the skip, the keyframe markers with where each is on screen, and the animation settings |
| `get_kinematics`                     | `kinematics`, what the motion graphs hold: the `span` they cover, the `samples` of the path, one entry per `segments` between two keyframes, what both come to at the current time, and where the `cursor` is drawn across the plotting area |
| `timeline {button}`                  | presses a time control button: `Play`, `Pause`, `Reset`, `Older`, `Younger`, `OlderKeyframe`, `YoungerKeyframe`, `Configure` |
| `set_animation {animation}`          | changes the animation settings the dialog holds, refusing what cannot be played; only the keys given are changed |
| `set_skip {skip}`                    | types a skip into the box beside the timeline's `<` and `>` buttons |
| `get_performance`                    | the frame rate, how much there is to draw, and whether it is playing |
| `get_view` / `set_view {lat, lon, angle, zoom, show_map, projection}` | where the camera looks, how far it is zoomed in, and whether the globe or one of the five map projections is drawn. `get_view` also reports the derived `fov`, the `window_size` and what the view toolbar fields read |
| `view {button}` / `view {projection}` | presses a view toolbar button (`zoom_in`, `zoom_out`, `zoom_reset`, `rotate_clockwise`, `rotate_anticlockwise`, `camera_reset`), or picks a view in the projection selector: `"globe"` or the number of a projection |
| `mouse_move {x, y}`                  | moves the mouse                                                  |
| `click {x, y, button, ctrl}`         | presses and releases a mouse button: `left`, `right`, `middle`, `wheel_up` or `wheel_down` |
| `press {x, y, button}` / `release {x, y, button}` | half a click each, so a drag can be scripted: press, `mouse_move`, release |
| `key {key, ctrl, shift}`             | presses and releases a key                                       |
| `latlon_to_screen {lat, lon}`        | `screen: [x, y]`, or `null` where the view does not draw that place: the far side of the globe, or a latitude the projection leaves off the map |
| `screen_to_latlon {x, y}`            | `latlon: [lat, lon]`, or `null` where there is no planet under the pixel |
| `get_pixel {x, y}`                   | `color: [r, g, b, a]` in the range 0 to 1                        |
| `screenshot {path}`                  | writes a PNG and answers `size: [width, height]`                 |
| `get_document`                       | `document` with `path`, `name`, `dirty`, `title`, `can_undo`, `can_redo` and `undo_depth`, the number of versions applied, so a run can check that an edit recorded exactly one |
| `benchmark_hit_test {samples}`       | `hit_test` with the microseconds one hit test costs with and without the bounding caps; see [Frame time](#frame-time) |
| `menu {item}`                        | runs a menu item, refusing a disabled one: `new`, `open`, `import`, `save`, `save_as`, `run_script`, `preferences`, `quit`, `undo`, `redo`, `cut`, `copy`, `paste`, `duplicate`, `delete`, `features`, `properties`, `timeline`, `kinematics`, `console`, `status_bar`, `view_settings`, `full_screen`, `about`, `skip_older`, `skip_younger`, `keyframe_older`, `keyframe_younger`, and `polygons`, `polylines`, `points`, `circles` and `topologies`, the geometry class switches |
| `get_context_menu`                   | `context_menu` with whether the globe right click menu is open and what it offers |
| `context_menu {item}`                | closes that menu and runs one of its items by label |
| `toolbar {button}`                   | presses a feature tree toolbar button by node name, `AddFeature` and the rest |
| `get_panels`                         | `panels`, which of the six panels are shown                      |
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
| `set_clipboard {text}`               | puts text on the clipboard, so a run can state what Paste is greyed out by |
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
