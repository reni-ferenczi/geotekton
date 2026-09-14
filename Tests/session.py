"""Scripted automation session against a running application.

Launches the application with the automation port open, drives it through a
short scenario and checks the answers. Nothing here is judged by looking at a
screenshot: every claim about what is on screen is a pixel probe or a
coordinate returned by the port.

Usage:
    python Tests/session.py [--port N]
"""

import colorsys
import json
import math
import re
import shutil
import sys
import tempfile
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from automation_client import AutomationClient, launch_app

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_PORT = 45455

USAGE = "usage: session.py [--port N]"

failures: list[str] = []


def check(condition: bool, message: str) -> bool:
    """Record and report one check, then return whether it passed."""
    print(f"{'PASS' if condition else 'FAIL'} {message}")
    if not condition:
        failures.append(message)
    return condition


def project_version() -> str:
    """The application version declared in project.godot."""
    text = (ROOT / "project.godot").read_text(encoding="utf-8")
    match = re.search(r'^config/version\s*=\s*"([^"]+)"', text, re.MULTILINE)
    assert match is not None, "config/version not found in project.godot"
    return match.group(1)


# How far the other two channels may come up before a colour stops being
# dominated by one of them. The channels are compared against each other rather
# than against a fixed level, so a feature that the hover highlight has
# brightened is still its own colour: green (0.11, 1.0, 0.11) becomes
# (0.44, 1.0, 0.44) under the highlight and both are green.
DOMINANT_RATIO = 0.7


# A feature whose colour is not dominated by one channel is recognised by its
# hue instead. The planet lights what it draws and lets the Earth texture
# through, which lifts every channel towards white and so washes the saturation
# out; the hue is what comes through that unchanged.
def hue_and_saturation(color: list[float]) -> tuple[float, float]:
    hue, saturation, _ = colorsys.rgb_to_hsv(color[0], color[1], color[2])
    return hue, saturation


def dominant(color: list[float]) -> str:
    """The channel a probed pixel is dominated by, empty when none is."""
    red, green, blue = color[0], color[1], color[2]
    for name, value, others in (
        ("red", red, (green, blue)),
        ("green", green, (red, blue)),
        ("blue", blue, (red, green)),
    ):
        if value > 0.5 and max(others) < value * DOMINANT_RATIO:
            return name
    return ""


def run_session(client: AutomationClient) -> None:
    """Drive the application through the scenario and check every answer."""
    version = project_version()
    check(client.call("ping")["version"] == version, f"ping reports version {version}")

    sample = ROOT / "Tests" / "Data" / "two_cratons.middle-earth"
    client.call("load", path=str(sample))
    titles = [f["title"] for f in client.call("get_features")["features"]]
    for title in ("Red Triangle", "Blue Quad", "Green Moved"):
        check(title in titles, f"get_features lists {title}")

    client.call("select", title="Blue Quad")
    selected = client.call("get_selected")["feature"]
    check(selected["title"] == "Blue Quad", "select by title selects Blue Quad")
    # The sample is a 0.1.0 file, where the quad was two triangles; the loader
    # recovers the outline, so what arrives here is one ring of four vertices.
    check(selected["geometry_kind"] == "polygon", "Blue Quad is a polygon")
    check([len(ring) for ring in selected["rings"]] == [4],
          f"Blue Quad is one ring of 4 vertices: {selected['rings']}")
    check(len(selected["triangles"]) == 6, "which still covers two triangles")

    client.call("select", title=None)
    clear = client.call("latlon_to_screen", lat=5.0, lon=40.0)["screen"]
    if check(clear is not None, "lat/lon (5, 40) is on the visible hemisphere"):
        clear_color = client.call("get_pixel", x=clear[0], y=clear[1])["color"]
        check(dominant(clear_color) != "green", f"the pixel at (5, 40) is not green: {clear_color}")

    # Turn the globe so that Green Moved faces the camera. At the default view it
    # sits near the limb, where the surface is barely lit, so the pixel probe
    # below would read a green too dark to recognize.
    client.call("set_view", lon=-60.0)
    check(client.call("get_view")["lon"] == -60.0, "set_view turns the globe to longitude -60")

    screen = client.call("latlon_to_screen", lat=-3.0, lon=-60.0)["screen"]
    if not check(screen is not None, "lat/lon (-3, -60) is on the visible hemisphere"):
        return

    client.call("click", x=screen[0], y=screen[1], button="left")
    selected = client.call("get_selected")["feature"]
    check(selected["title"] == "Green Moved", "clicking (-3, -60) selects Green Moved")
    check([len(ring) for ring in selected["rings"]] == [3], "Green Moved is one ring of 3 vertices")
    check([len(ring) for ring in selected["world_rings"]] == [3], "and 3 world vertices")
    check(selected["world_rings"] != selected["rings"], "Green Moved is rotated")

    # Take the mouse off the craton first: the one under the pointer is drawn
    # highlighted, which is a different green from the one the file asks for.
    away = client.call("latlon_to_screen", lat=30.0, lon=-90.0)["screen"]
    client.call("mouse_move", x=away[0], y=away[1])
    color = client.call("get_pixel", x=screen[0], y=screen[1])["color"]
    check(dominant(color) == "green", f"the pixel at (-3, -60) is green: {color}")

    client.call("set_time", time=1500.0)
    check(client.call("get_time")["time"] == 1500.0, "set_time 1500 round trips")

    latlon = client.call("screen_to_latlon", x=screen[0], y=screen[1])["latlon"]
    if check(latlon is not None, "the green click point maps back to a lat/lon"):
        off = max(abs(latlon[0] - (-3.0)), abs(latlon[1] - (-60.0)))
        check(off < 0.05, f"screen_to_latlon returns (-3, -60) within 0.05 degrees: {latlon}")


def run_document_session(client: AutomationClient, folder: Path) -> None:
    """Drive New, Open, Save, Save As and the unsaved changes prompt."""
    first = folder / "first.middle-earth"
    second = folder / "second.middle-earth"
    shutil.copy(ROOT / "Tests" / "Data" / "two_cratons.middle-earth", first)
    shutil.copy(ROOT / "Tests" / "Data" / "triangle.middle-earth", second)

    # Open asks for a path; the port answers it in place of the native dialog.
    client.call("expect_file_dialog", path=str(first))
    client.call("menu", item="open")
    document = client.call("get_document")["document"]
    check(document["path"] == str(first), f"Open loads the chosen file: {document['path']}")
    check(not document["dirty"], "a freshly opened document is clean")
    check(document["title"] == "first.middle-earth — Middle Earth",
          f"the window title names the file: {document['title']}")
    check_opens_at_the_oldest_age(client, "an opened document")

    # An edit through the feature tree toolbar marks the document dirty.
    client.call("toolbar", button="AddFeature")
    document = client.call("get_document")["document"]
    check(document["dirty"], "adding a feature makes the document dirty")
    check(document["title"].startswith("*"), f"the title marks it unsaved: {document['title']}")
    features_before = len(client.call("get_features")["features"])

    # New on a dirty document asks first, and Cancel leaves everything alone.
    client.call("menu", item="new")
    dialog = client.call("get_dialog")["dialog"]
    if check(dialog is not None, "New on a dirty document asks about the changes"):
        check("first.middle-earth" in dialog["text"], f"the prompt names the file: {dialog['text']}")
        check(sorted(b.lower() for b in dialog["buttons"]) == ["cancel", "discard", "save"],
              f"the prompt offers Save, Discard and Cancel: {dialog['buttons']}")
        client.call("dialog", button="Cancel")
    document = client.call("get_document")["document"]
    check(document["dirty"] and document["path"] == str(first), "Cancel leaves the document open and dirty")
    check(len(client.call("get_features")["features"]) == features_before,
          "Cancel leaves the feature tree untouched")

    # Quit on a dirty document asks the same way; Cancel keeps the application up.
    client.call("menu", item="quit")
    dialog = client.call("get_dialog")["dialog"]
    if check(dialog is not None, "Quit on a dirty document asks about the changes"):
        client.call("dialog", button="Cancel")
    check(client.call("get_document")["document"]["dirty"], "the application is still running after Cancel")

    # Save answers the prompt and the action behind it goes ahead: the document
    # is written to its own path, without a dialog, and then the other file opens.
    client.call("get_file_dialog")
    client.call("expect_file_dialog", path=str(second))
    client.call("menu", item="open")
    client.call("dialog", button="Save")
    document = client.call("get_document")["document"]
    check(document["path"] == str(second), f"Open goes ahead after Save: {document['path']}")
    check(not document["dirty"], "the opened document is clean")
    written = json.loads(first.read_text(encoding="utf-8"))
    check(count_features(written["features"]) == features_before,
          "the edit was written to the first file before it was closed")

    # Save on a document that has a path writes to it without asking.
    client.call("toolbar", button="AddFeature")
    client.call("get_file_dialog")  # forget the one the Open above went through
    client.call("menu", item="save")
    check(client.call("get_file_dialog")["file_dialog"] is None, "Save does not ask for a path")
    check(not client.call("get_document")["document"]["dirty"], "Save makes the document clean")

    # The Save button of the feature tree toolbar runs the same command.
    client.call("toolbar", button="AddFeature")
    client.call("get_file_dialog")
    client.call("toolbar", button="Save")
    check(client.call("get_file_dialog")["file_dialog"] is None, "the toolbar Save does not ask either")
    check(not client.call("get_document")["document"]["dirty"], "the toolbar Save writes the document")

    # Save As always asks, and cancelling it leaves the path alone.
    client.call("menu", item="save_as")
    asked = client.call("get_file_dialog")["file_dialog"]
    if check(asked is not None, "Save As asks for a path"):
        check(asked["title"] == "Save As", f"the dialog is the Save As one: {asked['title']}")
    check(client.call("get_document")["document"]["path"] == str(second),
          "a cancelled Save As leaves the path alone")

    # The recent list holds both files, newest first, and opens what it lists.
    recent = client.call("get_recent")["recent"]
    check(recent[:2] == [str(second), str(first)], f"the recent list is newest first: {recent}")
    client.call("open_recent", index=1)
    check(client.call("get_document")["document"]["path"] == str(first),
          "the second entry of the recent list opens the first file")
    client.call("clear_recent")
    check(client.call("get_recent")["recent"] == [], "Clear empties the recent list")

    # The About dialog names the version and credits the Earth texture.
    client.call("menu", item="about")
    dialog = client.call("get_dialog")["dialog"]
    if check(dialog is not None, "Help opens the About dialog"):
        check(dialog["name"] == "AboutDialog", f"the dialog is the About one: {dialog['name']}")
        client.call("dialog", button="OK")
    check(client.call("get_dialog")["dialog"] is None, "OK closes the About dialog")

    # New on a clean document goes straight through.
    client.call("menu", item="new")
    document = client.call("get_document")["document"]
    check(document["path"] == "" and not document["dirty"], "New starts an empty document")
    check(document["title"] == "Untitled — Middle Earth", f"the title says Untitled: {document['title']}")
    check_opens_at_the_oldest_age(client, "a new document")

    # Save on a document that has never been written asks where to put it.
    client.call("menu", item="save")
    check(client.call("get_file_dialog")["file_dialog"] is not None,
          "Save asks for a path when the document has none")

    # The panels can be hidden and shown from the View menu.
    client.call("menu", item="timeline")
    check(not client.call("get_panels")["panels"]["timeline"], "View hides the timeline")
    client.call("menu", item="timeline")
    check(client.call("get_panels")["panels"]["timeline"], "View shows the timeline again")


# The polyline reaches 45 degrees either side of the middle of the view, well out
# towards the limb, where a mismatch between the drawn globe and the sphere the
# ray is cast against would show up as a visible offset.
DRAWINGS = {
    "polygon": [(-10.0, -10.0), (10.0, 0.0), (-10.0, 10.0)],
    "polyline": [(0.0, -45.0), (5.0, 0.0), (0.0, 45.0)],
    "multipoint": [(-5.0, -5.0), (5.0, 5.0)],
}

# A click goes out as a screen position computed for the drawn globe and comes
# back as the lat/lon where the ray met the collision sphere. Both are the same
# sphere, so what is left is the single precision arithmetic of the projection
# and the ray cast.
CLICK_TOLERANCE = 0.001


def check_opens_at_the_oldest_age(client: AutomationClient, what: str) -> None:
    """The timeline starts at the oldest age the animation range covers."""
    timeline = client.call("get_timeline")["timeline"]
    oldest = max(timeline["animation"]["start"], timeline["animation"]["end"])
    check(timeline["time"] == oldest and timeline["typed"] == oldest,
          f"{what} opens at {oldest} Ma, the oldest age of the animation: {timeline['time']}")


def start_new_document(client: AutomationClient) -> None:
    """File > New, throwing away whatever the previous scenario left behind."""
    client.call("menu", item="new")
    if client.call("get_dialog")["dialog"] is not None:
        client.call("dialog", button="Discard")
    # An earlier scenario turned the globe; the points drawn below are around
    # the middle of the default view.
    client.call("set_view", lat=0.0, lon=0.0, angle=0.0)


def draw(client: AutomationClient, points: list[tuple[float, float]]) -> bool:
    """Click each point on the globe. False when one of them is not visible."""
    for lat, lon in points:
        screen = client.call("latlon_to_screen", lat=lat, lon=lon)["screen"]
        if not check(screen is not None, f"lat/lon ({lat}, {lon}) is on the visible hemisphere"):
            return False
        client.call("click", x=screen[0], y=screen[1])
    return True


def worst_offset(ring: list[list[float]], points: list[tuple[float, float]]) -> float:
    """How far the stored vertices are from the points that were clicked."""
    return max(
        max(abs(stored[0] - lat), abs(stored[1] - lon))
        for stored, (lat, lon) in zip(ring, points, strict=True)
    )


# The five feature types in the order the selector offers them, and the one
# each drawn kind gives, as Logic/feature_type.gd has them.
FEATURE_TYPES = ["polygon", "line", "points", "circle", "topology"]
KIND_TYPES = {"polygon": "polygon", "polyline": "line", "multipoint": "points"}


def run_drawing_session(client: AutomationClient) -> None:
    """Draw one feature of each geometry kind and check what it stored.

    The kind comes from the feature's type, which is picked in the Properties
    panel before anything is drawn.
    """
    for kind, points in DRAWINGS.items():
        start_new_document(client)
        client.call("toolbar", button="AddFeature")

        tool = client.call("get_tool")
        check(tool["tool"] == "draw", f"the Draw tool arms itself on an empty feature ({kind})")
        check("kind" not in tool and "allowed_kinds" not in tool,
              f"and the tool strip has no geometry kind box of its own ({kind})")
        panel = client.call("get_properties")["properties"]
        check(panel["feature_type"] == "polygon",
              f"which a new feature is, before anything is drawn: {panel['feature_type']!r}")
        client.call("set_property", field="feature_type", value=KIND_TYPES[kind])
        check(client.call("get_tool")["tool"] == "draw",
              f"the Draw tool draws all three of those types ({kind})")

        if not draw(client, points):
            continue
        check(client.call("get_tool")["drawing_vertices"] == len(points),
              f"{len(points)} vertices are placed ({kind})")
        client.call("key", key="Enter")

        feature = client.call("get_selected")["feature"]
        check(feature["geometry_kind"] == kind, f"the feature is a {kind}: {feature['geometry_kind']}")
        check(feature["feature_type"] == KIND_TYPES[kind],
              f"and the first shape gives it the type {KIND_TYPES[kind]}: {feature['feature_type']!r}")
        if check(len(feature["rings"]) == 1, f"one ring was committed ({kind})"):
            ring = feature["rings"][0]
            if check(len(ring) == len(points), f"the ring holds {len(points)} vertices ({kind})"):
                offset = worst_offset(ring, points)
                check(offset < CLICK_TOLERANCE,
                      f"the stored vertices match the clicked points within "
                      f"{CLICK_TOLERANCE} degrees ({kind}): {offset:.6f}")
        # Undo takes the geometry off again, leaving the empty feature behind
        # with the type that was picked for it.
        client.call("toolbar", button="Undo")
        check(client.call("get_selected")["feature"]["rings"] == [],
              f"undo removes the committed geometry ({kind})")
        check(client.call("get_properties")["properties"]["feature_type"] == KIND_TYPES[kind],
              f"and the feature keeps its type ({kind})")


def run_point_undo_session(client: AutomationClient) -> None:
    """Ctrl+Z takes back the last point a tool holds and Ctrl+Y puts it back.

    The document's own stack is reached only once no point is held; without
    that, Ctrl+Z halfway through a shape undid the creation of the feature it
    was being drawn on (GP-0041).
    """
    start_new_document(client)
    client.call("toolbar", button="AddFeature")
    client.call("set_tool", tool="draw")
    depth = client.call("get_document")["document"]["undo_depth"]
    points = DRAWINGS["polygon"]
    if not draw(client, points):
        return

    client.call("key", key="Z", ctrl=True)
    client.call("key", key="Z", ctrl=True)
    held = client.call("get_tool")["drawing_vertices"]
    check(held == len(points) - 2, f"Ctrl+Z twice takes two vertices back: {held} held")
    client.call("key", key="Y", ctrl=True)
    held = client.call("get_tool")["drawing_vertices"]
    check(held == len(points) - 1, f"Ctrl+Y puts one of them back: {held} held")
    check(client.call("get_document")["document"]["undo_depth"] == depth,
          "and the document's undo stack is untouched by either")

    # A new click forgets what was taken back, so Ctrl+Y has nothing to put down.
    if draw(client, points[-1:]):
        client.call("key", key="Y", ctrl=True)
        held = client.call("get_tool")["drawing_vertices"]
        check(held == len(points), f"a click forgets the vertex taken back: {held} held")

    # With the outline empty, Undo is the document's again.
    client.call("key", key="Escape")
    client.call("menu", item="undo")
    check(client.call("get_document")["document"]["undo_depth"] == depth - 1,
          "with nothing held, Edit > Undo reaches the document")
    client.call("menu", item="redo")

    # The Circle and Measure tools hold their points the same way.
    for tool, field in (("circle", "circle_points"), ("measure", "measure_points")):
        # Redo put the feature back but not the selection.
        client.call("select", title="Feature")
        if tool == "circle":
            # The Circle tool is offered on a Circle, and a polygon may be one.
            # Picking the type is an edit, so the stack is read again after it.
            client.call("set_property", field="feature_type", value="circle")
            depth = undo_depth(client)
        client.call("set_tool", tool=tool)
        if not draw(client, points[:2]):
            continue
        client.call("key", key="Z", ctrl=True)
        held = len(client.call("get_tool")[field])
        check(held == 1, f"Ctrl+Z takes a {tool} point back: {held} held")
        client.call("key", key="Y", ctrl=True)
        held = len(client.call("get_tool")[field])
        check(held == 2, f"Ctrl+Y puts the {tool} point back: {held} held")
        check(client.call("get_document")["document"]["undo_depth"] == depth,
              f"and the document's stack is untouched by the {tool} tool")
    client.call("set_tool", tool="move")


def run_escape_session(client: AutomationClient) -> None:
    """Escape throws the shape being drawn away without touching the feature."""
    start_new_document(client)
    client.call("toolbar", button="AddFeature")
    client.call("set_tool", tool="draw")
    if not draw(client, DRAWINGS["polygon"]):
        return
    check(client.call("get_tool")["drawing_vertices"] == 3, "three vertices are placed")

    client.call("key", key="Escape")
    check(client.call("get_tool")["drawing_vertices"] == 0, "Escape drops the placed vertices")
    check(client.call("get_selected")["feature"]["rings"] == [],
          "Escape leaves the feature without geometry")

    # A polygon of two vertices is not a shape, so Enter commits nothing.
    client.call("set_tool", tool="draw")
    if draw(client, DRAWINGS["polygon"][:2]):
        client.call("key", key="Enter")
        check(client.call("get_selected")["feature"]["rings"] == [],
              "Enter on two vertices commits no polygon")
        client.call("key", key="Escape")


MIXED = ROOT / "Tests" / "Data" / "mixed_geometry.middle-earth"

# The centroid of Red Triangle in mixed_geometry, as Tests/Data/README.md lists it.
RED_TRIANGLE_PROBE = (-3.0, 0.0)


def open_mixed_geometry(client: AutomationClient) -> None:
    """Load the mixed geometry sample, facing the middle of the default view."""
    client.call("load", path=str(MIXED))
    client.call("set_view", lat=0.0, lon=0.0, angle=0.0)


def titles_of(client: AutomationClient) -> list[str]:
    """Every title in the feature tree, in tree order."""
    return [f["title"] for f in client.call("get_features")["features"]]


# What a group's style selector offers, Styling.MODES in Logic/styling.gd.
GROUP_STYLES = ["inherit", "feature", "single", "age", "type"]


