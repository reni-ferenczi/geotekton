# Testing

The test suite has five modes. `Tests/run.py` starts all of them.

| Mode       | Command                       | What it covers                                            |
| ---------- | ----------------------------- | --------------------------------------------------------- |
| `headless` | `python Tests/run.py headless` | Pure logic: rotation math, triangulation, hit testing, the file format. No window. |
| `rendered` | `python Tests/run.py rendered` | The real application window: what is drawn, where clicks land, screen to world coordinates. |
| `session`  | `python Tests/run.py session`  | A scripted end-to-end session driving the running application over the automation port. |
| `cli`      | `python Tests/run.py cli`      | What `--version` and `--help` print, from a headless start with no window. |
| `golden`   | `uv run Tests/run.py golden`   | Full window screenshots diffed against reference images. |
| `all`      | `uv run Tests/run.py all`      | All five in the order above, stopping at the first failure. |

`headless`, `rendered`, `session` and `cli` run under any Python 3.13 or newer. `golden`
needs Pillow, so run it through `uv run`; under a plain interpreter without Pillow
it prints a hint and exits with code 2. `uv run Tests/run.py <mode>` works for every
mode, so `uv run` is the safe default.

`headless` and `rendered` accept `--filter=SUBSTRING` to run only the test files
whose name contains the substring, for example
`python Tests/run.py headless --filter=rotation`.

Set the `GODOT` environment variable to use an engine binary other than
`C:\Tools\Godot\Godot_v4.6.2-stable_win64_console.exe`.

## Fresh checkout

`Tests/run.py` imports the project before it starts Godot, so a clean checkout
needs no extra step. The import fills `.godot/` with the imported assets and the
script class cache; without it the textures, scenes and `class_name` scripts are
missing. Only when running Godot by hand, do it once yourself:

