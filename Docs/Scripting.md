# Scripting

Python drives the application from a console under the globe, from a script file
run out of the File menu, and from scripts that live in a folder and turn up as
menu entries of their own. The same package also reads and writes
`.middle-earth` files on its own, with nothing running.

The interpreter is a separate process. Nothing Python does can take the window
down with it, the interpreter can be replaced or upgraded without rebuilding
anything, and `--no-python` leaves it out of a run altogether. What that costs is
a round trip per call, which no scripting session here notices.

## Getting to it

| Where                   | What it does                                             |
| ----------------------- | -------------------------------------------------------- |
| View > Console          | The prompt under the globe                                |
| File > Run Script...    | Pick a `.py` file and run it against the open document    |
| File > Scripts          | One entry per documented script in the configured folders |
| `--help-command NAME`   | Print what one of those scripts does, without opening a window |
| `--no-python`           | Start with no interpreter and a dead console              |

The console panel starts hidden and stays where it is put, like the other
panels; see [Shell](Shell.md#menus). Running a script brings it up, since a
script that prints has nowhere else to say it.

## The console

`>>>` takes one line at a time. A line that could still be continued is answered
with `...` and held until the statement is closed by an empty line, so a `for`
or a `def` can be typed out as it would be anywhere else. Escape throws away an
unfinished statement.

Up and Down walk back through the lines already typed; past the newest the
prompt is empty again. Tab completes the word under the caret. One answer
finishes the word, several are listed and the beginning they share is filled in.

Completion is served by the interpreter rather than by the application, so it
knows about `rodinia` a moment after `rodinia = app.features[0]` was typed, and
about anything the session has imported.

What a script prints arrives as it is printed, not when the line finishes, so a
loop that reports its progress reports it while it runs. An error is shown as
the traceback it is and the session carries on with everything it had.

## The API

A script finds the running application as `app`, along with `Document`,
`Feature` and `Keyframe` for working on files. `app` holds nothing itself: every
property asks the application again, so a script always sees what is on screen.

```python
uuid = app.add_feature("Rodinia", rings=[[(0.0, 0.0), (0.0, 10.0), (10.0, 0.0)]],
                       feature_type="craton")
app.set_keyframe(uuid, 0.0, (0, 0, 0))
app.set_keyframe(uuid, 600.0, (-30, 10, 0))
app.time = 600.0
app.play()
```

### The document

| Call                | What it does                                                  |
| ------------------- | ------------------------------------------------------------- |
| `app.document`      | The whole document as a `Document`, the way a file holds it    |
| `app.features`      | Every feature in it, groups left out                           |
| `app.find(uuid)`    | One node by uuid, `None` when there is none                    |
| `app.named(title)`  | The first node with that title                                 |
| `app.name`          | What the window title says the document is called              |
| `app.new()`         | Start an empty document                                        |
| `app.open(path)`    | Open a file                                                    |
| `app.save(path="")` | Save, over the file it came from when no path is given         |
| `app.undo()` / `app.redo()` | One step of the undo stack                            |

The `Document` that comes back is a copy. Editing it changes nothing; the calls
below are what change the open document, and each one records an undo step.

### Features and motion

| Call                                        | What it does                            |
| ------------------------------------------- | --------------------------------------- |
| `app.add_feature(title, rings=(), geometry_kind="polygon", feature_type="", parent="")` | Add one, answering with its uuid |
| `app.add_group(title, parent="")`           | Add a group                             |
| `app.edit_feature(uuid, **fields)`          | Change `title`, `enabled`, `feature_type`, `color`, `time_range` or `rings` |
| `app.delete_feature(uuid)`                  | Take a node out of the tree             |
| `app.set_keyframe(uuid, time, rotation)`    | Where the feature stands at a time      |
| `app.delete_keyframe(uuid, time)`           | Drop the keyframe at that time          |

`parent` is a group's uuid, and the root group when it is empty. A ring is a
list of `(latitude, longitude)` pairs in degrees, a rotation is three degrees in
the order the rest of the application uses, and time is an age in millions of
years before present, so a larger number is older; see [Time](Time.md).

Anything the application refuses — a uuid that names nothing, a latitude off the
planet, a geometry kind a feature type does not allow — is raised as an
`AppError` saying what the application said.

### Time and selection

| Call                             | What it does                                  |
| -------------------------------- | --------------------------------------------- |
| `app.time`                       | The current time, read and written             |
| `app.play()` / `app.pause()`     | The timeline's own play and pause              |
| `app.playing`                    | Whether it is running                          |
| `app.selected`                   | The uuid of the selected node, empty when none |
| `app.select(uuid)`               | Select one                                     |

### Files without an application

`Document` reads and writes `.middle-earth` files on their own. It keeps the
JSON it parsed and the classes are views onto it, so a file that is read and
written back comes out byte for byte as it went in, whatever format version it
was written at — and this package does not carry a second copy of the migrations
in `Logic/document.gd`. See [Persistence](Persistence.md).

```python
from middle_earth import Document, Feature

document = Document.load("cratons.middle-earth")
for feature in document.features:
    print(feature.title, len(feature.keyframes))

plates = document.root.add(Feature.new_group("Plates"))
plates.add(Feature.new_feature("Craton", rings=[[(0, 0), (0, 10), (10, 0)]]))
document.save("with-plates.middle-earth")
```

The one place a round trip can differ is a float with no short decimal form:
Godot writes fourteen significant digits and Python writes the shortest text
that reads back as the same double. Both are valid JSON and both load, so it
only shows in a byte comparison, and only for numbers a script computed rather
than ones a person typed.

## Scripts as menu entries

Every `.py` file in a configured directory whose first statement is a docstring
becomes an entry under File > Scripts. The first line of the docstring is what
the menu says; the whole of it is the tooltip and what `--help-command` prints.
A file without a docstring is left alone, so a working file in a script folder
does not become a command by accident, and neither does one whose name begins
with an underscore.

```python
"""Add a marker at the origin

A one point feature at latitude 0, longitude 0, named after the time it was
added at.
"""

uuid = app.add_feature("Marker at %g Ma" % app.time, rings=[[(0.0, 0.0)]],
                       geometry_kind="multipoint")
app.select(uuid)
```

The catalog is read from the files themselves, not through the interpreter, so
the entries are listed and `--help-command` answers even with `--no-python` —
they simply cannot be run. The first directory holding a given name wins, which
lets a directory earlier in the list put its own version of a command in front
of a later one. Preferences rescans when it is accepted.

The project ships two in `Scripts/`, which is where the list starts.

## Preferences

Two settings under Python in File > Preferences:

| Setting            | What it is                                                    |
| ------------------ | -------------------------------------------------------------- |
| Interpreter        | The Python that runs the bridge. Empty means the project's own `.venv` |
| Script directories | Where scripts are looked for, one path per line                 |

Changing the interpreter starts it again; changing the directories rescans. A
path that is not an interpreter is said so in the console and in the panel, and
the application carries on without one.

The interpreter needs no packages installed: the bridge is started by path and
puts its own folder on the import path. Python 3.13 or newer. The one thing
that does need a package is File > Import, which reads GPlates files with
`pygplates`; without it the import says so and everything else carries on. See
[Import](Import.md).

## The protocol

The application starts the interpreter, which listens on a loopback port and
takes the connection the application makes. One connection carries both
directions: the application asks the interpreter to evaluate a line, complete a
word or run a file, and while that is being done the script asks the application
about the document and edits it.

Messages are one JSON object per line, UTF-8.

```
request   {"id": 3, "cmd": "eval", "source": "app.time"}
reply     {"id": 3, "ok": true, "incomplete": false, "traceback": ""}
error     {"id": 3, "ok": false, "error": "unknown command: nonsense"}
event     {"event": "output", "stream": "stdout", "text": "1400.0\n"}
```

Each side numbers its own requests and answers with the id it was given, so a
reply is never mistaken for one to another request. The application counts up
from one and the interpreter counts down from minus one, which keeps the two
apart in a log without either having to know about the other's numbering. An
event carries no id and is never replied to.

Nothing on either side blocks. The application sends a request and waits on a
signal, so its frames keep running while the interpreter thinks, which is what
lets a script call back into the document in the middle of the line that started
it.

### What the application asks the interpreter

| Command    | Sends      | Answers                              |
| ---------- | ---------- | ------------------------------------ |
| `ping`     |            | `python`, `executable`               |
| `eval`     | `source`   | `incomplete`, `traceback`            |
| `complete` | `source`   | `completions`                        |
| `run_file` | `path`     | `traceback`                          |
| `import_gplates` | `sources`, `output` | `features`, `output`      |
| `quit`     |            | Ends the session                     |

A script that raises is not a failure of the bridge: the reply is `ok` with the
traceback in it. `ok` is false only when the message itself was wrong, and a
line that is not a JSON object is refused without the interpreter going down.

### What the interpreter asks the application

`document`, `time`, `set_time`, `play`, `pause`, `selection`, `select`, `new`,
`open`, `save`, `undo`, `redo`, `add_feature`, `add_group`, `edit_feature`,
`delete_feature`, `set_keyframe` and `delete_keyframe` — one per call of the API
above. Each finishes the edit the way the panels do, so a script's change
reaches the tree, the globe, the timeline and the graphs exactly as a person's
does.

### When the interpreter goes away

A request already waiting is answered with a refusal rather than left hanging,
every later one is refused with the reason, the console says why and the prompt
stops taking typing. The application itself carries on. The same path covers an
interpreter that will not start and one that is killed mid session.

## Where the code is

| File                                     | What is in it                            |
| ---------------------------------------- | ---------------------------------------- |
| `src/middle_earth/document.py`           | The file format                           |
| `src/middle_earth/api.py`                | `App`, the running document               |
| `src/middle_earth/bridge.py`             | The server, the console session, completion |
| `src/middle_earth/gplates.py`            | The GPlates conversion; see [Import](Import.md) |
| `src/middle_earth/gproj.py`              | The GPlates project archive               |
| `src/middle_earth/__main__.py`           | What the application starts               |
| `Logic/script_catalog.gd`                | Reading docstrings out of script files    |
| `Scenes/Application/python_bridge.gd`    | The application's half of the protocol    |
| `Scenes/Application/console_panel.gd`    | The panel                                 |

Tested by `Tests/Python` for the package, `Tests/Rendered/test_python_bridge.gd`
for the protocol against a stub, and the console session in `Tests/session.py`
for the two together. See [Testing](Testing.md).