def run_group_style_checks(client: AutomationClient) -> None:
    """A group's style set through the panel, seen on the globe and undone."""
    lat, lon = (-3.0, 0.0)  # Red Triangle, under Shapes
    client.call("mouse_move", x=10, y=10)
    depth = client.call("get_document")["document"]["undo_depth"]
    single = [0.1, 0.6, 0.9, 1.0]
    client.call("set_property", field="style", value="single")
    client.call("set_property", field="color", value=single)
    style = client.call("get_properties")["properties"]["style"]
    check(style["mode"] == "single" and all(abs(a - b) < 1e-3 for a, b in zip(style["color"], single)),
          f"the panel reads back the style it was given: {style}")
    check(client.call("get_document")["document"]["undo_depth"] == depth + 2,
          "two edits of the style, two undo versions")
    check(is_colour(probe_at(client, lat, lon), single),
          "the group's single colour reaches the polygon under it")

    client.call("set_property", field="opacity", value=0)
    check(client.call("get_properties")["properties"]["style"]["opacity"] == 0,
          "the opacity box is the group's opacity")
    check(not is_colour(probe_at(client, lat, lon), single),
          "and at none the Earth shows where the polygon is")

    for _ in range(3):
        client.call("menu", item="undo")
    panel = client.call("get_properties")["properties"]
    check(panel["name"] == "Shapes" and panel["style"]["mode"] == "inherit",
          f"undo takes the style back: {panel.get('style')}")
    check(is_colour(probe_at(client, lat, lon), [1.0, 0.0, 0.0]),
          "and the polygon is red again")

    # GP-0036: the ramp rows. Both ends the same colour, so the probe does not
    # depend on how old the polygon is.
    depth = client.call("get_document")["document"]["undo_depth"]
    ramp = [0.1, 0.6, 0.9, 1.0]
    client.call("set_property", field="style", value="age")
    client.call("set_property", field="palette", value="ramp")
    client.call("set_property", field="ramp_colors", value=[ramp, ramp])
    client.call("set_property", field="ramp_span", value=450)
    style = client.call("get_properties")["properties"]["style"]
    check(style["palette"] == "ramp" and style["ramp_span"] == 450
          and len(style["ramp_colors"]) == 2
          and all(abs(a - b) < 1e-3 for stop in style["ramp_colors"]
                  for a, b in zip(stop, ramp)),
          f"the panel reads back the ramp it was given: {style}")
    check(client.call("get_document")["document"]["undo_depth"] == depth + 4,
          "four edits of the style, four undo versions")
    check(is_colour(probe_at(client, lat, lon), ramp),
          "the group's ramp reaches the polygon under it")

    # GP-0053: a colour added to the ramp. The polygon exists from 2000 Ma, so
    # at the present it is 2000 My old: past a two colour ramp of 1000 My, and
    # exactly at the end of the same ramp once a third colour is on it.
    red, blue, green = [1.0, 0.0, 0.0, 1.0], [0.0, 0.0, 1.0, 1.0], [0.0, 1.0, 0.0, 1.0]
    opened_at = client.call("get_timeline")["timeline"]["time"]
    client.call("set_time", time=0.0)
    client.call("set_property", field="ramp_span", value=1000)
    client.call("set_property", field="ramp_colors", value=[red, blue])
    check(is_colour(probe_at(client, lat, lon), blue),
          "2000 My old is past a 1000 My ramp, so the last colour of it")
    client.call("set_property", field="ramp_colors", value=[red, blue, green])
    check(len(client.call("get_properties")["properties"]["style"]["ramp_colors"]) == 3,
          "the panel shows three colours once a third is added")
    check(is_colour(probe_at(client, lat, lon), green),
          "and 2000 My old is the end of the second span, which is the new colour")
    refused = ""
    try:
        client.call("set_property", field="ramp_colors", value=[red])
    except RuntimeError as error:
        refused = str(error)
    check(refused != "", f"a ramp of one colour is refused: {refused}")
    client.call("set_time", time=opened_at)

    for _ in range(7):
        client.call("menu", item="undo")
    check(client.call("get_properties")["properties"]["style"]["mode"] == "inherit",
          "and undo takes the ramp back")
    client.call("set_view", lat=0.0, lon=0.0, angle=0.0)


def run_properties_session(client: AutomationClient) -> None:
    """The Properties panel: what it shows, what it edits and what it refuses."""
    open_mixed_geometry(client)

    # The panel keeps one width whatever it is showing. When it does not, the
    # split container hands the difference to the planet view, and every screen
    # position computed before the selection changed is off.
    widths = {}
    for title in (None, "Shapes", "Red Triangle"):
        client.call("select", title=title)
        panel = client.call("get_properties")["properties"]
        widths[panel["showing"]] = panel["width"]
    check(len(set(widths.values())) == 1,
          f"the panel is the same width for the root, a group and a feature: {widths}")

    client.call("select", title="Red Triangle")
    panel = client.call("get_properties")["properties"]
    check(panel["showing"] == "feature", f"selecting a feature fills the panel: {panel['showing']}")
    check(panel["name"] == "Red Triangle", f"with its name: {panel['name']}")
    check(panel["feature_type"] == "polygon", f"its type: {panel['feature_type']}")
    check(panel["types"] == FEATURE_TYPES, f"the type selector offers the five: {panel['types']}")
    check(panel["color"][:3] == [1.0, 0.0, 0.0], f"its colour: {panel['color']}")
    check(panel["enabled"] is True, "its enabled flag")
    check(panel["time_range"] == [0, 2000], f"its time range: {panel['time_range']}")
    check((panel["time_from"], panel["time_to"]) == (2000, 0),
          f"with From the older end and To the younger: {panel['time_from']}, {panel['time_to']}")
    check(panel["tooltips"]["time_from"].startswith("The age the feature appears at")
          and panel["tooltips"]["time_to"].startswith("The age it disappears at"),
          f"and a hover description on each: {panel['tooltips']}")
    check("3 vertices in 1 part" in panel["geometry"], f"its geometry summarized: {panel['geometry']}")
    check("coordinates" not in panel, f"and no coordinate rows: {sorted(panel)}")
    # The sample holds one keyframe at the present and the document opened at the
    # oldest age, so Delete is greyed out until the time is on that keyframe.
    now = client.call("get_time")["time"]
    times = [k["time"] for k in client.call("get_selected")["feature"]["keyframes"]]
    check(panel["keyframes"] == {"count": len(times), "key": True, "delete": now in times},
          f"one keyframe row with its count, Key and Delete: {panel['keyframes']}, {times}")

    # A group has a name, a switch and a style: how the features under it are
    # colored. It has no type, geometry or keyframes.
    client.call("select", title="Shapes")
    panel = client.call("get_properties")["properties"]
    check(panel["showing"] == "group", "selecting a group shows the group properties")
    check(panel["name"] == "Shapes" and "feature_type" not in panel and "keyframes" not in panel,
          f"a group has no type, geometry or keyframes: {sorted(panel)}")
    check(panel["style"]["mode"] == "inherit" and panel["style"]["opacity"] == 100,
          f"a group from an older file inherits at full opacity: {panel['style']}")
    check(panel["styles"] == GROUP_STYLES, f"the style selector offers these: {panel['styles']}")
    run_group_style_checks(client)

    # The name in the panel is the name on the tree row, and undo moves both back.
    client.call("select", title="Red Triangle")
    client.call("set_property", field="name", value="Gondwana")
    check("Gondwana" in titles_of(client), "renaming in the panel renames the tree row")
    check(client.call("get_properties")["properties"]["name"] == "Gondwana",
          "and the panel keeps the new name")
    client.call("menu", item="undo")
    titles = titles_of(client)
    check("Red Triangle" in titles and "Gondwana" not in titles,
          "undo puts the old name back in the tree")
    check(client.call("get_properties")["properties"]["name"] == "Red Triangle",
          "and in the panel, which stays on the feature it was showing")

    # A type the geometry does not fit is refused, with a message.
    client.call("select", title="Blue Ridge")
    client.call("set_property", field="feature_type", value="points")
    dialog = client.call("get_dialog")["dialog"]
    if check(dialog is not None, "a polyline cannot be Points, and the panel says so"):
        client.call("dialog", button="OK")
    check(client.call("get_properties")["properties"]["feature_type"] == "line",
          "the refused type is off the selector again")
    check(client.call("get_selected")["feature"]["feature_type"] == "line",
          "and never reached the feature")

    # Circle does fit, and leaves the colour the file picked alone.
    client.call("set_property", field="feature_type", value="circle")
    check(client.call("get_selected")["feature"]["feature_type"] == "circle",
          "a polyline may be a circle")
    check(client.call("get_properties")["properties"]["color"] == [0.0, 0.0, 1.0, 1.0],
          "and the blue the file picked survives the type change")

    # From is the older end, so it moves the second number of the pair.
    client.call("set_property", field="time_from", value=500)
    check(client.call("get_selected")["feature"]["time_range"] == [0, 500],
          "From moves the older end of the time range")
    # A range that ends older than it starts is refused the same way as a type.
    client.call("set_property", field="time_to", value=900)
    dialog = client.call("get_dialog")["dialog"]
    if check(dialog is not None, "a range that ends older than it starts is refused"):
        client.call("dialog", button="OK")
    check(client.call("get_selected")["feature"]["time_range"] == [0, 500],
          "and the feature keeps the range it had")
    panel = client.call("get_properties")["properties"]
    check((panel["time_from"], panel["time_to"]) == (500, 0),
          f"which is what the panel shows again: {panel['time_from']}, {panel['time_to']}")

    # The switch in the panel is the switch on the tree row.
    client.call("set_property", field="enabled", value=False)
    check(client.call("get_selected")["feature"]["enabled"] is False,
          "the panel disables the feature")
    client.call("set_property", field="enabled", value=True)

    # A new feature takes the age the timeline is showing as its oldest end and
    # runs to the present, since that is the direction the work goes in.
    client.call("set_time", time=1500.0)
    client.call("toolbar", button="AddFeature")
    check(client.call("get_selected")["feature"]["time_range"] == [0, 1500],
          "a feature added at 1500 Ma exists from 1500 Ma to the present")
    panel = client.call("get_properties")["properties"]
    check((panel["time_from"], panel["time_to"]) == (1500, 0),
          f"which the panel reads as From 1500 To 0: {panel['time_from']}, {panel['time_to']}")

    # It is a Polygon before anything is drawn into it, and the type is free to
    # change until a shape has to hold it.
    check(panel["feature_type"] == "polygon" and panel["type_label"] == "Polygon",
          f"a new feature is a Polygon: {panel['type_label']!r}")
    client.call("set_property", field="feature_type", value="line")
    check(client.call("get_dialog")["dialog"] is None,
          "a type on a feature holding nothing is accepted")
    check(client.call("get_selected")["feature"]["feature_type"] == "line",
          "and the empty feature keeps it")
    check(client.call("get_tool")["draw_enabled"],
          "the Draw tool draws a Line as a polyline")
    client.call("set_property", field="feature_type", value="topology")
    tool = client.call("get_tool")
    check(tool["topology_enabled"] and not tool["draw_enabled"],
          "a Topology is built with the Topology tool instead")
    client.call("set_property", field="feature_type", value="polygon")


def run_keyframe_row_session(client: AutomationClient) -> None:
    """The keyframe row: Key between two keyframes and Delete on one."""
    client.call("load", path=str(MOTION))
    client.call("select", title="Drifting Craton")
    # The sample holds keyframes at 0, 600 and 1400 Ma.
    client.call("set_time", time=300.0)
    before = client.call("get_selected")["feature"]
    row = client.call("get_properties")["properties"]["keyframes"]
    check(row == {"count": 3, "key": True, "delete": False},
          f"between two keyframes Key works and Delete is greyed out: {row}")

    versions = undo_depth(client)
    client.call("keyframes", button="Key")
    after = client.call("get_selected")["feature"]
    check([k["time"] for k in after["keyframes"]] == [0.0, 300.0, 600.0, 1400.0],
          f"Key adds a keyframe at the current time: {after['keyframes']}")
    check(worst_offset(after["world_rings"][0], [tuple(v) for v in before["world_rings"][0]]) < 1e-3,
          "without moving the feature on the globe")
    check(undo_depth(client) == versions + 1, "in one undo step")
    row = client.call("get_properties")["properties"]["keyframes"]
    check(row == {"count": 4, "key": True, "delete": True},
          f"the row counts it, and Delete works now the time is on one: {row}")

    client.call("set_time", time=600.0)
    client.call("keyframes", button="Delete")
    times = [k["time"] for k in client.call("get_selected")["feature"]["keyframes"]]
    check(times == [0.0, 300.0, 1400.0], f"Delete removes the keyframe at the current time: {times}")
    row = client.call("get_properties")["properties"]["keyframes"]
    check(row == {"count": 3, "key": True, "delete": False},
          f"and is greyed out once none is there: {row}")
    refused = ""
    try:
        client.call("keyframes", button="Delete")
    except RuntimeError as error:
        refused = str(error)
    check(refused != "", f"so pressing it again is refused: {refused}")


COUPLING_SAMPLE = ROOT / "Tests" / "Data" / "two_cratons.middle-earth"
COUPLED_AT = 500.0
DECOUPLED_AT = 200.0
# Inside the span, where the rider is dragged on its own.
RIDER_MOVED_AT = 350.0
# How far the parent is dragged each time, in degrees of longitude.
PARENT_DRAG = 10.0


def coupling_row(client: AutomationClient) -> dict:
    return client.call("get_properties")["properties"]["coupling"]


def centroid_of(client: AutomationClient, title: str) -> tuple[float, float]:
    client.call("select", title=title)
    return world_centroid(client)


def run_coupling_session(client: AutomationClient, folder: Path) -> None:
    """Couple the blue quad to the red triangle, drag each, decouple, and keep the spans."""
    client.call("load", path=str(COUPLING_SAMPLE))
    client.call("set_view", lat=15.0, lon=20.0, angle=0.0)
    planet = client.call("latlon_to_screen", lat=15.0, lon=20.0)["screen"]
    client.call("select", title="Red Triangle")
    red = client.call("get_selected")["feature"]
    client.call("select", title="Blue Quad")
    client.call("set_time", time=COUPLED_AT)

    row = coupling_row(client)
    check(row["coupled_to"] == "nothing" and not row["decouple"] and row["spans"] == [],
          f"an uncoupled feature rides on nothing: {row}")
    check("Red Triangle" in row["parents"] and "Blue Quad" not in row["parents"],
          f"and the picker offers every other feature: {row['parents']}")

    before = client.call("get_selected")["feature"]
    versions = undo_depth(client)
    client.call("coupling", button="Couple", parent="Red Triangle")
    after = client.call("get_selected")["feature"]
    check(after["couplings"] == [{"from": COUPLED_AT, "to": 0.0, "parent": red["uuid"]}],
          f"Couple starts a span at the current time running to the present: {after['couplings']}")
    check(worst_offset(after["world_rings"][0], [tuple(v) for v in before["world_rings"][0]]) < 1e-3,
          "without moving the feature on the globe")
    check(undo_depth(client) == versions + 1, "in one undo step")
    row = coupling_row(client)
    check(row["coupled_to"] == "Red Triangle" and row["decouple"] and not row["couple"]
          and row["spans"] == [{"parent": "Red Triangle", "from": COUPLED_AT, "to": 0.0, "broken": False}],
          f"the panel names the parent and lists the span: {row}")
    bars = client.call("get_timeline")["timeline"]["couplings"]
    check(len(bars) == 1 and bars[0]["from"] == COUPLED_AT and bars[0]["screen"][0] < bars[0]["screen"][1],
          f"the timeline draws the span as a bar from older to younger: {bars}")
    check(client.call("latlon_to_screen", lat=15.0, lon=20.0)["screen"] == planet,
          "the coupling rows leave the planet where it was")

    # Couple, drag the parent: the child moves with it.
    client.call("set_time", time=DECOUPLED_AT)
    rider = centroid_of(client, "Blue Quad")
    parent = centroid_of(client, "Red Triangle")
    if not drag(client, parent[0], parent[1] + PARENT_DRAG):
        return
    moved_parent = world_centroid(client)
    moved_rider = centroid_of(client, "Blue Quad")
    check(angular_distance(rider, moved_rider) > PARENT_DRAG / 2.0,
          f"dragging the parent carries the rider: {rider} to {moved_rider}")
    check(abs(angular_distance(moved_parent, moved_rider) - angular_distance(parent, rider)) < DRAG_TOLERANCE,
          "and keeps it as far from the parent as it was")

    # Decouple, drag the parent: the child stays.
    before = client.call("get_selected")["feature"]
    client.call("coupling", button="Decouple")
    after = client.call("get_selected")["feature"]
    check(after["couplings"] == [{"from": COUPLED_AT, "to": DECOUPLED_AT, "parent": red["uuid"]}],
          f"Decouple ends the span at the current time: {after['couplings']}")
    check(DECOUPLED_AT in [k["time"] for k in after["keyframes"]],
          f"with a keyframe there: {after['keyframes']}")
    check(worst_offset(after["world_rings"][0], [tuple(v) for v in before["world_rings"][0]]) < 1e-3,
          "and nothing on the globe moves")
    check(coupling_row(client)["coupled_to"] == "nothing", "the panel says it rides on nothing now")
    parent = centroid_of(client, "Red Triangle")
    if not drag(client, parent[0], parent[1] + PARENT_DRAG):
        return
    client.call("select", title="Blue Quad")
    stayed = client.call("get_selected")["feature"]
    check(worst_offset(stayed["world_rings"][0], [tuple(v) for v in after["world_rings"][0]]) < 1e-3,
          "dragging the parent after decoupling leaves the rider where it is")

    # Dragging the rider inside the span writes a keyframe relative to the
    # parent, which has moved by then, and still lands where it was dropped.
    client.call("set_time", time=RIDER_MOVED_AT)
    lat, lon = world_centroid(client)
    if not drag(client, lat - 5.0, lon):
        return
    got = world_centroid(client)
    check(abs(got[0] - (lat - 5.0)) < DRAG_TOLERANCE and abs(got[1] - lon) < DRAG_TOLERANCE,
          f"a rider dragged inside the span lands where it was dropped: {got}")

    run_coupling_refusal_checks(client)
    run_coupling_round_trip(client, folder)
    run_rigid_coupling_checks(client)
    run_pick_parent_checks(client)


# The green craton of the sample sits at longitude -60 and the red triangle at
# 0, so a view between the two has both well inside the limb. Nothing is drawn
# at PICK_EMPTY, which is probed before it is clicked.
PICK_VIEW = (0.0, -30.0)
PICK_EMPTY = (-40.0, -30.0)


def run_pick_parent_checks(client: AutomationClient) -> None:
    """The pointer on the Ride on row takes its parent from a click on the planet."""
    client.call("load", path=str(COUPLING_SAMPLE))
    client.call("set_view", lat=PICK_VIEW[0], lon=PICK_VIEW[1], angle=0.0, zoom=1.0,
                show_map=False)
    client.call("set_time", time=COUPLED_AT)
    green = centroid_of(client, "Green Moved")
    green_uuid = client.call("get_selected")["feature"]["uuid"]
    client.call("select", title="Red Triangle")

    row = coupling_row(client)
    check(row["pick"] and not row["picking"],
          f"the pointer is offered and is not armed to start with: {row}")

    client.call("coupling", pick=True)
    check(coupling_row(client)["picking"], "pressing it arms the pick")
    status = client.call("get_status")["status"]["measure"]
    check(status == "Pick the feature to ride on", f"and the status bar says so: {status!r}")

    # A click on the ocean says why and leaves the pointer armed.
    screen = client.call("latlon_to_screen", lat=PICK_EMPTY[0], lon=PICK_EMPTY[1])["screen"]
    if not check(screen is not None, f"{PICK_EMPTY} is on screen"):
        return
    pixel = client.call("get_pixel", x=screen[0], y=screen[1])["color"]
    if not check(dominant(pixel) == "", f"and nothing is drawn there: {pixel}"):
        return
    client.call("click", x=screen[0], y=screen[1])
    status = client.call("get_status")["status"]["measure"]
    check(coupling_row(client)["picking"] and status == "Click a feature to ride on it.",
          f"a click on the ocean stays in the mode with the reason: {status!r}")

    # And so does a click on the feature that is doing the riding.
    own = world_centroid(client)
    screen = client.call("latlon_to_screen", lat=own[0], lon=own[1])["screen"]
    if not check(screen is not None, f"the feature itself is on screen at {own}"):
        return
    client.call("click", x=screen[0], y=screen[1])
    status = client.call("get_status")["status"]["measure"]
    check(coupling_row(client)["picking"] and status == "A feature cannot ride on itself.",
          f"a click on the feature itself does too: {status!r}")

    # A click on the green craton picks it, and nothing else moves.
    planet = client.call("latlon_to_screen", lat=PICK_VIEW[0], lon=PICK_VIEW[1])["screen"]
    screen = client.call("latlon_to_screen", lat=green[0], lon=green[1])["screen"]
    if not check(screen is not None, f"the green craton is on screen at {green}"):
        return
    client.call("click", x=screen[0], y=screen[1])
    row = coupling_row(client)
    check(row["parent"] == "Green Moved" and not row["picking"],
          f"a click on the green craton picks it and ends the mode: {row}")
    check(client.call("get_selected")["feature"]["title"] == "Red Triangle",
          "the selection is still the feature that asked for the parent")
    check(client.call("get_tool")["tool"] == "move", "and the tool is still the Move tool")
    check(client.call("latlon_to_screen", lat=PICK_VIEW[0], lon=PICK_VIEW[1])["screen"] == planet,
          "and the planet did not move")

    # Couple works on the picked parent the way it does on a listed one.
    client.call("coupling", button="Couple")
    spans = client.call("get_selected")["feature"]["couplings"]
    check(spans == [{"from": COUPLED_AT, "to": 0.0, "parent": green_uuid}],
          f"Couple then rides on what was clicked: {spans}")

    # Escape puts the pointer away.
    client.call("coupling", pick=True)
    check(coupling_row(client)["picking"], "the pointer is armed again")
    client.call("key", key="Escape")
    row = coupling_row(client)
    status = client.call("get_status")["status"]["measure"]
    check(not row["picking"] and status != "Pick the feature to ride on",
          f"and Escape ends it: {row['picking']}, {status!r}")


# The cut in time, on a parent that turns over the whole timeline: the rider is
# coupled at RIGID_COUPLED_AT, dragged on its own at RIGID_DRAGGED_AT and then
# decoupled between the two. A rider that has not been dragged keeps its
# distance from the parent exactly; the drag is what moves it against the
# parent, and the decoupling leaves every time older than itself as the drag
# left it, dropping only the keyframe it wrote.
# See Docs/Time.md#a-coupling-edit-is-a-cut-in-time.
RIGID_COUPLED_AT = 900.0
RIGID_DECOUPLED_AT = 500.0
RIGID_DRAGGED_AT = 200.0
# The times between the two the checks below walk through.
RIGID_SAMPLES = (RIGID_COUPLED_AT, 800.0, 700.0, 600.0, RIGID_DECOUPLED_AT)


def rider_gaps(client: AutomationClient) -> dict[float, float]:
    """How far the rider is from its parent at each sampled time, in degrees."""
    gaps = {}
    for time in RIGID_SAMPLES:
        client.call("set_time", time=time)
        gaps[time] = angular_distance(centroid_of(client, "Blue Quad"),
                                      centroid_of(client, "Red Triangle"))
    return gaps


def turn_parent(client: AutomationClient) -> bool:
    """Drag Red Triangle at each end of the timeline, so it turns all the way through."""
    client.call("select", title="Red Triangle")
    for time, by_lat, by_lon in ((1000.0, 0.0, -15.0), (0.0, 10.0, 20.0)):
        client.call("set_time", time=time)
        lat, lon = world_centroid(client)
        if not drag(client, lat + by_lat, lon + by_lon):
            return False
    return True