```
C:\Tools\Godot\Godot_v4.6.2-stable_win64_console.exe --headless --path . --import --quit
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

Every method named `test_*` is one test. The runner (`Tests/run_tests.gd`) creates a
fresh instance of the test class per method, so tests do not share state. Helper
methods must not start with `test_` or the runner calls them as tests.

Assertions collect failures instead of aborting: `assert_true`, `assert_eq`,
`assert_close` and `fail` append to `TestCase.failures`, so one test method reports
every problem it finds. Never use GDScript's built-in `assert()`, it aborts the run
and is stripped from release builds.

`Tests/session.py`, `Tests/cli.py` and `Tests/golden.py` are Python and can also be
run on their own:

```
python Tests/session.py [--port N]
python Tests/cli.py
uv run Tests/golden.py check|update [--port N]
```

`session.py` runs several scenarios against one launch of the application: the
globe, which checks what is drawn and what a click selects; the document, which
checks New, Open, Save, Save As, the unsaved changes prompt, the recent file list
and a View toggle; drawing, one feature of each geometry kind; and the Properties
panel, which checks what selecting a feature fills in, what an edit does to the
tree row and the globe, what the document refuses, Duplicate and Delete from the
right click menu on the globe, and the Edit menu running the same commands.

The Edit menu scenario copies a feature, so a run puts a `.middle-earth` feature
on the clipboard of whoever is running it.

`cli.py` reads the switch list out of `Logic/cli.gd`, so a new switch that
`--help` forgets to list fails the run.

## Sample files

`Tests/Data` holds hand-written `.middle-earth` files used as fixtures:

| File                      | Contents                                                   |
| ------------------------- | ---------------------------------------------------------- |
| `empty.middle-earth`      | The root group only, no features.                          |
| `triangle.middle-earth`   | One red triangle around lat/lon (-3, 0).                   |
| `two_cratons.middle-earth` | The red triangle plus a blue quad at (30, 45) and a green triangle rotated to (-3, -60). |
| `mixed_geometry.middle-earth` | One feature of each geometry kind: a polygon at (-3, 0), a polyline through (0, 40) and markers at (-30, -30) and (30, -30). |

`Tests/Data/README.md` lists the probe points and the colour expected at each one.
Points near the limb of the globe are lit at a glancing angle and read much
darker than the colour the file asks for, so tests turn the globe to bring a
probe point to the front before reading its pixel.

## Golden images

The references are the PNGs in `Tests/Golden`, each a full 1800x900 window:

| Scene                | File                       | View                       |
| -------------------- | -------------------------- | -------------------------- |
| `triangle`           | `triangle.middle-earth`    | default                    |
| `two_cratons`        | `two_cratons.middle-earth` | default                    |
| `two_cratons_tilted` | `two_cratons.middle-earth` | latitude 30, longitude -45 |
| `empty`              | `empty.middle-earth`       | default                    |
| `mixed_geometry`     | `mixed_geometry.middle-earth` | default                 |

A run launches the application once, loads and renders every scene and compares the
screenshots with the references. Two images are compared per pixel on the largest
absolute channel difference: a pixel counts as different above `PIXEL_TOLERANCE`
(8 out of 255) and a scene fails when more than `MAX_DIFFERENT_FRACTION` (0.002) of
its pixels differ. A failing scene writes its screenshot next to the reference as
`Tests/Golden/<scene>.actual.png`, which is git-ignored.

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
| `get_selected`                       | `feature` with `pnid`, `title`, `enabled`, `feature_type`, `time_range`, `color`, `rotation`, `geometry_kind`, `rings`, `world_rings` and the derived `triangles` |
| `get_properties`                     | `properties`, what the Properties panel is showing and how wide it is, read off its widgets |
| `set_property {field, value}`        | drives one panel field: `name`, `feature_type`, `color`, `enabled`, `time_from`, `time_to` |
| `properties {button, part, index}`   | selects a vertex row and presses `Add` or `Remove` in the panel |
| `get_tool`                           | `tool` (`move` or `draw`), `kind`, whether the kind is locked, the `allowed_kinds` the selected feature's type permits, and how many vertices the shape being drawn holds |
| `set_tool {tool, kind}`              | picks the tool and the geometry kind, refusing what the toolbar itself would not allow |
| `get_time` / `set_time {time}`       | the timeline position                                            |
| `get_view` / `set_view {lat, lon, angle, fov, show_map}` | the globe orientation, camera and map toggle |
| `mouse_move {x, y}`                  | moves the mouse                                                  |
| `click {x, y, button, ctrl}`         | presses and releases a mouse button                              |
| `key {key, ctrl, shift}`             | presses and releases a key                                       |
| `latlon_to_screen {lat, lon}`        | `screen: [x, y]`, or `null` on the far side of the globe         |
| `screen_to_latlon {x, y}`            | `latlon: [lat, lon]`, or `null` off the globe                    |
| `get_pixel {x, y}`                   | `color: [r, g, b, a]` in the range 0 to 1                        |
| `screenshot {path}`                  | writes a PNG and answers `size: [width, height]`                 |
| `get_document`                       | `document` with `path`, `name`, `dirty`, `title`, `can_undo`, `can_redo` |
| `menu {item}`                        | runs a menu item, refusing a disabled one: `new`, `open`, `save`, `save_as`, `preferences`, `quit`, `undo`, `redo`, `cut`, `copy`, `paste`, `duplicate`, `delete`, `features`, `properties`, `timeline`, `status_bar`, `full_screen`, `about` |
| `get_context_menu`                   | `context_menu` with whether the globe right click menu is open and what it offers |
| `context_menu {item}`                | closes that menu and runs one of its items by label |
| `toolbar {button}`                   | presses a feature tree toolbar button by node name, `AddFeature` and the rest |
| `get_panels`                         | `panels`, which of the four panels are shown                     |
| `get_dialog`                         | `dialog` with `name`, `title`, `text` and `buttons`, or `null`   |
| `dialog {button}`                    | presses a dialog button by its label                             |
| `expect_file_dialog {path}`          | answers the next file dialog with a path, or cancels it when empty |
| `get_file_dialog`                    | `file_dialog` with `mode` and `title` of the last one asked for, and forgets it |
| `get_recent` / `open_recent {index}` / `clear_recent` | the recent file list                    |
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