def run_rigid_coupling_checks(client: AutomationClient) -> None:
    """A rider keeps its distance from the parent right down to where it is decoupled."""
    client.call("load", path=str(COUPLING_SAMPLE))
    client.call("set_view", lat=15.0, lon=20.0, angle=0.0)
    if not turn_parent(client):
        return

    client.call("select", title="Blue Quad")
    client.call("set_time", time=RIGID_COUPLED_AT)
    client.call("coupling", button="Couple", parent="Red Triangle")
    rigid = rider_gaps(client)
    apart = rigid[RIGID_COUPLED_AT]
    for time, gap in rigid.items():
        check(abs(gap - apart) < DRAG_TOLERANCE,
              f"a rider that is not dragged is {gap:.2f} degrees from the parent at {time} Ma,"
              f" as it was at {apart:.2f} when it was coupled")

    # A drag younger than where the rider will be decoupled, which is what moves
    # it against the parent, from the moment it is coupled to the drag itself.
    client.call("select", title="Blue Quad")
    client.call("set_time", time=RIGID_DRAGGED_AT)
    lat, lon = world_centroid(client)
    if not drag(client, lat - 8.0, lon + 8.0):
        return
    dragged = rider_gaps(client)
    check(abs(dragged[RIGID_DECOUPLED_AT] - apart) > DRAG_TOLERANCE,
          f"the drag moves it against the parent: {dragged[RIGID_DECOUPLED_AT]:.2f}")

    client.call("select", title="Blue Quad")
    client.call("set_time", time=RIGID_DECOUPLED_AT)
    client.call("coupling", button="Decouple")
    times = [k["time"] for k in client.call("get_selected")["feature"]["keyframes"]]
    check(times == [RIGID_DECOUPLED_AT, RIGID_COUPLED_AT],
          f"decoupling drops the keyframe the span covered younger than it: {times}")

    for time, gap in rider_gaps(client).items():
        check(abs(gap - dragged[time]) < DRAG_TOLERANCE,
              f"the rider and the parent keep the distance they had at {time} Ma:"
              f" {gap:.2f} against {dragged[time]:.2f}")

    client.call("set_time", time=RIGID_DECOUPLED_AT)
    left = centroid_of(client, "Blue Quad")
    for time in (400.0, RIGID_DRAGGED_AT, 0.0):
        client.call("set_time", time=time)
        stood = centroid_of(client, "Blue Quad")
        check(angular_distance(stood, left) < DRAG_TOLERANCE,
              f"and the rider holds its world pose at {time} Ma: {stood} against {left}")

    # And the pixels agree with the world rings the distances came from.
    for time in (RIGID_COUPLED_AT, RIGID_DECOUPLED_AT):
        client.call("set_time", time=time)
        for title, colour in (("Blue Quad", "blue"), ("Red Triangle", "red")):
            lat, lon = centroid_of(client, title)
            client.call("set_view", show_map=False, lat=lat, lon=lon, angle=0.0, zoom=1.0)
            # The feature under the pointer is drawn highlighted, so keep the
            # pointer well clear of the centroid, which is now facing the camera.
            away = client.call("latlon_to_screen", lat=lat - 45.0 if lat > 0 else lat + 45.0,
                               lon=lon)["screen"]
            if not check(away is not None, f"a place to park the pointer away from {title}"):
                return
            client.call("mouse_move", x=away[0], y=away[1])
            screen = client.call("latlon_to_screen", lat=lat, lon=lon)["screen"]
            pixel = client.call("get_pixel", x=screen[0], y=screen[1])["color"]
            check(dominant(pixel) == colour,
                  f"{title} is drawn at ({lat:.1f}, {lon:.1f}) at {time} Ma: {pixel}")
    client.call("set_view", lat=15.0, lon=20.0, angle=0.0, zoom=1.0, show_map=False)


def run_coupling_refusal_checks(client: AutomationClient) -> None:
    """A cycle is refused with the reason, and a deleted parent leaves the span broken."""
    client.call("select", title="Red Triangle")
    versions = undo_depth(client)
    client.call("coupling", button="Couple", parent="Blue Quad")
    dialog = client.call("get_dialog")["dialog"]
    if check(dialog is not None and "circle" in dialog["text"],
             f"coupling the parent to its own rider is refused: {dialog}"):
        client.call("dialog", button="OK")
    check(undo_depth(client) == versions and client.call("get_selected")["feature"]["couplings"] == [],
          "and changes nothing")

    client.call("menu", item="delete")
    client.call("select", title="Blue Quad")
    row = coupling_row(client)
    check([span["broken"] for span in row["spans"]] == [True],
          f"a deleted parent leaves the span in place, drawn as broken: {row['spans']}")
    client.call("menu", item="undo")
    client.call("select", title="Blue Quad")
    row = coupling_row(client)
    check([span["broken"] for span in row["spans"]] == [False], f"and undo mends it: {row['spans']}")


def run_coupling_round_trip(client: AutomationClient, folder: Path) -> None:
    """Save, load, undo and redo keep the spans."""
    client.call("select", title="Blue Quad")
    spans = client.call("get_selected")["feature"]["couplings"]
    saved = folder / "coupled.middle-earth"
    client.call("expect_file_dialog", path=str(saved))
    client.call("menu", item="save_as")
    client.call("load", path=str(saved))
    client.call("select", title="Blue Quad")
    check(client.call("get_selected")["feature"]["couplings"] == spans,
          f"save and load keep the spans: {spans}")

    client.call("coupling", button="Remove", index=0)
    check(client.call("get_selected")["feature"]["couplings"] == [], "Remove takes the span away")
    for item, wanted in (("undo", spans), ("redo", []), ("undo", spans)):
        client.call("menu", item=item)
        client.call("select", title="Blue Quad")
        got = client.call("get_selected")["feature"]["couplings"]
        check(got == wanted, f"{item} gives the spans {wanted}: {got}")


def run_colour_session(client: AutomationClient) -> None:
    """A colour picked in the panel reaches the globe."""
    open_mixed_geometry(client)
    client.call("select", title="Red Triangle")
    lat, lon = RED_TRIANGLE_PROBE
    screen = client.call("latlon_to_screen", lat=lat, lon=lon)["screen"]
    if not check(screen is not None, "the centroid of Red Triangle is on the visible hemisphere"):
        return

    client.call("set_property", field="color", value=[0.0, 0.0, 1.0, 1.0])
    # The feature under the pointer is drawn highlighted, which is a different
    # blue from the one the panel asked for.
    away = client.call("latlon_to_screen", lat=30.0, lon=15.0)["screen"]
    client.call("mouse_move", x=away[0], y=away[1])
    color = client.call("get_pixel", x=screen[0], y=screen[1])["color"]
    check(dominant(color) == "blue", f"the centroid is blue after the colour change: {color}")

    client.call("menu", item="undo")
    color = client.call("get_pixel", x=screen[0], y=screen[1])["color"]
    check(dominant(color) == "red", f"and red again after undo: {color}")

    # The opacity box beside the color sets the alpha of the same color.
    versions = undo_depth(client)
    client.call("set_property", field="opacity", value=50)
    panel = client.call("get_properties")["properties"]
    check(panel["opacity"] == 50 and panel["color"][3] == 0.5,
          f"the panel shows half opacity: {panel['opacity']}, {panel['color']}")
    feature_color = client.call("get_selected")["feature"]["color"]
    check(feature_color[3] == 0.5, f"which reaches the feature: {feature_color}")
    check(undo_depth(client) == versions + 1, "in one undo step")
    client.call("set_property", field="opacity", value=0)
    color = client.call("get_pixel", x=screen[0], y=screen[1])["color"]
    check(dominant(color) != "red", f"at none the Earth shows through: {color}")
    client.call("menu", item="undo")
    client.call("menu", item="undo")
    check(client.call("get_properties")["properties"]["opacity"] == 100,
          "and undo puts the opacity back")

    run_color_picker_checks(client)


# The default colour of each feature type, in the order Logic/feature_type.gd
# lists them: chocolate, crimson, gold, dark turquoise and medium purple. Every
# picker starts with these as its presets.
TYPE_COLORS = [
    (0.824, 0.412, 0.118),
    (0.863, 0.078, 0.235),
    (1.0, 0.843, 0.0),
    (0.0, 0.808, 0.820),
    (0.576, 0.439, 0.859),
]


def presets(client: AutomationClient) -> list[tuple[float, float, float]]:
    """The presets the Colour row's picker offers, rounded to compare."""
    panel = client.call("get_properties")["properties"]
    return [tuple(round(channel, 3) for channel in color[:3])
            for color in panel["color_presets"]]


def run_color_picker_checks(client: AutomationClient) -> None:
    """The tree row's swatch opens the picker the Colour row carries."""
    client.call("load", path=str(ROOT / "Tests" / "Data" / "craton.middle-earth"))
    # Something else selected to begin with, so the swatch has to select the
    # feature before the panel can open its picker.
    client.call("select", title="Cratons")
    check(not client.call("get_properties")["properties"]["color_picker_open"],
          "the colour picker starts closed")

    client.call("swatch", title="Old Shield")
    selected = client.call("get_selected")["feature"]["title"]
    check(selected == "Old Shield", f"the swatch selects the feature: {selected}")
    panel = client.call("get_properties")["properties"]
    check(panel["color_picker_open"], "and opens the picker of the Colour row")
    offered = presets(client)
    check(offered[:5] == TYPE_COLORS, f"which offers the five type colours: {offered}")

    client.call("key", key="Escape")
    check(not client.call("get_properties")["properties"]["color_picker_open"],
          "Escape closes the picker")

    # A colour committed on a feature is offered by every picker from then on,
    # so a palette built for one feature is a click away on the next.
    green = (0.0, 1.0, 0.0)
    check(green not in offered, "the picker does not offer green yet")
    client.call("set_property", field="color", value=[0.0, 1.0, 0.0, 1.0])
    client.call("swatch", title="Old Shield")
    grown = presets(client)
    check(grown == offered + [green],
          f"a committed colour is added as one more preset: {grown}")
    client.call("key", key="Escape")

    # The right click on the swatch still puts the type's default back, and
    # picks nothing.
    client.call("swatch", title="Old Shield", button="right")
    color = client.call("get_selected")["feature"]["color"]
    check(color[:3] != [0.0, 1.0, 0.0], f"a right click resets the colour: {color}")
    check(not client.call("get_properties")["properties"]["color_picker_open"],
          "and leaves the picker closed")


def refusal(client: AutomationClient, cmd: str, **params) -> str:
    """What the port said no with, or an empty string when it went through."""
    try:
        client.call(cmd, **params)
    except RuntimeError as error:
        return str(error)
    return ""


def row_icon(client: AutomationClient, title: str) -> str:
    """The file stem of the picture the feature's tree row is showing."""
    for feature in client.call("get_features")["features"]:
        if feature["title"] == title:
            return feature["row_icon"]
    return ""


def run_icon_checks(client: AutomationClient, folder: Path) -> None:
    """The glyph picked in the panel is the picture the tree row shows."""
    open_mixed_geometry(client)
    client.call("select", title="Red Triangle")
    panel = client.call("get_properties")["properties"]
    check(panel["icon"] == "", f"a feature starts with no icon: {panel['icon']}")
    check(panel["icons"][0] == "" and "mountain" in panel["icons"],
          f"the selector offers None first and the glyphs after it: {panel['icons']}")
    check(row_icon(client, "Red Triangle") == "RuleEnabled",
          "and its row shows the rule icon, as it did before there were any")

    check(refusal(client, "set_property", field="icon", value="sombrero") != "",
          "an icon the selector does not offer is refused")

    versions = undo_depth(client)
    client.call("set_property", field="icon", value="mountain")
    check(client.call("get_selected")["feature"]["icon"] == "mountain",
          "the icon reaches the feature")
    check(row_icon(client, "Red Triangle") == "mountain",
          f"and the tree row shows it: {row_icon(client, 'Red Triangle')}")
    check(undo_depth(client) == versions + 1, "in one undo step")

    saved = folder / "iconed.middle-earth"
    client.call("expect_file_dialog", path=str(saved))
    client.call("menu", item="save_as")
    client.call("load", path=str(saved))
    check(row_icon(client, "Red Triangle") == "mountain",
          "save and load keep it on the row")
    client.call("select", title="Red Triangle")
    check(client.call("get_properties")["properties"]["icon"] == "mountain",
          "and the panel shows it again")

    client.call("set_property", field="icon", value="")
    check(row_icon(client, "Red Triangle") == "RuleEnabled",
          "None puts the rule icon back")
    for item, wanted in (("undo", "mountain"), ("redo", "RuleEnabled"), ("undo", "mountain")):
        client.call("menu", item=item)
        got = row_icon(client, "Red Triangle")
        check(got == wanted, f"{item} gives the row {wanted}: {got}")

    # A group's row says whether the group is open, whatever is under it.
    client.call("select", title="Shapes")
    check(refusal(client, "set_property", field="icon", value="ocean") != "",
          "a group has no icon")


def run_globe_menu_session(client: AutomationClient) -> None:
    """Clone and delete from the right click menu on the globe."""
    open_mixed_geometry(client)
    lat, lon = RED_TRIANGLE_PROBE
    screen = client.call("latlon_to_screen", lat=lat, lon=lon)["screen"]
    if not check(screen is not None, "the red triangle is on the visible hemisphere"):
        return

    client.call("click", x=screen[0], y=screen[1], button="right")
    menu = client.call("get_context_menu")["context_menu"]
    check(menu["visible"], "a right click on the globe opens the menu")
    check([item["label"] for item in menu["items"]] == ["Duplicate", "Delete"],
          f"offering Duplicate and Delete: {menu['items']}")
    original = client.call("get_selected")["feature"]
    check(original["title"] == "Red Triangle",
          f"on the feature under the pointer: {original['title']}")

    before = len(client.call("get_features")["features"])
    client.call("context_menu", item="Duplicate")
    clone = client.call("get_selected")["feature"]
    features = {f["pnid"]: f for f in client.call("get_features")["features"]}
    check(len(features) == before + 1, "Duplicate adds one feature")
    check(clone["pnid"] != original["pnid"], "the clone has an identity of its own")
    check(clone["rings"] == original["rings"], "and the geometry of the original")
    check(features[clone["pnid"]]["depth"] == features[original["pnid"]]["depth"],
          "as a sibling beside it")

    client.call("click", x=screen[0], y=screen[1], button="right")
    check(client.call("get_context_menu")["context_menu"]["visible"], "the menu opens again")
    client.call("context_menu", item="Delete")
    check(len(client.call("get_features")["features"]) == before,
          "Delete takes one off again")
    client.call("menu", item="undo")
    check(len(client.call("get_features")["features"]) == before + 1,
          "and undo brings it back")


def run_edit_menu_session(client: AutomationClient) -> None:
    """The Edit menu runs the commands the feature tree toolbar runs.

    Copy records no undo version, so the menu has to learn about the clipboard
    some other way; without that, Paste stays disabled right after a Copy.
    Note that this puts a feature on the real clipboard of whoever is running it.
    """
    open_mixed_geometry(client)
    client.call("select", title="Red Triangle")
    before = len(client.call("get_features")["features"])

    copied = client.call("get_selected")["feature"]["uuid"]
    client.call("menu", item="copy")
    try:
        client.call("menu", item="paste")
    except RuntimeError as error:
        check(False, f"Edit > Paste is available right after Edit > Copy: {error}")
    else:
        check(len(client.call("get_features")["features"]) == before + 1,
              "Edit > Copy then Edit > Paste adds a feature")
        # The clipboard carries the uuid of the feature it was copied from; a
        # paste is another feature and gets one of its own, or a topology
        # naming either of them could not tell them apart.
        pasted = client.call("get_selected")["feature"]["uuid"]
        check(pasted != copied and pasted != "",
              f"the pasted feature has a uuid of its own: {pasted}")
        client.call("menu", item="undo")

    client.call("select", title="Blue Ridge")
    client.call("menu", item="delete")
    check(len(client.call("get_features")["features"]) == before - 1,
          "Edit > Delete removes the selected feature")
    check("Blue Ridge" not in titles_of(client), "the one that was selected")
    client.call("menu", item="undo")
    check("Blue Ridge" in titles_of(client), "and undo brings it back")


# A small triangle around lat/lon (0, 0), with its centroid on the equator so
# that turning it about the poles keeps it there. The time scenario relies on
# that: a point on the equator turned about the poles stays on the equator, so
# the path between two of its positions is a stretch of the equator itself.
TIME_TRIANGLE = [(-6.0, -6.0), (6.0, -6.0), (0.0, 6.0)]

# The two times the feature is moved at, and the one it is read back at.
TIME_A = 0.0
TIME_B = 200.0
TIME_MIDDLE = 100.0

# Where the anchor is dragged to at each of those times, in longitude. The
# feature ends up centred on the midpoint of the two at TIME_MIDDLE.
LONGITUDE_A = 30.0
LONGITUDE_B = -30.0

# How far off a scripted drag may leave the feature, in degrees. A drag lands on
# whichever pixel the point rounds to, so it is a pixel or so wide.
DRAG_TOLERANCE = 1.0


def unit(lat: float, lon: float) -> tuple[float, float, float]:
    """A latitude and longitude in degrees as a point on the unit sphere."""
    lat_rad, lon_rad = math.radians(lat), math.radians(lon)
    return (
        math.cos(lat_rad) * math.cos(lon_rad),
        math.sin(lat_rad),
        math.cos(lat_rad) * math.sin(lon_rad),
    )


def centroid(rings: list[list[list[float]]]) -> tuple[float, float]:
    """The middle of a feature's vertices, as a latitude and longitude."""
    points = [unit(v[0], v[1]) for ring in rings for v in ring]
    total = [sum(p[i] for p in points) for i in range(3)]
    length = math.sqrt(sum(c * c for c in total))
    x, y, z = (c / length for c in total)
    return math.degrees(math.asin(y)), math.degrees(math.atan2(z, x))


def world_centroid(client: AutomationClient) -> tuple[float, float]:
    """Where the selected feature sits on the globe at the current time."""
    return centroid(client.call("get_selected")["feature"]["world_rings"])


def drag(client: AutomationClient, to_lat: float, to_lon: float) -> bool:
    """Drag the selected feature by its middle to a latitude and longitude."""
    lat, lon = world_centroid(client)
    grab = client.call("latlon_to_screen", lat=lat, lon=lon)["screen"]
    target = client.call("latlon_to_screen", lat=to_lat, lon=to_lon)["screen"]
    if not check(grab is not None and target is not None,
                 f"the drag from ({lat:.1f}, {lon:.1f}) to ({to_lat}, {to_lon}) is visible"):
        return False
    client.call("press", x=grab[0], y=grab[1])
    client.call("mouse_move", x=target[0], y=target[1])
    client.call("release", x=target[0], y=target[1])
    return True


def run_time_session(client: AutomationClient) -> None:
    """Move a feature at two times and read it back between them."""
    start_new_document(client)
    client.call("toolbar", button="AddFeature")
    client.call("set_tool", tool="draw")
    if not draw(client, TIME_TRIANGLE):
        return
    client.call("key", key="Enter")
    client.call("set_property", field="color", value=[0.0, 1.0, 0.0, 1.0])

    check(client.call("get_selected")["feature"]["keyframes"] == [],
          "a feature that has never been moved holds no keyframes")

    # Move it at one time and again at another. The first move gives it its
    # only keyframe, so it stands still everywhere until the second one.
    client.call("set_time", time=TIME_A)
    if not drag(client, 0.0, LONGITUDE_A):
        return
    keyframes = client.call("get_selected")["feature"]["keyframes"]
    check([k["time"] for k in keyframes] == [TIME_A],
          f"the move writes the keyframe at {TIME_A} Ma: {keyframes}")

    client.call("set_time", time=TIME_B)
    check(abs(world_centroid(client)[1] - LONGITUDE_A) < DRAG_TOLERANCE,
          "one keyframe holds the feature still at every other time")
    if not drag(client, 0.0, LONGITUDE_B):
        return
    keyframes = client.call("get_selected")["feature"]["keyframes"]
    check([k["time"] for k in keyframes] == [TIME_A, TIME_B],
          f"the second move adds a keyframe, sorted by time: {keyframes}")

    # Halfway between the two, the feature is halfway along the equator that
    # joins the two positions it was left at.
    client.call("set_time", time=TIME_MIDDLE)
    lat, lon = world_centroid(client)
    check(abs(lat) < DRAG_TOLERANCE,
          f"halfway through, the middle is still on the great circle: latitude {lat:.3f}")
    middle = (LONGITUDE_A + LONGITUDE_B) / 2.0
    check(abs(lon - middle) < DRAG_TOLERANCE,
          f"and halfway between the two longitudes: {lon:.3f}, wanted {middle}")
    check(min(LONGITUDE_A, LONGITUDE_B) < lon < max(LONGITUDE_A, LONGITUDE_B),
          "which is between the two positions rather than beyond one of them")

    # And the globe agrees with the numbers.
    screen = client.call("latlon_to_screen", lat=lat, lon=lon)["screen"]
    if check(screen is not None, "the middle is on the visible hemisphere"):
        color = client.call("get_pixel", x=screen[0], y=screen[1])["color"]
        check(dominant(color) == "green",
              f"a probe at the middle shows the feature colour: {color}")

    run_visibility_checks(client)
    run_timeline_checks(client)


def run_visibility_checks(client: AutomationClient) -> None:
    """A feature outside its time range is neither drawn nor hit tested."""
    client.call("set_property", field="time_to", value=0)
    client.call("set_property", field="time_from", value=1000)

    outside = 1500.0
    client.call("set_time", time=outside)
    feature = client.call("get_selected")["feature"]
    check(not feature["exists_now"], f"the feature is not there at {outside} Ma")

    lat, lon = centroid(feature["world_rings"])
    screen = client.call("latlon_to_screen", lat=lat, lon=lon)["screen"]
    if not check(screen is not None, "where it would be is on the visible hemisphere"):
        return
    color = client.call("get_pixel", x=screen[0], y=screen[1])["color"]
    check(dominant(color) != "green",
          f"so the Earth shows through where it would be: {color}")
    check(client.call("get_features")["features"] is not None, "the tree still lists it")

    # The same probe point, with the time range widened to take that time in.
    client.call("set_property", field="time_from", value=2000)
    check(client.call("get_selected")["feature"]["exists_now"],
          "widening the range brings it back")
    color = client.call("get_pixel", x=screen[0], y=screen[1])["color"]
    check(dominant(color) == "green", f"and the same probe is green again: {color}")


def run_timeline_checks(client: AutomationClient) -> None:
    """The time control: the markers, the step buttons and playback."""
    client.call("set_animation", animation={
        "start": 400.0, "end": 0.0, "speed": 50.0, "loop": False,
    })
    client.call("set_skip", skip=100.0)
    timeline = client.call("get_timeline")["timeline"]
    check(timeline["markers"] == [TIME_A, TIME_B],
          f"the keyframes of the selected feature are marked: {timeline['markers']}")
    check(timeline["slider_range"] == [-400.0, 0.0],
          f"the slider runs from the oldest end on the left: {timeline['slider_range']}")

    client.call("timeline", button="Reset")
    check(client.call("get_time")["time"] == 400.0, "Reset goes to the start of the animation")
    check(client.call("get_timeline")["timeline"]["slider"] == -400.0,
          "and the slider follows the time")

    client.call("timeline", button="Younger")
    check(client.call("get_time")["time"] == 300.0, "a skip towards the younger end")
    check(client.call("get_timeline")["timeline"]["typed"] == 300.0,
          "which the typed time field shows as well")
    client.call("timeline", button="Older")
    check(client.call("get_time")["time"] == 400.0, "and one back towards the older")

    # The skip is a number beside the buttons, changed on the spot, and the two
    # shortcuts jump by it wherever the focus is.
    client.call("set_skip", skip=10.0)
    check(client.call("get_timeline")["timeline"]["skip"] == 10.0, "the skip box takes a new value")
    client.call("key", key="PageDown")
    check(client.call("get_time")["time"] == 390.0, "Page Down skips towards the younger end by it")
    client.call("menu", item="skip_older")
    check(client.call("get_time")["time"] == 400.0, "and Time > Skip Older comes back")
    client.call("key", key="PageUp")
    check(client.call("get_time")["time"] == 400.0, "a skip never leaves the animation range")
    run_keyframe_jump_checks(client)

    # A time typed in reaches the slider through the document, the same way a
    # time set from a script does.
    client.call("set_time", time=123.0)
    timeline = client.call("get_timeline")["timeline"]
    check(timeline["typed"] == 123.0 and timeline["slider"] == -123.0,
          f"a time set anywhere reaches both the field and the slider: {timeline['slider']}")

    client.call("set_animation", animation={"start": 400.0})
    client.call("timeline", button="Reset")

    # Slow enough that it cannot run out between the request that starts it and
    # the one that stops it: a request waits two frames, and at 50 My a second a
    # frame is a fraction of a million years.
    client.call("set_animation", animation={"speed": 50.0})
    client.call("timeline", button="Reset")
    client.call("timeline", button="Play")
    check(client.call("get_timeline")["timeline"]["playing"], "Play starts the animation")
    client.call("timeline", button="Pause")
    moved = 400.0 - client.call("get_time")["time"]
    check(not client.call("get_timeline")["timeline"]["playing"], "and Pause stops it")
    check(0.0 < moved < 50.0,
          f"having moved the time on by less than a second's worth: {moved} My")

    # Playing to the end without looping stops there rather than wrapping.
    client.call("set_animation", animation={"speed": 100000.0})
    client.call("timeline", button="Reset")
    client.call("timeline", button="Play")
    for _ in range(20):
        if not client.call("get_timeline")["timeline"]["playing"]:
            break
    check(client.call("get_time")["time"] == 0.0,
          f"the animation stops on the end time: {client.call('get_time')['time']}")
    check(not client.call("get_timeline")["timeline"]["playing"], "and stops playing there")

    # Play at the end starts again from the beginning.
    client.call("set_animation", animation={"speed": 50.0})
    client.call("timeline", button="Play")
    client.call("timeline", button="Pause")
    check(client.call("get_time")["time"] > 300.0,
          f"Play from the end starts over: {client.call('get_time')['time']}")

    run_space_checks(client)


def run_space_checks(client: AutomationClient) -> None:
    """Space plays and pauses, unless the keyboard belongs to a text field."""
    client.call("set_animation", animation={"speed": 50.0})
    client.call("timeline", button="Reset")
    client.call("key", key="Space")
    check(client.call("get_timeline")["timeline"]["playing"], "Space starts the animation")
    client.call("key", key="Space")
    check(not client.call("get_timeline")["timeline"]["playing"], "and Space again pauses it")
    moved = 400.0 - client.call("get_time")["time"]
    check(0.0 < moved < 50.0, f"the time ran on while it played: {moved} My")

    # A name being typed is a name being typed. The field takes the space and
    # the animation hears nothing.
    focus = client.call("focus", widget="Name")
    if check(focus["focus"] == "Name", f"the name field can be typed in: {focus['focus']}"):
        before = client.call("get_properties")["properties"]["name"]
        client.call("key", key="Space")
        after = client.call("get_properties")["properties"]["name"]
        check(after != before and after.replace(" ", "") == before.replace(" ", ""),
              f"Space types a space into the name: {before!r} became {after!r}")
        check(not client.call("get_timeline")["timeline"]["playing"],
              "and the animation did not start")
        client.call("set_property", field="name", value=before)

    # A click leaves the focus on the button it pressed, and a focused Button
    # answers Space itself. Play must not be pressed a second time.
    client.call("timeline", button="Reset")
    focus = client.call("focus", widget="Play")
    if check(focus["focus"] == "Play", f"the Play button holds the focus: {focus['focus']}"):
        client.call("timeline", button="Play")
        check(client.call("get_timeline")["timeline"]["playing"], "the Play button starts playback")
        client.call("key", key="Space")
        check(not client.call("get_timeline")["timeline"]["playing"],
              "and Space pauses rather than pressing Play again")
    client.call("focus", release=True)
    client.call("timeline", button="Reset")

    # A dialog has the keyboard while it is up, so Space is its own.
    client.call("menu", item="about")
    client.call("key", key="Space")
    check(not client.call("get_timeline")["timeline"]["playing"],
          "Space over an open dialog does not reach the animation")
    if client.call("get_dialog")["dialog"] is not None:
        client.call("dialog", button="OK")


def run_keyframe_jump_checks(client: AutomationClient) -> None:
    """The keyframe marks are clickable and the >> and << buttons walk them."""
    # The feature holds keyframes at TIME_A and TIME_B, the present and 200 Ma.
    client.call("set_time", time=123.456)
    client.call("timeline", button="YoungerKeyframe")
    check(client.call("get_time")["time"] == TIME_A,
          f"the younger keyframe button lands on {TIME_A}: {client.call('get_time')['time']}")
    client.call("menu", item="keyframe_older")
    check(client.call("get_time")["time"] == TIME_B,
          f"Time > Older Keyframe lands on {TIME_B}: {client.call('get_time')['time']}")
    client.call("key", key="PageUp", ctrl=True)
    check(client.call("get_time")["time"] == TIME_B,
          "and there is no older keyframe to go on to")
    timeline = client.call("get_timeline")["timeline"]
    check(not timeline["playing"], "a jump is not playback")

    # A click on a mark lands on the keyframe exactly, whatever the digits.
    client.call("set_time", time=333.0)
    marks = client.call("get_timeline")["timeline"]["marker_screen"]
    if check(len(marks) == 2, f"both keyframes are marked on the strip: {marks}"):
        for time, x, y in marks:
            client.call("click", x=x, y=y)
            check(client.call("get_time")["time"] == time,
                  f"clicking the mark at {x:.0f} lands on {time} Ma exactly: {client.call('get_time')['time']}")
        # Between two marks there is nothing to click on.
        (time_a, x_a, y_a), (time_b, x_b, _) = marks
        client.call("set_time", time=333.0)
        client.call("click", x=(x_a + x_b) / 2.0, y=y_a)
        check(client.call("get_time")["time"] == 333.0, "a click between the marks does nothing")


### The Circle scenario


def angular_distance(a: tuple[float, float], b: tuple[float, float]) -> float:
    """The angle between two lat/lon points, in degrees."""
    lat_a, lat_b = math.radians(a[0]), math.radians(b[0])
    half_lat = math.sin((lat_b - lat_a) / 2.0)
    half_lon = math.sin(math.radians(b[1] - a[1]) / 2.0)
    h = half_lat ** 2 + math.cos(lat_a) * math.cos(lat_b) * half_lon ** 2
    return math.degrees(2.0 * math.asin(math.sqrt(min(1.0, h))))


# The circle the scenario builds: a centre near the middle of the default view
# and a radius wide enough to click accurately but well inside the hemisphere.
CIRCLE_CENTRE = (0.0, 0.0)
CIRCLE_RADIUS = 15.0
CIRCLE_SEGMENTS = 12

# How far a vertex may sit from the radius it was asked for. The clicks go
# through the globe, so what comes back is a point picked on the sphere rather
# than the number that was typed.
CIRCLE_TOLERANCE = 0.5


def build_circle(client: AutomationClient, kind: str, points: list[tuple[float, float]]) -> dict:
    """Start a document, click the points with the Circle tool and commit.

    The Circle tool is offered on a Circle, which is picked in the Properties
    panel; the Outline switch beside the segment box says whether the circle is
    committed as a polygon or as a polyline.
    """
    start_new_document(client)
    # The segment count is set while its box is hidden, so the Circle tool has to
    # pick up a value typed in another tool.
    client.call("set_tool", tool="move", segments=CIRCLE_SEGMENTS)
    tool = client.call("get_tool")
    check(not tool["segments_visible"], f"the Segments box is hidden in the Move tool ({kind})")
    check(tool["segments"] == CIRCLE_SEGMENTS, f"but set_tool still sets it: {tool['segments']}")
    # Showing the box must fit in the toolbar's spare width. If it did not, the
    # splitter would give way and the planet would jump sideways under the pointer.
    before = client.call("latlon_to_screen", lat=0.0, lon=0.0)["screen"]
    client.call("toolbar", button="AddFeature")
    check(not client.call("get_tool")["circle_enabled"],
          f"the Circle tool waits for a Circle ({kind})")
    client.call("set_property", field="feature_type", value="circle")
    tool = client.call("get_tool")
    check(tool["tool"] == "circle", f"picking the type arms the Circle tool ({kind})")
    check(not tool["draw_enabled"], f"and takes the Draw tool away ({kind})")
    client.call("set_tool", tool="circle", outline=kind == "polyline")
    tool = client.call("get_tool")
    check(tool["segments_visible"], f"which shows the Segments box ({kind})")
    after = client.call("latlon_to_screen", lat=0.0, lon=0.0)["screen"]
    check(after == before, f"without moving the planet: {before} then {after}")
    if not draw(client, points):
        return {}
    return client.call("get_tool")


def run_circle_session(client: AutomationClient) -> None:
    """A circle from a centre and a rim point, and one through three points."""
    rim = (CIRCLE_CENTRE[0] + CIRCLE_RADIUS, CIRCLE_CENTRE[1])
    tool = build_circle(client, "polygon", [CIRCLE_CENTRE, rim])
    if not tool:
        return
    if check(tool["circle"] is not None, "two clicks describe a circle"):
        centre = tuple(tool["circle"]["centre"])
        check(angular_distance(centre, CIRCLE_CENTRE) < CIRCLE_TOLERANCE,
              f"its centre is where the first click landed: {centre}")
        check(abs(tool["circle"]["radius"] - CIRCLE_RADIUS) < CIRCLE_TOLERANCE,
              f"its radius reaches the second click: {tool['circle']['radius']:.4f}")

    client.call("key", key="Enter")
    feature = client.call("get_selected")["feature"]
    if check(len(feature["rings"]) == 1, "the circle is committed as one part"):
        ring = feature["rings"][0]
        check(len(ring) == CIRCLE_SEGMENTS,
              f"a polygon holds one vertex per segment: {len(ring)}")
        worst = max(abs(angular_distance(tuple(v), CIRCLE_CENTRE) - CIRCLE_RADIUS) for v in ring)
        check(worst < CIRCLE_TOLERANCE,
              f"every vertex sits the radius from the centre, within {worst:.4f} degrees")
    feature = client.call("get_selected")["feature"]
    check(feature["geometry_kind"] == "polygon", "and the feature is a polygon")
    check(feature["feature_type"] == "circle",
          f"which the Circle tool makes a Circle: {feature['feature_type']!r}")

    # A polyline of the same segment count draws the whole circle, so it repeats
    # its first vertex at the end.
    tool = build_circle(client, "polyline", [CIRCLE_CENTRE, rim])
    if tool:
        client.call("key", key="Enter")
        feature = client.call("get_selected")["feature"]
        if check(len(feature["rings"]) == 1, "the polyline circle is committed as one part"):
            check(len(feature["rings"][0]) == CIRCLE_SEGMENTS + 1,
                  f"and holds a vertex more than it has segments: {len(feature['rings'][0])}")
        check(feature["geometry_kind"] == "polyline",
              f"Outline commits the circle as a polyline: {feature['geometry_kind']}")
        check(feature["feature_type"] == "circle", "a polyline circle is a Circle too")

    # Three points on the rim describe the same circle, without its centre ever
    # being clicked.
    on_rim = [
        (CIRCLE_CENTRE[0] + CIRCLE_RADIUS, CIRCLE_CENTRE[1]),
        (CIRCLE_CENTRE[0] - CIRCLE_RADIUS, CIRCLE_CENTRE[1]),
        (CIRCLE_CENTRE[0], CIRCLE_CENTRE[1] + CIRCLE_RADIUS),
    ]
    tool = build_circle(client, "polygon", on_rim)
    if not tool:
        return
    if check(tool["circle"] is not None, "three clicks describe a circle"):
        centre = tuple(tool["circle"]["centre"])
        check(angular_distance(centre, CIRCLE_CENTRE) < CIRCLE_TOLERANCE,
              f"whose centre was never clicked: {centre}")
        check(abs(tool["circle"]["radius"] - CIRCLE_RADIUS) < CIRCLE_TOLERANCE,
              f"and whose radius is the one the points were taken from: "
              f"{tool['circle']['radius']:.4f}")

    client.call("key", key="Escape")
    check(client.call("get_tool")["circle"] is None, "Escape drops the clicked points")
    check(client.call("get_selected")["feature"]["rings"] == [],
          "and leaves the feature without geometry")


### The Topology scenario

# Two polylines on the equator, well apart, and the point on each one that is
# clicked to add it to the topology. A boundary built from them holds one
# section per line and nothing across the gap between them.
WEST_LINE = [(0.0, -40.0), (0.0, -30.0), (0.0, -20.0)]
EAST_LINE = [(0.0, 20.0), (0.0, 30.0), (0.0, 40.0)]
WEST_CLICK = (0.0, -35.0)
EAST_CLICK = (0.0, 35.0)

# Where the western line is dragged to at TOPOLOGY_TIME, and how far a resolved
# vertex may sit from where the line it came from is.
TOPOLOGY_TIME = 100.0
MOVED_LONGITUDE = -10.0
TOPOLOGY_TOLERANCE = 0.5


def add_polyline(client: AutomationClient, name: str,
                 points: list[tuple[float, float]]) -> bool:
    """Add a named feature and draw one polyline on it."""
    client.call("toolbar", button="AddFeature")
    client.call("set_property", field="name", value=name)
    client.call("set_property", field="feature_type", value="line")
    client.call("set_tool", tool="draw")
    if not draw(client, points):
        return False
    client.call("key", key="Enter")
    return True


def click_at(client: AutomationClient, at: tuple[float, float]) -> bool:
    """Click a point of the globe named by latitude and longitude."""
    screen = client.call("latlon_to_screen", lat=at[0], lon=at[1])["screen"]
    if not check(screen is not None, f"the point {at} is on the visible hemisphere"):
        return False
    client.call("click", x=screen[0], y=screen[1])
    return True


def run_topology_session(client: AutomationClient) -> None:
    """Build a line topology by clicking two features, then edit and move it."""
    start_new_document(client)
    if not add_polyline(client, "West Line", WEST_LINE):
        return
    if not add_polyline(client, "East Line", EAST_LINE):
        return

    # A third feature, holding nothing, becomes the topology.
    client.call("toolbar", button="AddFeature")
    client.call("set_property", field="name", value="Boundary")
    client.call("set_property", field="feature_type", value="topology")
    check(client.call("get_tool")["tool"] == "topology",
          "picking the Topology type arms the Topology tool")

    if not click_at(client, WEST_CLICK) or not click_at(client, EAST_CLICK):
        return

    feature = client.call("get_selected")["feature"]
    check(feature["geometry_kind"] == "topology",
          f"clicking a feature makes the empty one a topology: {feature['geometry_kind']}")
    sections = feature.get("sections", [])
    if not check(len(sections) == 2, f"one section per feature clicked: {len(sections)}"):
        return
    check([s["problem"] for s in sections] == ["", ""], "both sections resolve")
    check(len(feature["rings"]) == 2,
          "and each becomes a part of its own, so the gap between them is not joined")

    # What a section resolves to is the run of vertices of the feature it names.
    west_vertices = [tuple(v) for v in sections[0]["vertices"]]
    check(worst_offset(sections[0]["vertices"], WEST_LINE) < TOPOLOGY_TOLERANCE,
          f"the first section runs along the western line: {west_vertices}")
    check(worst_offset(sections[1]["vertices"], EAST_LINE) < TOPOLOGY_TOLERANCE,
          "and the second along the eastern one")

    # Reversing a section from the panel turns that run round and leaves the
    # other one alone.
    client.call("sections", button="Reverse", index=0)
    sections = client.call("get_selected")["feature"]["sections"]
    check(sections[0]["reversed"] and not sections[1]["reversed"],
          "Reverse turns the section that was picked and not the other")
    check(worst_offset(sections[0]["vertices"], list(reversed(WEST_LINE)))
          < TOPOLOGY_TOLERANCE,
          "so its vertices come back the other way round")
    panel = client.call("get_properties")["properties"]
    check([row["way"] for row in panel["sections"]] == ["back", "on"],
          f"and the panel says which way each section runs: {panel['sections']}")

    run_moved_section_checks(client)
    run_broken_section_checks(client)


def run_moved_section_checks(client: AutomationClient) -> None:
    """A topology follows the feature a section runs along when it moves."""
    boundary = client.call("get_selected")["feature"]["pnid"]

    # Move the western line at a later time. The drag writes its keyframe there,
    # so the line is where it was drawn at the present and elsewhere at 100 Ma.
    client.call("select", title="West Line")
    check(client.call("get_selected")["feature"]["geometry_kind"] == "polyline",
          "the western line is selected to be moved")
    # Selecting a feature the Topology tool cannot build on puts the Move tool
    # back, so the drag below is a drag rather than another section.
    check(client.call("get_tool")["tool"] == "move",
          "the Topology tool gives way to Move on a feature holding vertices")

    # Pin where the line is at the present first. Without a keyframe there, the
    # one the drag writes would be the only one and would hold at every time.
    # The document opened at the oldest age, so go to the present to pin it.
    client.call("set_time", time=0.0)
    client.call("keyframes", button="Key")
    client.call("set_time", time=TOPOLOGY_TIME)
    if not drag(client, 0.0, MOVED_LONGITUDE):
        return
    moved = client.call("get_selected")["feature"]["world_rings"][0]
    check(abs(centroid([moved])[1] - MOVED_LONGITUDE) < TOPOLOGY_TOLERANCE,
          f"the drag really moved it, to {centroid([moved])[1]:.3f}")

    client.call("select", pnid=boundary)
    sections = client.call("get_selected")["feature"]["sections"]
    # The section was reversed, so it holds the moved line back to front.
    resolved = list(reversed(sections[0]["vertices"]))
    check(worst_offset(resolved, [tuple(v) for v in moved]) < TOPOLOGY_TOLERANCE,
          f"at {TOPOLOGY_TIME} Ma the section follows the line it runs along: {resolved}")
    check(worst_offset(sections[1]["vertices"], EAST_LINE) < TOPOLOGY_TOLERANCE,
          "while the section whose feature did not move is where it was")

    client.call("set_time", time=0.0)
    sections = client.call("get_selected")["feature"]["sections"]
    check(worst_offset(list(reversed(sections[0]["vertices"])), WEST_LINE)
          < TOPOLOGY_TOLERANCE,
          "and at the present it is back where the line was drawn")


def run_broken_section_checks(client: AutomationClient) -> None:
    """A section whose feature is deleted is shown as broken, not dropped."""
    boundary = client.call("get_selected")["feature"]["pnid"]
    client.call("select", title="West Line")
    client.call("menu", item="delete")

    client.call("select", pnid=boundary)
    sections = client.call("get_selected")["feature"]["sections"]
    if not check(len(sections) == 2, "the deleted feature does not take its section with it"):
        return
    check(sections[0]["problem"] != "", f"which is broken instead: {sections[0]['problem']}")
    check(sections[1]["problem"] == "", "and the other section is untouched")
    panel = client.call("get_properties")["properties"]
    check([row["broken"] for row in panel["sections"]] == [True, False],
          f"the panel marks the broken one: {panel['sections']}")

    # An undo brings the feature back, and the section with it. The uuid is what
    # makes that work: the tree that comes back is a clone, so nothing the
    # section could have held on to is the same object.
    client.call("toolbar", button="Undo")
    client.call("select", pnid=boundary)
    sections = client.call("get_selected")["feature"]["sections"]
    check([s["problem"] for s in sections] == ["", ""],
          "undoing the deletion mends the broken section")

    # Remove is the way to take a section out on purpose.
    client.call("sections", button="Remove", index=1)
    check(len(client.call("get_selected")["feature"]["sections"]) == 1,
          "Remove takes the picked section out of the topology")


### The Vertex, Measure and Split scenarios

# A triangle around the middle of the default view, large enough that its
# vertices are well apart on screen.
VERTEX_POLYGON = [(-8.0, -8.0), (8.0, -8.0), (0.0, 8.0)]

# Where the feature is moved to at time zero, and the time the vertices are
# then edited at, which is between the one keyframe and nothing, so the feature
# is somewhere other than where its vertices are stored.
VERTEX_LONGITUDE = 25.0
VERTEX_TIME = 100.0

# How far off the edge an inserted vertex may land. The insert follows the
# straight line between the two vertices on screen, and the edge itself is a
# great circle arc, so the two part company slightly over a long edge.
EDGE_TOLERANCE = 0.5

# A second polygon, off to the side, whose vertex the first one snaps onto.
SNAP_POLYGON = [(-8.0, 30.0), (8.0, 30.0), (0.0, 46.0)]

# How many pixels short of the target the snapped vertex is dropped: inside
# Application.SNAP_PIXELS, so the snap takes it the rest of the way.
SNAP_SHORT_PIXELS = 6.0

# Twenty degrees along the equator, a distance the radius turns into a number
# the check works out for itself rather than reading off the status bar. The
# radius is Measure.EARTH_RADIUS_KM, which the preference defaults to.
MEASURE_POINTS = [(0.0, -10.0), (0.0, 10.0)]
MEASURE_DEGREES = 20.0
EARTH_RADIUS_KM = 6371.0

# A five vertex polygon, so a cut between two vertices leaves three on one side.
SPLIT_POLYGON = [(-8.0, -8.0), (8.0, -8.0), (10.0, 4.0), (0.0, 10.0), (-8.0, 6.0)]


def run_projection_session(client: AutomationClient) -> None:
    """The five map projections, the zoom and the camera, driven from the toolbar."""
    sample = ROOT / "Tests" / "Data" / "two_cratons.middle-earth"
    client.call("load", path=str(sample))
    client.call("set_view", lat=0.0, lon=0.0, angle=0.0, zoom=1.0, show_map=False, projection=0)

    lat, lon = RED_TRIANGLE_PROBE
    for name, request in [
        ("the globe", {"show_map": False}),
        ("Rectangular", {"projection": 0}),
        ("Mercator", {"projection": 1}),
        ("Mollweide", {"projection": 2}),
        ("Robinson", {"projection": 3}),
        ("Orthographic", {"projection": 4}),
    ]:
        # Through the selector, which is the path a person takes; it is what
        # decides between the globe and a map as well as which projection.
        client.call("view", projection="globe" if name == "the globe" else request["projection"])
        client.call("select", title=None)
        screen = client.call("latlon_to_screen", lat=lat, lon=lon)["screen"]
        if not check(screen is not None, f"Red Triangle has a place on {name}"):
            continue
        # Read the pixel with the pointer somewhere else, so the hover highlight
        # is not what the colour is being judged on.
        client.call("mouse_move", x=screen[0] + 200, y=screen[1])
        color = client.call("get_pixel", x=screen[0], y=screen[1])["color"]
        check(dominant(color) == "red", f"and is drawn there on {name}: {color}")
        back = client.call("screen_to_latlon", x=screen[0], y=screen[1])["latlon"]
        check(back is not None and abs(back[0] - lat) < 0.5 and abs(back[1] - lon) < 0.5,
              f"and the pixel says which place it shows on {name}: {back}")
        client.call("click", x=screen[0], y=screen[1])
        selected = client.call("get_selected")["feature"]
        check(selected["title"] == "Red Triangle", f"and a click there selects it on {name}")
        view = client.call("get_view")
        check(view["show_map"] == (name != "the globe"),
              f"and the selector switched the view to {name}")
        check(view["toolbar"]["projection"] == name.replace("the globe", "Globe"),
              f"and the toolbar says {name}")

    run_zoom_checks(client)
    run_wheel_checks(client)
    client.call("set_view", show_map=False, projection=0, lat=0.0, lon=0.0, angle=0.0, zoom=1.0)


def run_zoom_checks(client: AutomationClient) -> None:
    """Zoom in, out and reset, and the camera turned and put back."""
    client.call("set_view", show_map=False, lat=0.0, lon=0.0, angle=0.0, zoom=1.0)
    start = client.call("get_view")
    check(start["zoom"] == 1.0, "the view starts at the whole planet")

    client.call("view", button="zoom_in")
    zoomed = client.call("get_view")
    check(abs(zoomed["zoom"] - 1.2) < 1e-6, f"one press of zoom in is a step: {zoomed['zoom']}")
    check(zoomed["fov"] < start["fov"], "which narrows the field of view")
    check(zoomed["toolbar"]["zoom"] == 120.0, "and the toolbar reads 120%")

    client.call("view", button="zoom_out")
    check(abs(client.call("get_view")["zoom"] - 1.0) < 1e-6, "and zoom out is the step back")

    client.call("set_view", zoom=8.0)
    check(client.call("get_view")["zoom"] == 8.0, "a zoom typed in is the zoom")
    client.call("view", button="zoom_reset")
    check(client.call("get_view")["zoom"] == 1.0, "and reset goes back to the whole planet")

    client.call("view", button="rotate_clockwise")
    check(client.call("get_view")["angle"] == 15.0, "one press turns the view clockwise")
    client.call("view", button="rotate_anticlockwise")
    check(client.call("get_view")["angle"] == 0.0, "and one back leaves it where it was")

    client.call("set_view", lat=25.0, lon=-50.0, angle=40.0)
    view = client.call("get_view")
    check((view["lat"], view["lon"]) == (25.0, -50.0), "the camera position typed in is read back")
    check(view["toolbar"]["lat"] == 25.0 and view["toolbar"]["lon"] == -50.0,
          "and the toolbar fields follow it")
    client.call("view", button="camera_reset")
    view = client.call("get_view")
    check((view["lat"], view["lon"], view["angle"]) == (0.0, 0.0, 0.0),
          "and the reset puts all three back")


def run_wheel_checks(client: AutomationClient) -> None:
    """The wheel zooms both views, with the pointer over the planet."""
    for name, request in [
        ("the globe", {"show_map": False}),
        ("the map", {"show_map": True, "projection": 0}),
    ]:
        client.call("set_view", lat=0.0, lon=0.0, angle=0.0, zoom=1.0, **request)
        middle = client.call("latlon_to_screen", lat=0.0, lon=0.0)["screen"]
        client.call("click", x=middle[0], y=middle[1], button="wheel_up")
        zoomed = client.call("get_view")["zoom"]
        check(zoomed > 1.0, f"a notch of the wheel zooms {name} in: {zoomed}")
        client.call("click", x=middle[0], y=middle[1], button="wheel_down")
        check(abs(client.call("get_view")["zoom"] - 1.0) < 1e-6,
              f"and a notch back returns {name} to the whole planet")


### The export scenario


# Where the three features of the two cratons sample stand, and the width the
# pictures below are exported at. A width of 720 makes a rectangular sheet 720
# by 360, so a degree is two pixels and a probe lands well inside a feature.
EXPORT_WIDTH = 720
EXPORT_PLACES = {"blue": (30.0, 45.0), "red": (-3.0, 0.0), "green": (-3.0, -60.0)}

# The projections and the size each one exports at, which is the width and what
# the projection's own aspect makes of it: 2:1, square, 2:1, 1.97:1 and square.
EXPORT_SIZES = {0: (720, 360), 1: (720, 720), 2: (720, 360), 3: (720, 365), 4: (720, 720)}


def rectangular_pixel(size: tuple[int, int], lat: float, lon: float) -> tuple[int, int]:
    """Which pixel of a rectangular export shows a place, the sheet filling it."""
    width, height = size
    return (int((lon / 360.0 + 0.5) * width), int((0.5 - lat / 180.0) * height))


def export_to(client: AutomationClient, path: Path, **params) -> tuple[int, int]:
    """Export a picture and answer the size the port reported."""
    answer = client.call("export_image", path=str(path), **params)
    return (int(answer["size"][0]), int(answer["size"][1]))


def edge_pixels(image) -> list[tuple[int, int, int]]:
    """Every pixel of the four edge rows and columns of an image."""
    width, height = image.size
    pixels = [image.getpixel((x, y)) for y in (0, height - 1) for x in range(width)]
    return pixels + [image.getpixel((x, y)) for x in (0, width - 1) for y in range(height)]


def run_export_session(client: AutomationClient, folder: Path) -> None:
    """File > Export Image: the whole sheet, nothing else, the same size every time."""
    from PIL import Image

    sample = ROOT / "Tests" / "Data" / "two_cratons.middle-earth"
    client.call("load", path=str(sample))
    client.call("select", title=None)

    # The globe is a view of one side of the planet rather than a map of the
    # whole of it, so there is nothing there to make a picture of.
    client.call("set_view", show_map=False, lat=0.0, lon=0.0, angle=0.0, zoom=1.0)
    check("disabled" in refusal(client, "menu", item="export_image"),
          "the menu item is disabled while the globe is shown")
    check("map projection" in refusal(
        client, "export_image", path=str(folder / "globe.png"), width=EXPORT_WIDTH),
        "and the command says to pick a map projection")
    check(not (folder / "globe.png").exists(), "and nothing was written")

    # What the window itself is drawn in, which is what must not be in a
    # picture of the map: the menu bar, well away from the planet view.
    panel = client.call("get_pixel", x=4, y=4)["color"]
    panel_rgb = tuple(round(channel * 255) for channel in panel[:3])

    client.call("set_view", show_map=True, projection=0, lat=0.0, lon=0.0, angle=0.0, zoom=1.0)
    before = client.call("get_view")
    rectangular = folder / "rectangular.png"
    size = export_to(client, rectangular, width=EXPORT_WIDTH)
    check(size == EXPORT_SIZES[0], f"a rectangular export at 720 is 720 by 360: {size}")

    image = Image.open(rectangular).convert("RGB")
    check(image.size == EXPORT_SIZES[0], f"and the file is that size: {image.size}")
    for name, (lat, lon) in EXPORT_PLACES.items():
        pixel = image.getpixel(rectangular_pixel(image.size, lat, lon))
        check(dominant([channel / 255.0 for channel in pixel]) == name,
              f"the {name} feature is drawn where the projection puts it: {pixel}")

    # The sheet fills the picture, so its corners are the poles of the map
    # rather than anything behind it, and no edge of it is the window's own
    # colour: there is no panel, no label and no letterboxing in it.
    corners = [image.getpixel(point) for point in
               [(0, 0), (image.width - 1, 0), (0, image.height - 1),
                (image.width - 1, image.height - 1)]]
    check(all(abs(corner[0] - corner[2]) < 24 and min(corner) > 128 for corner in corners),
          f"the corners of a rectangular export are the polar ice it draws there: {corners}")
    check(panel_rgb not in edge_pixels(image),
          f"and no pixel of its four edges is the window's panel colour {panel_rgb}")

    run_export_shape_checks(client, folder, panel_rgb)
    run_export_width_checks(client, folder)

    after = client.call("get_view")
    for field in ["zoom", "fov", "lat", "lon", "angle", "projection", "window_size"]:
        check(after[field] == before[field],
              f"the view is where it was before the export: {field} is {after[field]}")
    client.call("set_view", show_map=False, projection=0, lat=0.0, lon=0.0, angle=0.0, zoom=1.0)


def run_export_shape_checks(client: AutomationClient, folder: Path,
                            panel_rgb: tuple[int, int, int]) -> None:
    """Each projection's own size, and a sheet that reaches every edge."""
    from PIL import Image

    background = client.call("get_view_settings")["view_settings"]["background_color"]
    background_rgb = tuple(round(channel * 255) for channel in background[:3])

    for kind, wanted in EXPORT_SIZES.items():
        path = folder / f"projection_{kind}.png"
        client.call("set_view", show_map=True, projection=kind,
                    lat=0.0, lon=0.0, angle=0.0, zoom=1.0)
        size = export_to(client, path, width=EXPORT_WIDTH)
        image = Image.open(path).convert("RGB")
        check(size == wanted and image.size == wanted,
              f"projection {kind} exports at {wanted}: reported {size}, written {image.size}")
        check(panel_rgb not in edge_pixels(image),
              f"and no edge of it is the window's panel colour: projection {kind}")

    # A Mollweide sheet is an ellipse, so its corners are what is behind it
    # while the ends of its axes touch the four edges: the picture is the sheet
    # and no larger.
    mollweide = Image.open(folder / "projection_2.png").convert("RGB")
    width, height = mollweide.size
    corners = [mollweide.getpixel(point) for point in
               [(0, 0), (width - 1, 0), (0, height - 1), (width - 1, height - 1)]]
    check(all(max(abs(a - b) for a, b in zip(corner, background_rgb)) <= 64
              for corner in corners),
          f"the corners of a Mollweide export are the background {background_rgb}: {corners}")
    for name, point in [("top", (width // 2, 0)), ("bottom", (width // 2, height - 1)),
                        ("left", (0, height // 2)), ("right", (width - 1, height // 2))]:
        pixel = mollweide.getpixel(point)
        check(max(abs(a - b) for a, b in zip(pixel, background_rgb)) > 64,
              f"and its {name} edge is the sheet itself, not a margin: {pixel}")


def run_export_width_checks(client: AutomationClient, folder: Path) -> None:
    """The width is a preference, and an export without one is that wide."""
    from PIL import Image

    client.call("set_view", show_map=True, projection=0, lat=0.0, lon=0.0, angle=0.0, zoom=1.0)
    check(client.call("get_preferences")["preferences"]["export_width"] == 3600,
          "the export width starts at 3600")
    client.call("set_preferences", preferences={"export_width": 400})
    check(client.call("get_preferences")["preferences"]["export_width"] == 400,
          "and the Preferences dialog changes it")

    path = folder / "preferred.png"
    size = export_to(client, path)
    check(size == (400, 200), f"an export that says no width is that wide: {size}")
    check(Image.open(path).size == (400, 200), "and the file is too")
    client.call("set_preferences", preferences={"export_width": 3600})


def run_scene_session(client: AutomationClient, folder: Path) -> None:
    """The scene settings: saved with the document, dragged on the globe, defaulted."""
    sample = ROOT / "Tests" / "Data" / "two_cratons.middle-earth"
    # The image goes beside the project, which is what makes the path in the
    # file a relative one.
    image = folder / "quarters.png"
    shutil.copyfile(ROOT / "Tests" / "Data" / "Backdrops" / "quarters.png", image)
    client.call("load", path=str(sample))
    client.call("set_view", show_map=False, lat=0.0, lon=0.0, angle=0.0, zoom=1.0)

    edited = {
        "background_color": [0.1, 0.0, 0.2, 1.0],
        "star_field": False,
        "graticule_color": [1.0, 0.5, 0.0, 1.0],
        "graticule_spacing": 30.0,
        "light_direction": [15.0, -25.0],
        "ambient": 0.3,
        "backdrop_path": str(image),
        "backdrop_opacity": 0.75,
        "backdrop_visible": True,
    }
    client.call("set_view_settings", view_settings=edited)
    check(client.call("get_document")["document"]["dirty"],
          "editing the scene settings offers the document for saving")
    check(client.call("get_view_settings")["backdrop_error"] == "",
          "and the backdrop image it names loads")

    saved = folder / "scene.middle-earth"
    client.call("expect_file_dialog", path=str(saved))
    client.call("menu", item="save_as")
    check(not client.call("get_document")["document"]["dirty"],
          "saving it makes the document clean again")

    written = json.loads(saved.read_text(encoding="utf-8"))
    check("view" in written, "the file carries a view block")
    client.call("load", path=str(sample))
    client.call("load", path=str(saved))
    back = client.call("get_view_settings")["view_settings"]
    for key, value in edited.items():
        if key == "backdrop_path":
            # An image beside the project is stored relative to it.
            check(back[key] == image.name, f"the backdrop path came back as {back[key]}")
        elif isinstance(value, list):
            check(all(abs(a - b) < 1e-3 for a, b in zip(back[key], value)),
                  f"{key} survived the round trip: {back[key]}")
        else:
            check(back[key] == value, f"{key} survived the round trip: {back[key]}")

    run_light_tool_checks(client)
    run_view_default_checks(client, sample)


def run_light_tool_checks(client: AutomationClient) -> None:
    """The Light tool drags the light, and the planet is brightest under it."""
    client.call("load", path=str(ROOT / "Tests" / "Data" / "empty.middle-earth"))
    client.call("set_view", show_map=False, lat=0.0, lon=0.0, angle=0.0, zoom=1.0)
    client.call("set_view_settings", view_settings={"light_direction": [0.0, 0.0], "ambient": 0.0})
    client.call("set_tool", tool="light")
    check(client.call("get_tool")["tool"] == "light", "the Light tool is armed")

    start = client.call("latlon_to_screen", lat=0.0, lon=0.0)["screen"]
    target = (20.0, -40.0)
    end = client.call("latlon_to_screen", lat=target[0], lon=target[1])["screen"]
    versions = undo_depth(client)
    client.call("press", x=start[0], y=start[1])
    client.call("mouse_move", x=end[0], y=end[1])
    client.call("release", x=end[0], y=end[1])

    stored = client.call("get_view_settings")["view_settings"]["light_direction"]
    check(abs(stored[0] - target[0]) < 0.1 and abs(stored[1] - target[1]) < 0.1,
          f"the drag put the light at {stored}")
    check(undo_depth(client) == versions + 1, "the whole light drag is one undo step")
    client.call("menu", item="undo")
    back = client.call("get_view_settings")["view_settings"]["light_direction"]
    check(back == [0.0, 0.0], f"undo puts the light back where it was: {back}")
    client.call("menu", item="redo")

    client.call("mouse_move", x=10, y=10)
    lit = luminance(client.call("get_pixel", x=end[0], y=end[1])["color"])
    away = client.call("latlon_to_screen", lat=-20.0, lon=40.0)["screen"]
    shaded = luminance(client.call("get_pixel", x=away[0], y=away[1])["color"])
    check(lit > shaded + 0.1, f"and the planet is brightest under it: {lit:.3f} to {shaded:.3f}")
    client.call("set_tool", tool="move")

    client.call("set_view", show_map=True)
    check(client.call("get_tool")["tool"] == "move",
          "the Light tool gives way when a map takes over")
    client.call("set_view", show_map=False)


def run_view_default_checks(client: AutomationClient, sample: Path) -> None:
    """What a new document starts from, and what a saved one brings with it."""
    client.call("set_view_settings", view_settings={"ambient": 0.45, "graticule_spacing": 25.0})
    client.call("view", projection=3)
    client.call("set_view_settings", button="SaveAsDefault")
    preferences = client.call("get_preferences")["preferences"]
    check(preferences["default_view"] == "Robinson", "the default view is remembered")
    check(preferences["view_defaults"]["ambient"] == 0.45, "and the settings with it")

    # Move away from the default, so what a new document picks up is the
    # preference and not what happened to be on screen.
    client.call("set_view_settings", view_settings={"ambient": 0.9, "graticule_spacing": 5.0})
    client.call("view", projection=0)
    client.call("menu", item="new")
    if client.call("get_dialog")["dialog"] is not None:
        client.call("dialog", button="Discard")
    fresh = client.call("get_view_settings")["view_settings"]
    check(fresh["ambient"] == 0.45, f"a new document takes the default ambient: {fresh['ambient']}")
    check(fresh["graticule_spacing"] == 25.0, "and the default graticule spacing")
    check(client.call("get_view")["toolbar"]["projection"] == "Robinson",
          "and opens in the default view")

    # A document that says something of its own wins over the preference.
    client.call("load", path=str(sample))
    opened = client.call("get_view_settings")["view_settings"]
    check(opened["ambient"] == 0.0 and opened["graticule_spacing"] == 15.0,
          f"an opened document brings its own settings: {opened['ambient']}")

    client.call("set_view_settings", button="RestoreDefaults")
    check(client.call("get_view_settings")["view_settings"]["ambient"] == 0.45,
          "and Restore defaults puts the preference back on it")

    # Put the preferences back, so the scenarios after this one open the
    # documents they expect rather than the ones this scenario asked for. The
    # sample was written before there was a view block, so opening it is what
    # puts the defaults back on the document to be stored.
    client.call("load", path=str(sample))
    client.call("view", projection="globe")
    client.call("set_view_settings", button="SaveAsDefault")
    restored = client.call("get_preferences")["preferences"]
    check(restored["default_view"] == "Globe" and restored["view_defaults"]["ambient"] == 0.0,
          "the preferences are back to what a fresh installation holds")
    client.call("set_view", show_map=False)


def luminance(color: list[float]) -> float:
    """How bright a probed pixel is, the way the eye weighs the channels."""
    return 0.2126 * color[0] + 0.7152 * color[1] + 0.0722 * color[2]


def run_vertex_session(client: AutomationClient) -> None:
    """Edit the vertices of a feature that the current time has moved.

    The point of doing it at a non zero time is that the stored vertex and the
    one on screen are then different. An edit that forgot to map the click back
    into the feature's own frame would still look right on the globe and put the
    wrong numbers in the file, so what is read back is the stored vertex, turned
    through the feature's rotation at that time and compared with where the
    pointer was.
    """
    start_new_document(client)
    client.call("toolbar", button="AddFeature")
    client.call("set_tool", tool="draw")
    if not draw(client, VERTEX_POLYGON):
        return
    client.call("key", key="Enter")

    # Move it at one time, so that at VERTEX_TIME it sits away from where its
    # vertices are stored.
    client.call("set_time", time=0.0)
    if not drag(client, 0.0, VERTEX_LONGITUDE):
        return
    client.call("set_time", time=VERTEX_TIME)
    rotation = client.call("get_selected")["feature"]["keyframes"]
    check(len(rotation) == 1, f"the feature has the one keyframe it was moved at: {rotation}")

    client.call("set_tool", tool="vertex", snap=False)
    tool = client.call("get_tool")
    check(tool["tool"] == "vertex", f"the Vertex tool is active: {tool['tool']}")
    check(not tool["snapping"], "with snapping off for these checks")

    before = client.call("get_selected")["feature"]
    check(before["world_rings"][0] != before["rings"][0],
          "the feature is somewhere other than where its vertices are stored")

    ### Dragging a vertex

    versions = undo_depth(client)
    grabbed = before["world_rings"][0][0]
    dropped = [grabbed[0] + 4.0, grabbed[1] + 6.0]
    if not drag_vertex(client, grabbed, dropped):
        return

    tool = client.call("get_tool")
    check(tool["selected_vertex"] == [0, 0],
          f"the press took hold of the first vertex: {tool['selected_vertex']}")

    after = client.call("get_selected")["feature"]
    check(len(after["rings"][0]) == len(before["rings"][0]),
          "the drag moved a vertex rather than adding one")
    check(worst_offset([after["world_rings"][0][0]], [tuple(dropped)]) < DRAG_TOLERANCE,
          f"the vertex is where it was dropped: {after['world_rings'][0][0]} wanted {dropped}")
    check(after["rings"][0][0] != before["rings"][0][0],
          "and the stored vertex moved with it, in the feature's own frame")
    check(undo_depth(client) == versions + 1, "the whole drag is one undo step")

    client.call("menu", item="undo")
    back = client.call("get_selected")["feature"]
    check(worst_offset(back["rings"][0], [tuple(v) for v in before["rings"][0]]) < 1e-4,
          "undo puts every stored vertex back")
    client.call("menu", item="redo")

    ### Inserting on an edge

    before = client.call("get_selected")["feature"]
    versions = undo_depth(client)
    first, second = before["world_rings"][0][0], before["world_rings"][0][1]
    middle = midpoint(first, second)
    screen = client.call("latlon_to_screen", lat=middle[0], lon=middle[1])["screen"]
    if not check(screen is not None, "the middle of the first edge is visible"):
        return
    client.call("click", x=screen[0], y=screen[1])

    after = client.call("get_selected")["feature"]
    check(len(after["rings"][0]) == len(before["rings"][0]) + 1,
          f"one vertex was added: {len(after['rings'][0])}")
    check(client.call("get_tool")["selected_vertex"] == [0, 1],
          "the new vertex is the one the tool now holds")
    check(worst_offset([after["world_rings"][0][1]], [middle]) < EDGE_TOLERANCE,
          f"it landed on the edge: {after['world_rings'][0][1]} wanted {middle}")
    check(after["rings"][0][0] == before["rings"][0][0]
          and after["rings"][0][2] == before["rings"][0][1],
          "between the two vertices the edge runs between, with both still there")
    check(undo_depth(client) == versions + 1, "inserting is one undo step")

    ### Deleting the vertex under the pointer

    # Delete takes out whatever the pointer is resting on, so the pointer is
    # moved onto the inserted vertex and nothing is clicked.
    inserted = client.call("get_selected")["feature"]["world_rings"][0][1]
    screen = client.call("latlon_to_screen", lat=inserted[0], lon=inserted[1])["screen"]
    if not check(screen is not None, "the inserted vertex is visible"):
        return
    client.call("mouse_move", x=screen[0], y=screen[1])
    check(client.call("get_tool")["hovered_vertex"] == [0, 1],
          "the pointer resting on it is enough to name it")

    versions = undo_depth(client)
    client.call("vertex", action="delete")
    after = client.call("get_selected")["feature"]
    check(len(after["rings"][0]) == len(before["rings"][0]),
          "the inserted vertex is gone again")
    check(client.call("get_tool")["selected_vertex"] is None,
          "and the tool holds nothing")
    check(undo_depth(client) == versions + 1, "deleting is one undo step")

    # A triangle has nothing to spare, so the next deletion is refused rather
    # than taking the whole shape with it.
    check(len(after["rings"][0]) == 3, "the feature is back to a triangle")
    grabbed = after["world_rings"][0][0]
    if drag_vertex(client, grabbed, grabbed):
        versions = undo_depth(client)
        refused = ""
        try:
            client.call("vertex", action="delete")
        except RuntimeError as error:
            refused = str(error)
        check(refused != "", f"deleting from a triangle is refused: {refused}")
        check(len(client.call("get_selected")["feature"]["rings"][0]) == 3,
              "and the triangle is still whole")
        check(undo_depth(client) == versions, "a refusal records no undo step")


def run_snap_session(client: AutomationClient) -> None:
    """A dragged vertex jumps onto a vertex of another feature."""
    start_new_document(client)
    client.call("toolbar", button="AddFeature")
    client.call("set_tool", tool="draw")
    if not draw(client, VERTEX_POLYGON):
        return
    client.call("key", key="Enter")
    client.call("set_property", field="name", value="Anchor")

    client.call("toolbar", button="AddFeature")
    client.call("set_tool", tool="draw")
    if not draw(client, SNAP_POLYGON):
        return
    client.call("key", key="Enter")
    client.call("set_property", field="name", value="Mover")

    anchor = None
    for feature in client.call("get_features")["features"]:
        if feature["title"] == "Anchor":
            anchor = feature
    if not check(anchor is not None, "both features are in the tree"):
        return
    client.call("select", title="Anchor")
    target = client.call("get_selected")["feature"]["world_rings"][0][0]

    client.call("select", title="Mover")
    client.call("set_tool", tool="vertex", snap=True)
    check(client.call("get_tool")["snapping"], "snapping is on")

    # Drop the vertex a few pixels short of the anchor's, near enough for the
    # snap to take it the rest of the way.
    mover = client.call("get_selected")["feature"]["world_rings"][0][0]
    near = client.call("latlon_to_screen", lat=target[0], lon=target[1])["screen"]
    grab = client.call("latlon_to_screen", lat=mover[0], lon=mover[1])["screen"]
    if not check(near is not None and grab is not None, "both vertices are visible"):
        return
    short = [near[0] + SNAP_SHORT_PIXELS, near[1]]
    client.call("press", x=grab[0], y=grab[1])
    client.call("mouse_move", x=short[0], y=short[1])
    client.call("release", x=short[0], y=short[1])

    landed = client.call("get_selected")["feature"]["world_rings"][0][0]
    check(worst_offset([landed], [tuple(target)]) < 1e-3,
          f"the vertex snapped onto the other feature's: {landed} wanted {target}")

    # The same drop with snapping off stays where it was put.
    client.call("menu", item="undo")
    client.call("set_tool", tool="vertex", snap=False)
    client.call("press", x=grab[0], y=grab[1])
    client.call("mouse_move", x=short[0], y=short[1])
    client.call("release", x=short[0], y=short[1])
    landed = client.call("get_selected")["feature"]["world_rings"][0][0]
    check(worst_offset([landed], [tuple(target)]) > 1e-3,
          f"with snapping off it stays where it was dropped: {landed}")


def run_measure_session(client: AutomationClient) -> None:
    """The Measure tool reports a distance in the status bar."""
    start_new_document(client)
    client.call("set_tool", tool="measure")
    check(client.call("get_status")["status"]["measure"] == "click two points to measure",
          "the status bar asks for two points")

    for lat, lon in MEASURE_POINTS:
        screen = client.call("latlon_to_screen", lat=lat, lon=lon)["screen"]
        if not check(screen is not None, f"the point at ({lat}, {lon}) is visible"):
            return
        client.call("click", x=screen[0], y=screen[1])

    tool = client.call("get_tool")
    check(len(tool["measure_points"]) == len(MEASURE_POINTS),
          f"both points were taken: {tool['measure_points']}")

    # 20 degrees along the equator on a sphere of Earth's mean radius.
    wanted = math.radians(MEASURE_DEGREES) * EARTH_RADIUS_KM
    shown = client.call("get_status")["status"]["measure"]
    check(f"{wanted:.1f} km" in shown, f"the status bar shows {wanted:.1f} km: {shown}")

    # The same number sits beside the line, just up and right of its midpoint.
    label = client.call("get_tool")["measure_label"]
    check(label["visible"] and label["text"] == shown,
          f"the distance is written beside the line: {label}")
    middle = client.call("latlon_to_screen", lat=0.0, lon=0.0)["screen"]
    dx, dy = label["screen"][0] - middle[0], label["screen"][1] - middle[1]
    check(0.0 < dx < 40.0 and -60.0 < dy < 0.0,
          f"and it sits up and to the right of the midpoint: {dx:.0f}, {dy:.0f}")

    # Turn the midpoint round the back of the globe and the label goes with it.
    client.call("set_view", lat=0.0, lon=180.0)
    check(not client.call("get_tool")["measure_label"]["visible"],
          "the label is hidden while the midpoint is round the back")
    client.call("set_view", lat=0.0, lon=0.0)
    check(client.call("get_tool")["measure_label"]["visible"], "and back when it is in view")

    # A third click is the start of the next measurement, not a longer path.
    third = client.call("latlon_to_screen", lat=10.0, lon=0.0)["screen"]
    client.call("click", x=third[0], y=third[1])
    tool = client.call("get_tool")
    check(len(tool["measure_points"]) == 1, f"a third click starts over: {tool['measure_points']}")
    check(not tool["measure_label"]["visible"], "with no segment to label yet")
    for lat, lon in MEASURE_POINTS:
        screen = client.call("latlon_to_screen", lat=lat, lon=lon)["screen"]
        client.call("click", x=screen[0], y=screen[1])
    client.call("set_tool", tool="move")
    check(not client.call("get_tool")["measure_label"]["visible"],
          "leaving the tool takes the label away")
    client.call("set_tool", tool="measure")
    for lat, lon in MEASURE_POINTS:
        screen = client.call("latlon_to_screen", lat=lat, lon=lon)["screen"]
        client.call("click", x=screen[0], y=screen[1])

    # Another planet. The radius is a whole number of kilometres, which is the
    # step the preference is edited in.
    other = 3000.0
    client.call("set_preferences", preferences={"planet_radius_km": other})
    check(client.call("get_preferences")["preferences"]["planet_radius_km"] == other,
          "the radius preference took the new value")
    shown = client.call("get_status")["status"]["measure"]
    check(f"{math.radians(MEASURE_DEGREES) * other:.1f} km" in shown,
          f"a smaller planet makes every distance smaller: {shown}")
    client.call("set_preferences", preferences={"planet_radius_km": EARTH_RADIUS_KM})


def run_split_session(client: AutomationClient) -> None:
    """Cutting a polygon in two, with both halves keeping what they were."""
    start_new_document(client)
    client.call("toolbar", button="AddFeature")
    client.call("set_tool", tool="draw")
    if not draw(client, SPLIT_POLYGON):
        return
    client.call("key", key="Enter")
    client.call("set_property", field="name", value="Whole")
    client.call("set_property", field="color", value=[0.0, 0.0, 1.0, 1.0])
    client.call("set_property", field="time_from", value=1500)
    client.call("set_time", time=0.0)
    if not drag(client, 0.0, 0.0):
        return

    whole = client.call("get_selected")["feature"]
    client.call("set_tool", tool="vertex", snap=False)

    # Hold one vertex, pick the one two along, and cut between them.
    if not pick_vertex(client, whole["world_rings"][0][0]):
        return
    client.call("vertex", action="split_from")
    check(client.call("get_tool")["split_from"] == [0, 0], "the first end is held")
    if not pick_vertex(client, whole["world_rings"][0][2]):
        return
    check(client.call("get_tool")["can_split"], "the Vertex tool can split there")
    client.call("vertex", action="split")

    titles = [f["title"] for f in client.call("get_features")["features"]]
    check("Whole" in titles and "Whole 2" in titles,
          f"the feature became two: {titles}")

    for title in ("Whole", "Whole 2"):
        client.call("select", title=title)
        half = client.call("get_selected")["feature"]
        check(half["geometry_kind"] == "polygon", f"{title} is still a polygon")
        check(half["color"][:3] == [0.0, 0.0, 1.0], f"{title} kept the colour: {half['color']}")
        check(half["time_range"] == whole["time_range"],
              f"{title} kept the time range: {half['time_range']}")
        check(half["keyframes"] == whole["keyframes"],
              f"{title} kept the keyframes: {half['keyframes']}")
        check(len(half["rings"][0]) >= 3, f"{title} has a ring of its own")


# A cut across the body of the sample craton, south to north a little west of
# the middle, with one point between its ends. Both ends are clicked outside the
# outline, so the commit has to put them onto it.
SPLIT_CUT = [(-24.0, -8.0), (-6.0, -10.0), (12.0, -8.0)]
# Inside the west and the east half of that cut, away from every edge.
SPLIT_PROBES = {"Old Shield": (-10.0, -16.0), "Old Shield 2": (-10.0, -2.0)}


def run_split_tool_session(client: AutomationClient) -> None:
    """The Split tool cutting the sample craton along a drawn line."""
    client.call("load", path=str(ROOT / "Tests" / "Data" / "craton.middle-earth"))
    client.call("select", title="Old Shield")
    whole = client.call("get_selected")["feature"]
    depth = undo_depth(client)

    before = client.call("latlon_to_screen", lat=0.0, lon=0.0)["screen"]
    client.call("set_tool", tool="split")
    tool = client.call("get_tool")
    check(tool["tool"] == "split", f"the Split button picks the Split tool: {tool['tool']}")
    check(client.call("latlon_to_screen", lat=0.0, lon=0.0)["screen"] == before,
          "the planet stays where it was when the tool is picked")

    # A point too many, taken back with Ctrl+Z, and a cut that crosses the edge.
    if not draw(client, SPLIT_CUT[:2] + [(2.0, -30.0)]):
        return
    client.call("key", key="Z", ctrl=True)
    held = len(client.call("get_tool")["split_points"])
    check(held == 2, f"Ctrl+Z takes the last point of the cut back: {held} held")
    if not draw(client, [(2.0, -30.0), SPLIT_CUT[2]]):
        return
    client.call("key", key="Enter")
    status = client.call("get_status")["status"]["measure"]
    check("crosses the edge" in status, f"a cut that crosses the edge is refused: {status!r}")
    check(undo_depth(client) == depth, "and records nothing")

    client.call("key", key="Escape")
    check(client.call("get_tool")["split_points"] == [], "Escape lets the points go")
    if not draw(client, SPLIT_CUT):
        return
    client.call("key", key="Enter")
    check(undo_depth(client) == depth + 1, "the split recorded one version")
    check(client.call("get_tool")["tool"] == "move", "and went back to the Move tool")

    titles = [f["title"] for f in client.call("get_features")["features"]]
    check("Old Shield" in titles and "Old Shield 2" in titles,
          f"the craton became two features: {titles}")
    total = 0
    for title, (lat, lon) in SPLIT_PROBES.items():
        client.call("select", title=title)
        half = client.call("get_selected")["feature"]
        total += len(half["rings"][0])
        check(half["color"] == whole["color"] and half["feature_type"] == whole["feature_type"],
              f"{title} kept the colour and the type")
        check(len(half["triangles"]) > 0, f"{title} is triangulated")
        client.call("set_view", show_map=False, lat=lat, lon=lon, angle=0.0, zoom=1.0)
        # Off the feature, since the one under the pointer is drawn highlighted.
        away = client.call("latlon_to_screen", lat=lat, lon=lon - 40.0)["screen"]
        client.call("mouse_move", x=away[0], y=away[1])
        screen = client.call("latlon_to_screen", lat=lat, lon=lon)["screen"]
        pixel = client.call("get_pixel", x=screen[0], y=screen[1])["color"]
        check(pixel[2] > max(pixel[0], pixel[1]) + 0.3, f"{title} is drawn blue there: {pixel}")
    wanted = len(whole["rings"][0]) + 2 * len(SPLIT_CUT)
    check(total == wanted, f"the halves hold every vertex once and the cut twice: {total}, {wanted}")

    client.call("menu", item="undo")
    titles = [f["title"] for f in client.call("get_features")["features"]]
    check("Old Shield 2" not in titles, f"undo puts the one craton back: {titles}")
    client.call("select", title="Old Shield")
    check(client.call("get_selected")["feature"]["rings"] == whole["rings"],
          "with the outline it had")


# Where the shape scenario works: the middle of `Blue Quad`, the quad spanning
# latitude 20 to 40 and longitude 30 to 60, and the colour the copy of it is
# given, which is nothing else in the sample.
QUAD_MIDDLE = (30.0, 45.0)
TRACE_COLOUR = [1.0, 0.0, 1.0, 1.0]

# A short polyline west of the quad, drawn into a Line feature so that a polygon
# shape has something of another kind to be refused by.
TRACE_LINE = [(10.0, 10.0), (0.0, 20.0)]


# The ridge scenario cuts the craton along the same line, at an age old enough
# to leave room for the halves to drift, then drags the east half away at the
# present and looks at the two of them halfway between.
RIDGE_CUT_AT = 400.0
RIDGE_BETWEEN = 200.0

# How far east the drag carries the half, in degrees, and how near the ridge has
# to sit to halfway between the halves' shared edges. A drag along the equator
# turns the half about an axis near the pole, so the great circle midpoint of two
# matching vertices is where the half stage rotation puts the ridge to within a
# tenth of a degree; the tolerance leaves room for the drag landing on a pixel.
RIDGE_DRIFT = 24.0
RIDGE_TOLERANCE = 1.0

# How far inside its shared edge each half is probed. A pixel on the boundary
# itself is as likely to land off the shape as on it.
RIDGE_INSIDE = 2.0


def is_red(pixel: list[float]) -> bool:
    """Whether a probed pixel is the crimson a Line feature is painted in."""
    return pixel[0] > max(pixel[1], pixel[2]) + 0.3


def step_toward(place: tuple[float, float], target: tuple[float, float],
                degrees: float) -> tuple[float, float]:
    """A place moved that far along the great circle towards another place."""
    gap = angular_distance(place, target)
    if gap <= degrees:
        return target
    omega, part = math.radians(gap), degrees / gap
    first, second = unit(*place), unit(*target)
    near = math.sin((1.0 - part) * omega) / math.sin(omega)
    far = math.sin(part * omega) / math.sin(omega)
    return place_of(tuple(near * first[i] + far * second[i] for i in range(3)))


def world_ring(client: AutomationClient, title: str) -> list[list[float]]:
    client.call("select", title=title)
    return client.call("get_selected")["feature"]["world_rings"][0]


def nearest_vertex(ring: list[list[float]], vertex: list[float]) -> tuple[int, float]:
    """Which vertex of a ring is nearest a point, and how far away it is."""
    return min(((i, angular_distance(tuple(v), tuple(vertex))) for i, v in enumerate(ring)),
               key=lambda pair: pair[1])


def run_ridge_session(client: AutomationClient) -> None:
    """The Split tool leaving a ridge that stays midway between the halves."""
    client.call("load", path=str(ROOT / "Tests" / "Data" / "craton.middle-earth"))
    client.call("set_view", show_map=False, lat=0.0, lon=0.0, angle=0.0, zoom=1.0)
    client.call("set_time", time=RIDGE_CUT_AT)
    client.call("select", title="Old Shield")
    depth = undo_depth(client)

    client.call("set_tool", tool="split", ridge=True)
    tool = client.call("get_tool")
    check(tool["ridge"] and tool["ridge_visible"],
          f"the Ridge switch is on and shown with the Split tool: {tool['ridge_visible']}")
    if not draw(client, SPLIT_CUT):
        return
    client.call("key", key="Enter")
    check(undo_depth(client) == depth + 1, "the split and the ridge are one version")
    check(not client.call("get_tool")["ridge_visible"],
          "and the switch goes with the tool")

    titles = [f["title"] for f in client.call("get_features")["features"]]
    check(titles[-3:] == ["Old Shield", "Old Shield 2", "Old Shield ridge"],
          f"the cut left the two halves and a ridge: {titles}")
    status = client.call("get_status")["status"]["measure"]
    check(all(title in status for title in titles[-3:]),
          f"the status bar names all three: {status!r}")

    client.call("select", title="Old Shield ridge")
    ridge = client.call("get_selected")["feature"]
    check(ridge["geometry_kind"] == "polyline" and ridge["feature_type"] == "line",
          f"the ridge is a Line: {ridge['geometry_kind']}, {ridge['feature_type']}")
    check(ridge["time_range"] == [0, int(RIDGE_CUT_AT)],
          f"there from the cut to the present: {ridge['time_range']}")
    client.call("select", title="Old Shield")
    west_uuid = client.call("get_selected")["feature"]["uuid"]
    client.call("select", title="Old Shield 2")
    east_uuid = client.call("get_selected")["feature"]["uuid"]
    check(ridge["couplings"] == [{"from": RIDGE_CUT_AT, "to": 0.0,
                                 "parent": west_uuid, "parent_b": east_uuid}],
          f"riding on both halves from the cut on: {ridge['couplings']}")
    client.call("select", title="Old Shield ridge")
    check(coupling_row(client)["coupled_to"] == "Old Shield and Old Shield 2, midway",
          f"which the panel says: {coupling_row(client)['coupled_to']!r}")

    # Where each of the ridge's vertices sits on the two halves at the cut.
    on_ridge = world_ring(client, "Old Shield ridge")
    shared = []
    for vertex in on_ridge:
        west = nearest_vertex(world_ring(client, "Old Shield"), vertex)
        east = nearest_vertex(world_ring(client, "Old Shield 2"), vertex)
        shared.append((west[0], east[0]))
        check(max(west[1], east[1]) < 0.01,
              f"the ridge vertex {vertex} is on both halves at the cut: {west[1]}, {east[1]}")

    # Hold the second half where it is at the cut, then carry it away from the
    # first at the present, whichever side of the cut it came from.
    client.call("select", title="Old Shield")
    stays = world_centroid(client)
    client.call("select", title="Old Shield 2")
    client.call("keyframes", button="Key")
    client.call("set_time", time=0.0)
    away = world_centroid(client)
    if not drag(client, away[0], away[1] + (RIDGE_DRIFT if away[1] > stays[1] else -RIDGE_DRIFT)):
        return

    client.call("set_time", time=RIDGE_BETWEEN)
    on_ridge = world_ring(client, "Old Shield ridge")
    west_ring = world_ring(client, "Old Shield")
    east_ring = world_ring(client, "Old Shield 2")
    for vertex, (west, east) in zip(on_ridge, shared, strict=True):
        halfway = midpoint(west_ring[west], east_ring[east])
        off = angular_distance(tuple(vertex), halfway)
        check(off < RIDGE_TOLERANCE,
              f"the ridge vertex is halfway between the halves: {off:.3f} degrees off")
    apart = angular_distance(tuple(west_ring[shared[1][0]]), tuple(east_ring[shared[1][1]]))
    check(apart > 5.0, f"and the two halves have come apart by then: {apart:.1f} degrees")

    # The pixels: the ridge's own colour where the middle of it is, and the
    # craton's blue just inside each half's shared edge, which is what the ridge
    # is now halfway between. Nothing is selected, so no outline is in the way.
    client.call("select", title=None)
    middle = on_ridge[1]
    pixel = probe_at(client, middle[0], middle[1])
    check(is_red(pixel), f"the ridge is drawn along the middle of the gap: {pixel}")
    for title, ring, index in (("Old Shield", west_ring, shared[1][0]),
                               ("Old Shield 2", east_ring, shared[1][1])):
        inside = step_toward(tuple(ring[index]), centroid([ring]), RIDGE_INSIDE)
        pixel = probe_at(client, inside[0], inside[1])
        check(is_blue(pixel), f"and {title} reaches its side of the gap: {pixel}")

    for _ in range(3):
        client.call("menu", item="undo")
    titles = [f["title"] for f in client.call("get_features")["features"]]
    check(titles[-1:] == ["Old Shield"], f"undo puts the one craton back: {titles}")


def world_offset(first: list[list[float]], second: list[list[float]]) -> float:
    """The largest difference between two rings of world coordinates, in degrees."""
    return max(
        max(abs(a[0] - b[0]), abs(a[1] - b[1]))
        for a, b in zip(first, second, strict=True)
    )


def run_copy_shape_session(client: AutomationClient) -> None:
    """Copy the shape of one feature into another and edit it there."""
    client.call("load", path=str(ROOT / "Tests" / "Data" / "two_cratons.middle-earth"))
    client.call("set_time", time=0.0)
    client.call("set_view", show_map=False, lat=QUAD_MIDDLE[0], lon=QUAD_MIDDLE[1],
                angle=0.0, zoom=1.0)
    client.call("select", title="Blue Quad")
    source = client.call("get_selected")["feature"]
    depth = undo_depth(client)

    client.call("menu", item="copy_shape")
    check(undo_depth(client) == depth, "Copy Shape changes the document in no way")
    status = client.call("get_status")["status"]["measure"]
    check("Copied 1 part" in status, f"and says what it took: {status!r}")

    # The root, so the copy is appended at the end of the tree and is drawn over
    # the feature it was taken from rather than under it.
    client.call("select", title=None)
    client.call("toolbar", button="AddFeature")
    client.call("set_property", field="name", value="Traced Quad")
    client.call("set_property", field="color", value=TRACE_COLOUR)
    depth = undo_depth(client)

    client.call("menu", item="paste_shape")
    check(undo_depth(client) == depth + 1, "the paste recorded exactly one version")
    check(client.call("get_tool")["tool"] == "vertex",
          "and armed the Vertex tool, so the vertices can be edited at once")
    pasted = client.call("get_selected")["feature"]
    check(pasted["title"] == "Traced Quad", f"on the feature it was pasted into: {pasted['title']}")
    check(pasted["geometry_kind"] == "polygon" and pasted["feature_type"] == "polygon",
          f"which took the kind with the shape: {pasted['geometry_kind']}")
    if check(len(pasted["rings"]) == 1, f"one part was pasted: {len(pasted['rings'])}"):
        check(len(pasted["rings"][0]) == len(source["rings"][0]),
              f"holding the {len(source['rings'][0])} vertices of the original: "
              f"{len(pasted['rings'][0])}")
        offset = world_offset(pasted["world_rings"][0], source["world_rings"][0])
        check(offset < 1e-3,
              f"at the same world points as the feature it came from: {offset:.6f} degrees")

    client.call("menu", item="paste_shape")
    check(len(client.call("get_selected")["feature"]["rings"]) == 2,
          "pasting again appends a second part")
    client.call("menu", item="undo")
    check(len(client.call("get_selected")["feature"]["rings"]) == 1, "undo takes it off again")
    client.call("menu", item="undo")
    check(client.call("get_selected")["feature"]["rings"] == [],
          "and another undo leaves the feature empty, as the paste found it")
    client.call("menu", item="redo")
    check(len(client.call("get_selected")["feature"]["rings"]) == 1, "redo puts the shape back")

    run_traced_pixel_checks(client)
    run_shape_refusal_checks(client)


def run_traced_pixel_checks(client: AutomationClient) -> None:
    """The traced shape is drawn where the feature it was copied from is."""
    client.call("set_tool", tool="move")
    client.call("select", title="Blue Quad")
    client.call("set_property", field="enabled", value=False)
    # Off the shape, since whatever is under the pointer is drawn highlighted.
    away = client.call("latlon_to_screen", lat=QUAD_MIDDLE[0], lon=QUAD_MIDDLE[1] - 40.0)["screen"]
    client.call("mouse_move", x=away[0], y=away[1])
    pixel = probe_at(client, QUAD_MIDDLE[0], QUAD_MIDDLE[1])
    check(is_colour(pixel, TRACE_COLOUR),
          f"with the original switched off, the copy paints the quad: {pixel}")


def run_shape_refusal_checks(client: AutomationClient) -> None:
    """A feature already holding another kind refuses the shape."""
    if not add_polyline(client, "A Line", TRACE_LINE):
        return
    depth = undo_depth(client)
    client.call("menu", item="paste_shape")
    status = client.call("get_status")["status"]["measure"]
    check(status == "A polyline cannot take a polygon.",
          f"a Line feature refuses a polygon shape, with the reason: {status!r}")
    check(undo_depth(client) == depth, "and nothing was recorded")


### The Rotate and Pole tools


# The degree sign the status bar writes the angle with, kept out of the source
# as an escape so the file stays plain ASCII.
DEGREE = "°"

# Where the pole scenario puts its pole, well clear of the craton to the west,
# and how far the craton is turned about it.
POLE_AT = (0.0, -40.0)
POLE_TURN = 35.0

# How far the Rotate tool turns the craton about its own middle, and the point
# out towards the rim that a turn that far carries the craton off. Both are in
# the craton's own table in Tests/Data/README.md.
SPIN_TURN = 90.0
CRATON_RIM = (-15.64, -19.48)


def place_of(point: tuple[float, float, float]) -> tuple[float, float]:
    """The place a point on the unit sphere is at, the inverse of unit()."""
    return (math.degrees(math.asin(max(-1.0, min(1.0, point[1])))),
            math.degrees(math.atan2(point[2], point[0])))


def turn_about(place: tuple[float, float], axis: tuple[float, float],
               degrees: float) -> tuple[float, float]:
    """Where a place ends up when it is turned about an axis, both as latitude/longitude."""
    point, pole, angle = unit(*place), unit(*axis), math.radians(degrees)
    along = sum(a * b for a, b in zip(pole, point, strict=True))
    turned = (pole[1] * point[2] - pole[2] * point[1],
              pole[2] * point[0] - pole[0] * point[2],
              pole[0] * point[1] - pole[1] * point[0])
    return place_of(tuple(
        point[i] * math.cos(angle) + turned[i] * math.sin(angle)
        + pole[i] * along * (1.0 - math.cos(angle)) for i in range(3)))


def is_blue(pixel: list[float]) -> bool:
    """Whether a probed pixel is the blue the sample craton is painted in."""
    return pixel[2] > max(pixel[0], pixel[1]) + 0.3


def turn(client: AutomationClient, grab: tuple[float, float],
         release: tuple[float, float]) -> bool:
    """Drag from one place on the planet to another, which is what turns a feature."""
    start = client.call("latlon_to_screen", lat=grab[0], lon=grab[1])["screen"]
    end = client.call("latlon_to_screen", lat=release[0], lon=release[1])["screen"]
    if not check(start is not None and end is not None,
                 f"the drag from {grab} to {release} is on the visible hemisphere"):
        return False
    client.call("press", x=start[0], y=start[1])
    client.call("mouse_move", x=end[0], y=end[1])
    client.call("release", x=end[0], y=end[1])
    return True


def status_angle(client: AutomationClient) -> float:
    """The angle the status bar says the last drag turned the feature by."""
    status = client.call("get_status")["status"]["measure"]
    if not status.startswith("Rotating "):
        check(False, f"the status bar reports the angle: {status!r}")
        return math.nan
    return float(status.removeprefix("Rotating ").rstrip(DEGREE))


def look_at(client: AutomationClient, place: tuple[float, float]) -> None:
    """Turn the globe so a place faces the camera, which is where a drag is accurate."""
    client.call("set_view", show_map=False, lat=place[0], lon=place[1], angle=0.0, zoom=1.0)


def run_rotate_session(client: AutomationClient) -> None:
    """Turning the sample craton in place and about a pole."""
    client.call("load", path=str(ROOT / "Tests" / "Data" / "craton.middle-earth"))
    client.call("set_time", time=0.0)
    client.call("select", title="Old Shield")
    middle = world_centroid(client)

    client.call("key", key="R")
    check(client.call("get_tool")["tool"] == "rotate", "R picks the Rotate tool")
    check(is_blue(probe_at(client, middle[0], middle[1])), "the middle of the craton is blue")
    check(is_blue(probe_at(client, CRATON_RIM[0], CRATON_RIM[1])),
          "and so is the point out towards the rim")

    look_at(client, middle)
    depth = undo_depth(client)
    if turn(client, CRATON_RIM, turn_about(CRATON_RIM, middle, SPIN_TURN)):
        check(abs(status_angle(client) - SPIN_TURN) < 2.0,
              "the drag turns the craton a quarter of the way about its own middle")
        check(undo_depth(client) == depth + 1, "and records exactly one version")
        after = client.call("get_selected")["feature"]
        check(len(after["keyframes"]) == 1,
              f"written as one keyframe: {len(after['keyframes'])}")
        check(angular_distance(centroid(after["world_rings"]), middle) < 0.5,
              "a turn in place leaves the middle of the craton where it was")
        check(is_blue(probe_at(client, middle[0], middle[1])),
              "which the pixel there still shows")
        check(not is_blue(probe_at(client, CRATON_RIM[0], CRATON_RIM[1])),
              "while the point out towards the rim is off the craton now")

    client.call("menu", item="undo")
    check(client.call("get_selected")["feature"]["keyframes"] == [],
          "undo takes the keyframe away again")
    check(is_blue(probe_at(client, CRATON_RIM[0], CRATON_RIM[1])),
          "and the craton is back over the rim point")

    run_pole_checks(client, middle)
    run_tool_key_checks(client)


def run_pole_checks(client: AutomationClient, middle: tuple[float, float]) -> None:
    """A pole placed with a click, and a drag that turns the craton about it."""
    look_at(client, middle)
    client.call("key", key="P")
    check(client.call("get_tool")["tool"] == "pole", "P picks the Pole tool")
    check(client.call("get_tool")["pole"] is None, "which starts with no pole placed")

    screen = client.call("latlon_to_screen", lat=POLE_AT[0], lon=POLE_AT[1])["screen"]
    if not check(screen is not None, f"the pole at {POLE_AT} is on the visible hemisphere"):
        return
    client.call("click", x=screen[0], y=screen[1])
    placed = client.call("get_tool")["pole"]
    if not check(placed is not None and angular_distance(tuple(placed), POLE_AT) < 1.0,
                 f"a click places the pole: {placed}"):
        return

    depth = undo_depth(client)
    wanted = turn_about(middle, POLE_AT, POLE_TURN)
    if not turn(client, middle, wanted):
        return
    check(abs(status_angle(client) - POLE_TURN) < 2.0,
          "the status bar shows how far the drag turned the craton")
    check(undo_depth(client) == depth + 1, "and the drag records one version")
    landed = world_centroid(client)
    check(angular_distance(landed, wanted) < 1.0,
          f"the craton turned about the pole rather than about itself: {landed} for {wanted}")
    check(client.call("get_tool")["pole"] is not None, "and the pole stays for the next turn")
    check(is_blue(probe_at(client, landed[0], landed[1])),
          "the craton is drawn where the turn about the pole put it")

    client.call("key", key="Escape")
    check(client.call("get_tool")["pole"] is None, "Escape clears the pole")
    client.call("menu", item="undo")


def run_tool_key_checks(client: AutomationClient) -> None:
    """The tool keys, and the text field that swallows them."""
    client.call("set_tool", tool="move")
    for key, tool in [("V", "vertex"), ("E", "measure"), ("L", "light"), ("X", "split"),
                      ("R", "rotate"), ("P", "pole"), ("M", "move")]:
        client.call("key", key=key)
        picked = client.call("get_tool")["tool"]
        check(picked == tool, f"{key} picks the {tool} tool: {picked}")

    # A key of a tool the toolbar greys out for what is selected does nothing.
    client.call("key", key="T")
    check(client.call("get_tool")["tool"] == "move",
          "a key of a tool that is not offered leaves the tool alone")

    # A name being typed is a name being typed, whatever the letters are.
    focus = client.call("focus", widget="Name")
    if check(focus["focus"] == "Name", f"the name field can be typed in: {focus['focus']}"):
        before = client.call("get_properties")["properties"]["name"]
        for key in ["R", "P", "V"]:
            client.call("key", key=key)
        after = client.call("get_properties")["properties"]["name"]
        # The caret is at the front of the field the focus was handed to.
        check(after == "rpv" + before, f"the keys are typed into the name: {after!r}")
        check(client.call("get_tool")["tool"] == "move", "and no tool was picked by them")
        client.call("set_property", field="name", value=before)
    client.call("focus", release=True)


### Helpers for the vertex scenarios


def undo_depth(client: AutomationClient) -> int:
    """How many versions the document has recorded, so an edit can be counted."""
    return client.call("get_document")["document"]["undo_depth"]


def midpoint(a: list[float], b: list[float]) -> tuple[float, float]:
    """Halfway along the great circle arc between two latitude/longitude points."""
    first, second = unit(a[0], a[1]), unit(b[0], b[1])
    total = [first[i] + second[i] for i in range(3)]
    length = math.sqrt(sum(c * c for c in total))
    x, y, z = (c / length for c in total)
    return math.degrees(math.asin(y)), math.degrees(math.atan2(z, x))


def pick_vertex(client: AutomationClient, world: list[float]) -> bool:
    """Press and release on a vertex, so the tool takes hold of it."""
    screen = client.call("latlon_to_screen", lat=world[0], lon=world[1])["screen"]
    if not check(screen is not None, f"the vertex at {world} is visible"):
        return False
    client.call("press", x=screen[0], y=screen[1])
    client.call("release", x=screen[0], y=screen[1])
    return True


def drag_vertex(client: AutomationClient, world: list[float], to: list[float]) -> bool:
    """Drag one vertex from where it is on screen to another latitude/longitude."""
    grab = client.call("latlon_to_screen", lat=world[0], lon=world[1])["screen"]
    target = client.call("latlon_to_screen", lat=to[0], lon=to[1])["screen"]
    if not check(grab is not None and target is not None,
                 f"the vertex drag from {world} to {to} is visible"):
        return False
    client.call("press", x=grab[0], y=grab[1])
    client.call("mouse_move", x=target[0], y=target[1])
    client.call("release", x=target[0], y=target[1])
    return True


def count_features(node: dict) -> int:
    """The number of nodes in a serialized feature tree."""
    return 1 + sum(count_features(child) for child in node.get("children", []))


### The styling scenario


# How far a probed pixel may be from the colour asked for, per channel. The
# probe faces the camera and so does the light, so the lit colour is the picked
# one and a paler pixel is a defect rather than lighting (GP-0032). Matches
# COLOR_TOLERANCE in Tests/Rendered/test_styling.gd.
COLOR_TOLERANCE = 0.03


def is_colour(probed: list[float], expected: list[float]) -> bool:
    """Whether a probed pixel is the colour it was meant to be drawn in."""
    return all(abs(a - b) < COLOR_TOLERANCE for a, b in zip(probed[:3], expected[:3]))


def probe_at(client: AutomationClient, lat: float, lon: float) -> list[float]:
    """The pixel where a place is, with that place brought round to face the camera."""
    client.call("set_view", show_map=False, lat=lat, lon=lon, angle=0.0, zoom=1.0)
    screen = client.call("latlon_to_screen", lat=lat, lon=lon)["screen"]
    assert screen is not None, f"({lat}, {lon}) is not on screen"
    return client.call("get_pixel", x=screen[0], y=screen[1])["color"]


# The three features of mixed_geometry.middle-earth, one of each class the
# visibility switches cover, at the probe points Tests/Data/README.md lists.
STYLE_PROBES = {"polygons": (-3.0, 0.0), "polylines": (0.0, 40.0), "points": (-30.0, -30.0)}

# The colour each feature of the sample takes under the feature type style: the
# type its geometry gives, as FeatureType.CATALOG colours it in
# Logic/feature_type.gd. Chocolate, crimson and gold.
TYPE_COLOURS = {"polygons": [0.824, 0.412, 0.118], "polylines": [0.863, 0.078, 0.235],
                "points": [1.0, 0.843, 0.0]}


def run_styling_session(client: AutomationClient, folder: Path) -> None:
    """The draw styles, the palette read from a file, and the class switches."""
    # GP-0053: a new document starts on the custom ramp, black to white.
    start_new_document(client)
    style = client.call("get_view_settings")["style"]
    check(style["palette"] == "ramp"
          and style["ramp_colors"] == [[0.0, 0.0, 0.0, 1.0], [1.0, 1.0, 1.0, 1.0]]
          and style["ramp_span"] == 300.0,
          f"a new document's root ramps black to white over 300 My: {style}")

    sample = ROOT / "Tests" / "Data" / "mixed_geometry.middle-earth"
    client.call("load", path=str(sample))
    client.call("mouse_move", x=10, y=10)

    single = [0.1, 0.6, 0.9, 1.0]
    client.call("set_view_settings",
                view_settings={"draw_style": "single", "single_color": single})
    for name, (lat, lon) in STYLE_PROBES.items():
        check(is_colour(probe_at(client, lat, lon), single),
              f"the single colour style paints the {name[:-1]}")

    client.call("set_view_settings", view_settings={"draw_style": "type"})
    for name, (lat, lon) in STYLE_PROBES.items():
        check(is_colour(probe_at(client, lat, lon), TYPE_COLOURS[name]),
              f"the feature type style paints the {name[:-1]} in its type's colour")

    run_palette_checks(client)
    run_class_switch_checks(client)
    run_styling_round_trip(client, folder)


def run_palette_checks(client: AutomationClient) -> None:
    """The feature age style over a built in palette and one read from a file."""
    # How old a feature is is measured from the current time, and a document
    # opens at the oldest age of the animation, so read the ages at the present.
    client.call("set_time", time=0.0)
    # Give each feature its own age, which is the older end of its time range,
    # the one the panel calls From.
    ages = {"Red Triangle": 100, "Blue Ridge": 300, "Green Stations": 900}
    for title, age in ages.items():
        client.call("select", title=title)
        client.call("set_property", field="time_from", value=age)
    client.call("select", title=None)

    # Rainbow runs through six colours two hundred million years apart, so each
    # of the three ages lands halfway along a different pair of them.
    client.call("set_view_settings", view_settings={"draw_style": "age", "palette": "rainbow"})
    expected = {"polygons": [1.0, 0.5, 0.0], "polylines": [0.5, 1.0, 0.0],
                "points": [0.5, 0.0, 1.0]}
    for name, (lat, lon) in STYLE_PROBES.items():
        check(is_colour(probe_at(client, lat, lon), expected[name]),
              f"the {name[:-1]} takes the palette colour for its age")

    # GP-0053: the root's custom ramp through the dialog, red to blue over
    # 200 My. The polyline at 300 and the markers at 900 are past it, so blue.
    ramp = {"palette": "ramp", "ramp_span": 200.0,
            "ramp_colors": [[1.0, 0.0, 0.0, 1.0], [0.0, 0.0, 1.0, 1.0]]}
    client.call("set_view_settings", view_settings=ramp)
    style = client.call("get_view_settings")["style"]
    check(all(style[key] == value for key, value in ramp.items()),
          f"the root group carries the ramp the dialog was given: {style}")
    for name in ("polylines", "points"):
        lat, lon = STYLE_PROBES[name]
        check(is_colour(probe_at(client, lat, lon), [0.0, 0.0, 1.0]),
              f"the {name[:-1]}, older than the span, is the ramp's last colour")

    # A third colour added to the ramp: green 200 My after blue. The markers at
    # 900 are past the whole ramp, so they take the new last colour, while the
    # polyline at 300 is halfway from blue to it.
    client.call("set_view_settings", view_settings={"ramp_colors": ramp["ramp_colors"]
                                                    + [[0.0, 1.0, 0.0, 1.0]]})
    lat, lon = STYLE_PROBES["points"]
    check(is_colour(probe_at(client, lat, lon), [0.0, 1.0, 0.0]),
          "a colour added to the ramp reaches the feature past the end of it")
    lat, lon = STYLE_PROBES["polylines"]
    check(is_colour(probe_at(client, lat, lon), [0.0, 0.5, 0.5]),
          "and the one at 300 Ma is halfway along the second span")

    # The same again from a file rather than from the built in list. The
    # fixture ramps black to red between 0 and 100, then red to white to 200.
    palette = ROOT / "Tests" / "Data" / "Palettes" / "continuous.cpt"
    client.call("set_view_settings", view_settings={"palette": str(palette)})
    answer = client.call("get_view_settings")
    check(answer["style"]["palette"] == str(palette),
          "the root group names the palette file it was given")
    check(answer["palette_errors"] == [], "which reads without error")
    lat, lon = STYLE_PROBES["polygons"]
    check(is_colour(probe_at(client, lat, lon), [1.0, 0.0, 0.0]),
          "and 100 Ma is the boundary its two ramps share, which is red")
    lat, lon = STYLE_PROBES["polylines"]
    check(is_colour(probe_at(client, lat, lon), [0.0, 1.0, 0.0]),
          "while 300 Ma is past its top, which is the foreground colour")

    # A file the reader cannot make sense of says which lines it could not read
    # rather than leaving the planet unexplained.
    broken = ROOT / "Tests" / "Data" / "Palettes" / "malformed.cpt"
    client.call("set_view_settings", view_settings={"palette": str(broken)})
    errors = client.call("get_view_settings")["palette_errors"]
    check(len(errors) == 2 and all(error.startswith("line ") for error in errors),
          f"a malformed palette reports its lines: {errors}")


def run_class_switch_checks(client: AutomationClient) -> None:
    """Each View menu switch takes its own class off the globe and no other."""
    client.call("set_view_settings",
                view_settings={"draw_style": "feature", "hidden_classes": []})
    for hidden in STYLE_PROBES:
        client.call("menu", item=hidden)
        stored = client.call("get_view_settings")["view_settings"]["hidden_classes"]
        check(stored == [hidden], f"the {hidden} switch is off: {stored}")
        for name, (lat, lon) in STYLE_PROBES.items():
            drawn = dominant(probe_at(client, lat, lon)) != ""
            check(drawn != (name == hidden),
                  f"{name} {'is gone' if name == hidden else 'is still drawn'} at ({lat}, {lon})")
        client.call("menu", item=hidden)
    check(client.call("get_view_settings")["view_settings"]["hidden_classes"] == [],
          "and every class is back on at the end")


def run_styling_round_trip(client: AutomationClient, folder: Path) -> None:
    """The active style, its colour, its palette and the switches survive the file."""
    palette = ROOT / "Tests" / "Data" / "Palettes" / "discrete.cpt"
    edited = {
        "draw_style": "age",
        "single_color": [0.3, 0.7, 0.2, 1.0],
        "palette": str(palette),
        "hidden_classes": ["points", "topologies"],
    }
    client.call("set_view_settings", view_settings=edited)
    check(client.call("get_document")["document"]["dirty"],
          "picking a style offers the document for saving")

    saved = folder / "styled.middle-earth"
    client.call("expect_file_dialog", path=str(saved))
    client.call("menu", item="save_as")
    written = json.loads(saved.read_text(encoding="utf-8"))
    check(written["features"]["style"]["mode"] == "age" and "draw_style" not in written["view"],
          "the file carries the active style on the root group")

    client.call("menu", item="new")
    if client.call("get_dialog")["dialog"] is not None:
        client.call("dialog", button="Discard")
    client.call("load", path=str(saved))
    answer = client.call("get_view_settings")
    style = answer["style"]
    back = {**answer["view_settings"], "draw_style": style["mode"],
            "single_color": style["color"], "palette": style["palette"]}
    for key, value in edited.items():
        if key == "single_color":
            check(all(abs(a - b) < 1e-3 for a, b in zip(back[key], value)),
                  f"{key} survived the round trip: {back[key]}")
        else:
            check(back[key] == value, f"{key} survived the round trip: {back[key]}")

    # Put the switches back on, so the scenarios after this one see everything.
    client.call("set_view_settings",
                view_settings={"hidden_classes": [], "draw_style": "feature"})


### The kinematics scenario


MOTION = ROOT / "Tests" / "Data" / "motion.middle-earth"

# The span the graphs are drawn over during the scenario, and the time the
# cursor is moved to inside it. The scenario states the animation range itself:
# the graphs span it, and an earlier scenario leaves it somewhere else.
KINEMATICS_OLDEST = 2000.0
KINEMATICS_YOUNGEST = 0.0
CURSOR_TIME = 500.0

# How far the cursor may sit from where the time says it should, in pixels. It
# is drawn on a whole pixel of a plotting area a few hundred wide.
CURSOR_TOLERANCE = 1.0


def run_kinematics_session(client: AutomationClient) -> None:
    """The kinematics panel: what it graphs, and how its cursor follows the time."""
    client.call("load", path=str(MOTION))
    client.call("set_animation",
                animation={"start": KINEMATICS_OLDEST, "end": KINEMATICS_YOUNGEST})
    # A document opens at the oldest age of the animation; the graphs below are
    # read at the present, which is where the cursor belongs at the right.
    client.call("set_time", time=KINEMATICS_YOUNGEST)

    check(not client.call("get_panels")["panels"]["kinematics"],
          "the graphs are not shown until they are asked for")
    client.call("menu", item="kinematics")
    check(client.call("get_panels")["panels"]["kinematics"],
          "the View menu shows them")

    client.call("select", title="Drifting Craton")
    graphs = client.call("get_kinematics")["kinematics"]
    check(graphs["title"] == "Drifting Craton", f"the panel graphs the selection: {graphs['title']}")
    check(graphs["span"] == [KINEMATICS_OLDEST, KINEMATICS_YOUNGEST],
          f"over the span the timeline covers: {graphs['span']}")
    check(len(graphs["samples"]) > 2, f"the path is filled in: {len(graphs['samples'])} samples")
    check(len(graphs["segments"]) == 2,
          f"one span per pair of keyframes: {len(graphs['segments'])}")
    check(graphs["samples"][0]["time"] == KINEMATICS_OLDEST
          and graphs["samples"][-1]["time"] == KINEMATICS_YOUNGEST,
          "sampled from the oldest end to the youngest, which is left to right")

    # What the panel says the middle is doing has to agree with where the globe
    # has actually drawn the feature.
    lat, lon = world_centroid(client)
    check(abs(graphs["current"]["lat"] - lat) < 1e-3
          and abs(graphs["current"]["lon"] - lon) < 1e-3,
          f"the panel and the globe agree on the middle: {graphs['current']}, ({lat}, {lon})")

    # The rate at the present is the one of the younger of the two spans.
    younger = min(graphs["segments"], key=lambda segment: segment["to"])
    check(abs(graphs["current"]["degrees_per_my"] - younger["degrees_per_my"]) < 1e-9,
          f"and on the rate at the current time: {graphs['current']['degrees_per_my']}")

    # The cursor sits where the time is, measured across the plotting area: the
    # oldest end on the left, the youngest on the right.
    check(abs(graphs["cursor"] - graphs["plot_width"]) < CURSOR_TOLERANCE,
          f"at the present the cursor is at the right hand end: {graphs['cursor']}")
    client.call("set_time", time=CURSOR_TIME)
    graphs = client.call("get_kinematics")["kinematics"]
    fraction = (KINEMATICS_OLDEST - CURSOR_TIME) / (KINEMATICS_OLDEST - KINEMATICS_YOUNGEST)
    check(abs(graphs["cursor"] - fraction * graphs["plot_width"]) < CURSOR_TOLERANCE,
          f"and moving the time moves it to that time: {graphs['cursor']}")
    check(f"{CURSOR_TIME:g} Ma" in graphs["readout"],
          f"the readout says where the cursor is: {graphs['readout']}")

    # Where the feature is at that time, off the graph, is where the globe has
    # carried it as well.
    lat, lon = world_centroid(client)
    check(abs(graphs["current"]["lat"] - lat) < 1e-3
          and abs(graphs["current"]["lon"] - lon) < 1e-3,
          f"the graph followed the time along with the globe: {graphs['current']}")

    client.call("select", title="Plates")
    empty = client.call("get_kinematics")["kinematics"]
    check(empty["samples"] == [] and empty["segments"] == [] and empty["current"] == {},
          f"a group empties the panel: {len(empty['samples'])} samples")
    check("group" in empty["readout"], f"which says why: {empty['readout']}")

    client.call("menu", item="kinematics")
    check(not client.call("get_panels")["panels"]["kinematics"],
          "and the same menu item hides the panel again")


### Python scripting


# How long the interpreter is given to come up before the run gives up on it.
PYTHON_ATTEMPTS = 120
PYTHON_DELAY = 0.5

SCRIPT_SOURCE = '''"""Add the craton this run is looking for

Adds one polygon, so a run can tell the script's work from its own.
"""

uuid = app.add_feature("From the menu", rings=[[(0.0, 0.0), (0.0, 8.0), (8.0, 0.0)]])
print("added", uuid)
'''


def await_python(client: AutomationClient) -> dict:
    """Wait until the interpreter is up or has given up, then say which."""
    state = {}
    for _ in range(PYTHON_ATTEMPTS):
        state = client.call("get_python")["python"]
        if state["state"] in ("READY", "FAILED", "OFF"):
            return state
        time.sleep(PYTHON_DELAY)
    return state


def console(client: AutomationClient, line: str) -> str:
    """Type one line at the prompt and answer with what the transcript gained."""
    before = client.call("get_console")["console"]["transcript"]
    after = client.call("console", line=line)["transcript"]
    return after[len(before):]


def run_python_session(client: AutomationClient) -> None:
    """A console session that builds a moving feature, checked through the port."""
    state = await_python(client)
    if not check(state["state"] == "READY", f"the interpreter is running: {state}"):
        return
    check(state["port"] > 0, f"it was given a port of its own, {state['port']}")
    check(client.call("get_console")["console"]["editable"],
          "the prompt takes typing once the interpreter is up")

    start_new_document(client)
    client.call("console_clear")

    # Add a feature and move it, entirely from the console.
    printed = console(client, 'uuid = app.add_feature("Scripted", '
                              'rings=[[(0.0, 0.0), (0.0, 10.0), (10.0, 0.0)]])')
    check("Traceback" not in printed, f"adding a feature raised nothing: {printed!r}")
    printed = console(client, "app.set_keyframe(uuid, 0.0, (0, 0, 0))")
    check("Traceback" not in printed, f"the first keyframe was written: {printed!r}")
    printed = console(client, "app.set_keyframe(uuid, 600.0, (-30, 10, 0))")
    check("Traceback" not in printed, f"the second keyframe was written: {printed!r}")

    # What the port says the document holds now, which is the application's own
    # answer rather than the script's.
    features = client.call("get_features")["features"]
    scripted = [entry for entry in features if entry["title"] == "Scripted"]
    if check(len(scripted) == 1, f"the port sees the feature the console added: {features}"):
        client.call("select", title="Scripted")
        panel = client.call("get_properties")["properties"]
        check(panel["geometry"].startswith("polygon"),
              f"drawn as the kind the console asked for: {panel['geometry']!r}")
        check(panel["keyframes"]["count"] == 2,
              f"the panel counts both keyframes: {panel['keyframes']}")
        keyframes = client.call("get_selected")["feature"]["keyframes"]
        check([key["time"] for key in keyframes] == [0.0, 600.0],
              f"at the times they were set: {keyframes}")
        check(keyframes[1]["rotation"] == [-30.0, 10.0, 0.0],
              f"with the rotation the console asked for: {keyframes[1]}")

    # Playing from the console is the timeline playing. It starts from the
    # oldest end of the animation, since starting at the youngest is standing
    # on the last frame and playback would stop at once.
    beginning = client.call("get_timeline")["timeline"]["animation"]["start"]
    console(client, "app.time = %r" % beginning)
    console(client, "app.play()")
    check(client.call("get_timeline")["timeline"]["playing"], "app.play() started the animation")
    console(client, "app.pause()")
    check(not client.call("get_timeline")["timeline"]["playing"], "and app.pause() stopped it")

    # An expression prints its value, the way an interpreter does.
    printed = console(client, "6 * 7")
    check("42" in printed, f"an expression prints its value: {printed!r}")

    # A statement over two lines: the interpreter says the first is unfinished.
    console(client, "for i in range(2):")
    check(client.call("get_console")["console"]["prompt"] == "... ",
          "an unfinished statement asks for the rest")
    console(client, "    print('line', i)")
    printed = console(client, "")
    check("line 0" in printed and "line 1" in printed,
          f"and the block runs when it is closed: {printed!r}")
    check(client.call("get_console")["console"]["prompt"] == ">>> ",
          "the first prompt comes back")

    # An error is shown and the session carries on.
    printed = console(client, "1 / 0")
    check("ZeroDivisionError" in printed, f"an error is shown: {printed!r}")
    printed = console(client, "'still here'")
    check("still here" in printed, f"and the session survived it: {printed!r}")

    run_history_checks(client)
    run_completion_checks(client)
    run_export_from_console(client)


def run_export_from_console(client: AutomationClient) -> None:
    """app.export_image writes a picture of the map and answers its size."""
    folder = Path(tempfile.mkdtemp(prefix="middle-earth-console-export-"))
    try:
        path = folder / "console.png"
        client.call("set_view", show_map=True, projection=0,
                    lat=0.0, lon=0.0, angle=0.0, zoom=1.0)
        printed = console(client, f"app.export_image({str(path)!r}, width=240)")
        check("(240, 120)" in printed, f"app.export_image answers with the size: {printed!r}")
        check(path.is_file() and path.stat().st_size > 0,
              f"and the picture is on disk: {path}")

        # The globe is refused there too, as an exception a script can catch.
        client.call("set_view", show_map=False)
        printed = console(client, f"app.export_image({str(folder / 'globe.png')!r})")
        check("AppError" in printed, f"and the globe is refused: {printed!r}")
    finally:
        shutil.rmtree(folder, ignore_errors=True)


def run_history_checks(client: AutomationClient) -> None:
    """The arrow keys walk back through the lines already typed."""
    history = client.call("get_console")["console"]["history"]
    if not check(len(history) > 1, "the console remembers the lines typed"):
        return
    check(history[-1] == "'still here'", f"the newest is the line just typed: {history[-1]!r}")

    check(client.call("console_recall", step=-1)["input"] == history[-1],
          "Up recalls the previous line")
    check(client.call("console_recall", step=-1)["input"] == history[-2],
          "and again the one before it")
    check(client.call("console_recall", step=1)["input"] == history[-1],
          "Down comes back towards the newest")
    check(client.call("console_recall", step=1)["input"] == "",
          "and past the newest the prompt is empty again")


def run_completion_checks(client: AutomationClient) -> None:
    """Completion is served by the interpreter, so it knows the live namespace."""
    answered = client.call("console_complete", source="app.set_key")
    check("app.set_keyframe(" in answered["completions"],
          f"a known method is offered: {answered['completions']}")
    check(answered["input"] == "app.set_keyframe(",
          f"and the one answer finishes the word: {answered['input']!r}")

    answered = client.call("console_complete", source="app.add_")
    check(sorted(answered["completions"]) == ["app.add_feature(", "app.add_group("],
          f"two answers are both offered: {answered['completions']}")
    check(answered["input"] == "app.add_", f"and the shared start stays: {answered['input']!r}")

    # A name this session made a moment ago is completed too, which is what
    # having the interpreter serve the completions buys.
    console(client, "rodinia_marker = 1")
    answered = client.call("console_complete", source="rodinia_mar")
    check(answered["completions"] == ["rodinia_marker"],
          f"a name from this session is offered: {answered['completions']}")

    client.call("console_complete", source="")


def run_script_menu_session(client: AutomationClient, folder: Path) -> None:
    """A script dropped in a configured directory becomes a menu entry."""
    script = folder / "add_from_menu.py"
    script.write_text(SCRIPT_SOURCE, encoding="utf-8")
    (folder / "undocumented.py").write_text("print('no docstring')\n", encoding="utf-8")

    directories = client.call("get_preferences")["preferences"]["script_directories"]
    client.call("set_preferences", preferences={"script_directories": directories + [str(folder)]})
    client.call("rescan_scripts")

    scripts = {entry["name"]: entry for entry in client.call("get_scripts")["scripts"]}
    if not check("add_from_menu" in scripts, f"the new script is a menu entry: {sorted(scripts)}"):
        return
    check(scripts["add_from_menu"]["title"] == "Add the craton this run is looking for",
          f"named after the first line of its docstring: {scripts['add_from_menu']['title']!r}")
    check("undocumented" not in scripts, "a script without a docstring is not a command")

    start_new_document(client)
    client.call("console_clear")
    before = len(client.call("get_features")["features"])
    transcript = client.call("run_script", name="add_from_menu")["transcript"]
    check("Traceback" not in transcript, f"the script ran without an error: {transcript[-200:]!r}")
    check(client.call("get_panels")["panels"]["console"],
          "running a script brings the console up to show what it printed")

    features = client.call("get_features")["features"]
    check(len(features) == before + 1, f"the script added a feature: {len(features)} now")
    check(any(entry["title"] == "From the menu" for entry in features),
          f"the one it says it adds: {[entry['title'] for entry in features]}")
    check("added" in transcript, f"and what it printed is in the console: {transcript[-200:]!r}")

    # Running it by path is what File > Run Script does.
    client.call("console_clear")
    transcript = client.call("run_script", path=str(script))["transcript"]
    check("Traceback" not in transcript, "the same script runs from a path")
    check(len(client.call("get_features")["features"]) == before + 2,
          "and adds a second feature")

    client.call("set_preferences", preferences={"script_directories": directories})
    client.call("rescan_scripts")
    check("add_from_menu" not in {entry["name"] for entry in client.call("get_scripts")["scripts"]},
          "taking the directory away takes the entry with it")


def run_bad_interpreter_checks(client: AutomationClient) -> None:
    """A path that is not an interpreter is said so, and the application stays up."""
    good = client.call("get_preferences")["preferences"]["python_interpreter"]
    client.call("set_preferences", preferences={"python_interpreter": "C:/no/such/python.exe"})

    state = await_python(client)
    check(state["state"] == "FAILED", f"the interpreter is reported as failed: {state}")
    check("C:/no/such/python.exe" in state["reason"],
          f"the reason names the path: {state['reason']}")

    console_state = client.call("get_console")["console"]
    check(not console_state["editable"], "the prompt does not take typing with no interpreter")
    check(state["reason"] in console_state["transcript"],
          f"and the console says why: {console_state['transcript'][-200:]!r}")

    # The application still answers, which is the point of the check.
    check(client.call("ping")["ok"], "the application is still running")
    start_new_document(client)
    check(client.call("get_document")["document"]["name"] == "Untitled",
          "and still opens documents")

    client.call("set_preferences", preferences={"python_interpreter": good})
    check(await_python(client)["state"] == "READY", "a good path brings the interpreter back")


def run_no_python_session(port: int) -> None:
    """--no-python: an application with no interpreter and a dead console."""
    process = launch_app(port, user_args=["--no-python"])
    client = AutomationClient(port)
    try:
        client.connect()
        state = client.call("get_python")["python"]
        check(state["state"] == "OFF", f"--no-python starts without an interpreter: {state}")
        check(state["port"] == 0, "so no port was taken")
        check("--no-python" in state["reason"], f"and it says why: {state['reason']}")

        console_state = client.call("get_console")["console"]
        check(not console_state["editable"], "the prompt is switched off")
        check(not client.call("get_panels")["panels"]["console"], "and the panel starts hidden")

        # Everything that does not need Python still works.
        check(client.call("ping")["version"] == project_version(),
              "the application is otherwise the same")
        client.call("menu", item="new")
        titles = [entry["title"] for entry in client.call("get_features")["features"]]
        check(titles == ["Planet"], f"a new document opens: {titles}")
        check(len(client.call("get_scripts")["scripts"]) > 0,
              "the scripts are still listed, they simply cannot be run")
        client.call("quit")
    finally:
        client.close()
        try:
            process.wait(timeout=30)
        except Exception:
            pass
        if process.poll() is None:
            process.kill()


def write_gplates_files(folder: Path) -> list[Path]:
    """One plate's outline and the rotation that moves it, as GPlates holds them."""
    import pygplates

    outline = pygplates.Feature(pygplates.FeatureType.create_from_qualified_string("gpml:Coastline"))
    outline.set_geometry(pygplates.PolygonOnSphere([(-15, -15), (-15, 15), (15, 15), (15, -15)]))
    outline.set_reconstruction_plate_id(101)
    outline.set_valid_time(600, 0)
    outline.set_name("Imported Plate")

    # Twenty degrees about the north pole by 100 Ma, so the outline is ten
    # degrees east of where it started when the time is set to fifty.
    samples = [
        pygplates.GpmlTimeSample(pygplates.GpmlFiniteRotation(
            pygplates.FiniteRotation((90, 0), 0.0)), 0.0),
        pygplates.GpmlTimeSample(pygplates.GpmlFiniteRotation(
            pygplates.FiniteRotation((90, 0), math.radians(20.0))), 100.0),
    ]
    rotation = pygplates.Feature.create_total_reconstruction_sequence(
        0, 101, pygplates.GpmlIrregularSampling(samples))

    features, rotations = folder / "plate.gpml", folder / "plate.rot"
    pygplates.FeatureCollection([outline]).write(str(features))
    pygplates.FeatureCollection([rotation]).write(str(rotations))
    return [features, rotations]


def run_import_session(client: AutomationClient, folder: Path) -> None:
    """File > Import on a GPlates file, then look for the plate where it should be."""
    import pygplates

    sys.path.insert(0, str(ROOT / "src"))
    from middle_earth.gplates import plate_color

    sources = write_gplates_files(folder)

    # Import takes several files at once, which is what a feature collection
    # and the rotation file that moves it need.
    start_new_document(client)
    client.call("expect_file_dialog", paths=[str(path) for path in sources])
    client.call("menu", item="import")

    # The conversion is a round trip to the interpreter, so it is not done when
    # the menu item returns. The tree holds the root group and nothing else
    # until it is.
    titles: list = []
    for _ in range(120):
        titles = [entry["title"] for entry in client.call("get_features")["features"]]
        if len(titles) > 1:
            break
        time.sleep(0.5)

    check(titles == ["Planet", "Plate 101", "Imported Plate"],
          f"the import puts the feature under a group named after its plate: {titles}")

    document = client.call("get_document")["document"]
    check(document["path"] == "", f"an import has no file of its own: {document['path']!r}")
    check(document["dirty"], "and is offered for saving")

    client.call("select", title="Imported Plate")
    keyframes = client.call("get_selected")["feature"]["keyframes"]
    check(len(keyframes) >= 2,
          f"the feature carries its plate's sampled rotation: {len(keyframes)}")
    panel = client.call("get_properties")["properties"]
    check(panel["geometry"].startswith("polygon"), f"drawn as a polygon: {panel['geometry']!r}")
    check(panel["feature_type"] == "polygon",
          f"typed by its geometry: {panel['feature_type']!r}")

    # Where GPlates puts the middle of that outline at fifty million years.
    model = pygplates.RotationModel(str(sources[1]))
    latitude, longitude = (model.get_rotation(50.0, 101)
                           * pygplates.PointOnSphere((0.0, 0.0))).to_lat_lon()
    check(abs(longitude - 10.0) < 0.01, f"the plate has turned ten degrees by then: {longitude}")

    # Probing where the outline is, and where it is not, at both times. The
    # plate is drawn in a colour of its own, which is how GPlates tells one
    # plate from another; see Docs/Import.md.
    client.call("set_view", lat=0.0, lon=0.0, angle=0.0)
    wanted, _ = hue_and_saturation(plate_color(101))

    def is_plate(lat: float, lon: float) -> bool:
        screen = client.call("latlon_to_screen", lat=lat, lon=lon)["screen"]
        assert screen is not None, f"lat/lon ({lat}, {lon}) is off the visible hemisphere"
        color = client.call("get_pixel", x=screen[0], y=screen[1])["color"]
        hue, saturation = hue_and_saturation(color)
        return saturation > 0.15 and min(abs(hue - wanted), 1.0 - abs(hue - wanted)) < 0.03

    client.call("set_time", time=50.0)
    check(is_plate(latitude, longitude),
          "at fifty the plate is drawn in its own colour where GPlates reconstructs it")
    check(not is_plate(0.0, -10.0), "and is no longer where it stood at the present day")

    client.call("set_time", time=0.0)
    check(is_plate(0.0, -10.0), "at the present day it stands where GPlates draws it then")
    check(not is_plate(0.0, -20.0), "and stops where its outline stops")


def main(argv: list[str]) -> int:
    port = DEFAULT_PORT
    if argv:
        if len(argv) != 2 or argv[0] != "--port":
            print(USAGE, file=sys.stderr)
            return 2
        port = int(argv[1])

    process = launch_app(port)
    client = AutomationClient(port)
    connected = False
    try:
        client.connect()
        connected = True
        run_session(client)
        folder = Path(tempfile.mkdtemp(prefix="middle-earth-session-"))
        try:
            run_document_session(client, folder)
        finally:
            shutil.rmtree(folder, ignore_errors=True)
        run_drawing_session(client)
        run_point_undo_session(client)
        run_escape_session(client)
        run_properties_session(client)
        run_keyframe_row_session(client)
        folder = Path(tempfile.mkdtemp(prefix="middle-earth-coupling-"))
        try:
            run_coupling_session(client, folder)
        finally:
            shutil.rmtree(folder, ignore_errors=True)
        run_colour_session(client)
        folder = Path(tempfile.mkdtemp(prefix="middle-earth-icons-"))
        try:
            run_icon_checks(client, folder)
        finally:
            shutil.rmtree(folder, ignore_errors=True)
        run_globe_menu_session(client)
        run_edit_menu_session(client)
        run_time_session(client)
        run_projection_session(client)
        folder = Path(tempfile.mkdtemp(prefix="middle-earth-export-"))
        try:
            run_export_session(client, folder)
        finally:
            shutil.rmtree(folder, ignore_errors=True)
        folder = Path(tempfile.mkdtemp(prefix="middle-earth-scene-"))
        try:
            run_scene_session(client, folder)
        finally:
            shutil.rmtree(folder, ignore_errors=True)
        folder = Path(tempfile.mkdtemp(prefix="middle-earth-styling-"))
        try:
            run_styling_session(client, folder)
        finally:
            shutil.rmtree(folder, ignore_errors=True)
        run_vertex_session(client)
        run_snap_session(client)
        run_measure_session(client)
        run_split_session(client)
        run_split_tool_session(client)
        run_ridge_session(client)
        run_copy_shape_session(client)
        run_rotate_session(client)
        run_circle_session(client)
        run_topology_session(client)
        run_kinematics_session(client)
        run_python_session(client)
        folder = Path(tempfile.mkdtemp(prefix="middle-earth-import-"))
        try:
            run_import_session(client, folder)
        finally:
            shutil.rmtree(folder, ignore_errors=True)
        folder = Path(tempfile.mkdtemp(prefix="middle-earth-scripts-"))
        try:
            run_script_menu_session(client, folder)
        finally:
            shutil.rmtree(folder, ignore_errors=True)
        run_bad_interpreter_checks(client)
    finally:
        if connected:
            try:
                client.call("quit")
            except (OSError, RuntimeError):
                pass
            client.close()
        try:
            process.wait(timeout=30)
        except Exception:
            pass
        if process.poll() is None:
            process.kill()

    # An application of its own, because --no-python is settled at startup and
    # the one above was started without it.
    run_no_python_session(port + 1)

    print(f"{len(failures)} failed" if failures else "all checks passed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
