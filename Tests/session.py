"""Scripted automation session against a running application.

Launches the application with the automation port open, drives it through a
short scenario and checks the answers. Nothing here is judged by looking at a
screenshot: every claim about what is on screen is a pixel probe or a
coordinate returned by the port.

Usage:
    python Tests/session.py [--port N]
"""

import json
import math
import re
import shutil
import sys
import tempfile
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


def run_drawing_session(client: AutomationClient) -> None:
    """Draw one feature of each geometry kind and check what it stored."""
    for kind, points in DRAWINGS.items():
        start_new_document(client)
        client.call("toolbar", button="AddFeature")

        tool = client.call("get_tool")
        check(tool["tool"] == "draw", f"the Draw tool arms itself on an empty feature ({kind})")
        check(not tool["kind_locked"], f"the kind can still be chosen ({kind})")
        client.call("set_tool", tool="draw", kind=kind)

        if not draw(client, points):
            continue
        check(client.call("get_tool")["drawing_vertices"] == len(points),
              f"{len(points)} vertices are placed ({kind})")
        client.call("key", key="Enter")

        feature = client.call("get_selected")["feature"]
        check(feature["geometry_kind"] == kind, f"the feature is a {kind}: {feature['geometry_kind']}")
        if check(len(feature["rings"]) == 1, f"one ring was committed ({kind})"):
            ring = feature["rings"][0]
            if check(len(ring) == len(points), f"the ring holds {len(points)} vertices ({kind})"):
                offset = worst_offset(ring, points)
                check(offset < CLICK_TOLERANCE,
                      f"the stored vertices match the clicked points within "
                      f"{CLICK_TOLERANCE} degrees ({kind}): {offset:.6f}")
        check(client.call("get_tool")["kind_locked"],
              f"the kind is fixed once the feature holds geometry ({kind})")

        # Undo takes the geometry off again, leaving the empty feature behind.
        client.call("toolbar", button="Undo")
        check(client.call("get_selected")["feature"]["rings"] == [],
              f"undo removes the committed geometry ({kind})")


def run_escape_session(client: AutomationClient) -> None:
    """Escape throws the shape being drawn away without touching the feature."""
    start_new_document(client)
    client.call("toolbar", button="AddFeature")
    client.call("set_tool", tool="draw", kind="polygon")
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


def part_sizes(panel: dict) -> list[int]:
    """How many vertices the coordinate table shows in each part."""
    return [len(part) for part in panel["coordinates"]]


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
    check(panel["feature_type"] == "unclassified", f"its type: {panel['feature_type']}")
    check(panel["color"][:3] == [1.0, 0.0, 0.0], f"its colour: {panel['color']}")
    check(panel["enabled"] is True, "its enabled flag")
    check(panel["time_range"] == [0, 2000], f"its time range: {panel['time_range']}")
    check(part_sizes(panel) == [3], f"and the three vertices of its geometry: {panel['coordinates']}")
    check("3 vertices in 1 part" in panel["geometry"], f"summarized as: {panel['geometry']}")

    # A group has a name and a switch and nothing else, so that is all it shows.
    client.call("select", title="Shapes")
    panel = client.call("get_properties")["properties"]
    check(panel["showing"] == "group", "selecting a group shows the group properties")
    check(panel["name"] == "Shapes" and "feature_type" not in panel,
          f"a group has no type, colour or geometry: {sorted(panel)}")

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
    client.call("set_property", field="feature_type", value="craton")
    dialog = client.call("get_dialog")["dialog"]
    if check(dialog is not None, "a polyline cannot be a craton, and the panel says so"):
        client.call("dialog", button="OK")
    check(client.call("get_properties")["properties"]["feature_type"] == "unclassified",
          "the refused type is off the selector again")
    check(client.call("get_selected")["feature"]["feature_type"] == "unclassified",
          "and never reached the feature")

    # One that does fit is taken, and leaves the colour the file picked alone.
    client.call("set_property", field="feature_type", value="ridge")
    check(client.call("get_selected")["feature"]["feature_type"] == "ridge",
          "a polyline may be a ridge")
    check(client.call("get_properties")["properties"]["color"] == [0.0, 0.0, 1.0, 1.0],
          "and the blue the file picked survives the type change")

    # A time range that ends before it starts is refused the same way.
    client.call("set_property", field="time_from", value=500)
    check(client.call("get_selected")["feature"]["time_range"] == [500, 2000],
          "the start of the time range is taken")
    client.call("set_property", field="time_to", value=100)
    dialog = client.call("get_dialog")["dialog"]
    if check(dialog is not None, "a range that ends before it starts is refused"):
        client.call("dialog", button="OK")
    check(client.call("get_selected")["feature"]["time_range"] == [500, 2000],
          "and the feature keeps the range it had")
    check(client.call("get_properties")["properties"]["time_range"] == [500, 2000],
          "which is what the panel shows again")

    # The switch in the panel is the switch on the tree row.
    client.call("set_property", field="enabled", value=False)
    check(client.call("get_selected")["feature"]["enabled"] is False,
          "the panel disables the feature")
    client.call("set_property", field="enabled", value=True)

    # The type restricts what the Draw tool offers, while there is no geometry
    # yet for the kind to be fixed by.
    client.call("toolbar", button="AddFeature")
    check(sorted(client.call("get_tool")["allowed_kinds"])
          == ["multipoint", "polygon", "polyline"],
          "an unclassified feature may be drawn in any kind")
    unclassified_color = client.call("get_properties")["properties"]["color"]
    client.call("set_property", field="feature_type", value="ridge")
    check(client.call("get_tool")["allowed_kinds"] == ["polyline"],
          "a ridge may only be drawn as a polyline")
    # Nobody picked a colour for this one, so it takes the one the type gives.
    check(client.call("get_properties")["properties"]["color"] != unclassified_color,
          "and a new feature takes the colour of the type it is given")


def run_coordinate_session(client: AutomationClient) -> None:
    """The coordinate table: adding a vertex and taking one off again."""
    open_mixed_geometry(client)
    client.call("select", title="Green Stations")
    panel = client.call("get_properties")["properties"]
    check(part_sizes(panel) == [2], f"the multipoint holds two markers: {panel['coordinates']}")

    client.call("properties", button="Add", part=0, index=0)
    panel = client.call("get_properties")["properties"]
    check(part_sizes(panel) == [3], f"Add puts a third one in: {panel['coordinates']}")
    check(panel["coordinates"][0][1] == panel["coordinates"][0][0],
          "on top of the one it was added after")
    check(client.call("get_selected")["feature"]["rings"][0][1] == panel["coordinates"][0][0],
          "and the feature holds it too")

    client.call("properties", button="Remove", part=0, index=1)
    check(part_sizes(client.call("get_properties")["properties"]) == [2],
          "Remove takes it off again")
    client.call("menu", item="undo")
    check(part_sizes(client.call("get_properties")["properties"]) == [3],
          "and undo brings it back")


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
    client.call("set_tool", tool="draw", kind="polygon")
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
    client.call("set_property", field="time_from", value=0)
    client.call("set_property", field="time_to", value=1000)

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
    client.call("set_property", field="time_to", value=2000)
    check(client.call("get_selected")["feature"]["exists_now"],
          "widening the range brings it back")
    color = client.call("get_pixel", x=screen[0], y=screen[1])["color"]
    check(dominant(color) == "green", f"and the same probe is green again: {color}")


def run_timeline_checks(client: AutomationClient) -> None:
    """The time control: the markers, the step buttons and playback."""
    client.call("set_animation", animation={
        "start": 400.0, "end": 0.0, "increment": 100.0,
        "frames_per_second": 60.0, "loop": False, "land_on_end": True,
    })
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
    check(client.call("get_time")["time"] == 300.0, "a step towards the younger end")
    check(client.call("get_timeline")["timeline"]["typed"] == 300.0,
          "which the typed time field shows as well")
    client.call("timeline", button="Older")
    check(client.call("get_time")["time"] == 400.0, "and one back towards the older")

    # A time typed in reaches the slider through the document, the same way a
    # time set from a script does.
    client.call("set_time", time=123.0)
    timeline = client.call("get_timeline")["timeline"]
    check(timeline["typed"] == 123.0 and timeline["slider"] == -123.0,
          f"a time set anywhere reaches both the field and the slider: {timeline['slider']}")

    # An animation long enough that it cannot run out between the request that
    # starts it and the one that stops it.
    client.call("set_animation", animation={"increment": 1.0, "frames_per_second": 60.0})
    client.call("timeline", button="Reset")
    client.call("timeline", button="Play")
    check(client.call("get_timeline")["timeline"]["playing"], "Play starts the animation")
    client.call("timeline", button="Pause")
    check(not client.call("get_timeline")["timeline"]["playing"], "and Pause stops it")
    check(client.call("get_time")["time"] < 400.0, "having moved the time along the way")

    # Playing to the end without looping stops there rather than wrapping.
    client.call("set_animation", animation={"increment": 100.0, "frames_per_second": 240.0})
    client.call("timeline", button="Reset")
    client.call("timeline", button="Play")
    for _ in range(20):
        if not client.call("get_timeline")["timeline"]["playing"]:
            break
    check(client.call("get_time")["time"] == 0.0,
          f"the animation stops on the end time: {client.call('get_time')['time']}")
    check(not client.call("get_timeline")["timeline"]["playing"], "and stops playing there")


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
    """Start a document, click the points with the Circle tool and commit."""
    start_new_document(client)
    client.call("toolbar", button="AddFeature")
    client.call("set_tool", tool="draw", kind=kind)
    client.call("set_tool", tool="circle", segments=CIRCLE_SEGMENTS)
    check(client.call("get_tool")["tool"] == "circle", f"the Circle tool is armed ({kind})")
    if not draw(client, points):
        return {}
    return client.call("get_tool")


def run_circle_session(client: AutomationClient) -> None:
    """A small circle from a centre and a rim point, and one through three points."""
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
    check(client.call("get_selected")["feature"]["geometry_kind"] == "polygon",
          "and the feature is a polygon")

    # A polyline of the same segment count draws the whole circle, so it repeats
    # its first vertex at the end.
    tool = build_circle(client, "polyline", [CIRCLE_CENTRE, rim])
    if tool:
        client.call("key", key="Enter")
        feature = client.call("get_selected")["feature"]
        if check(len(feature["rings"]) == 1, "the polyline circle is committed as one part"):
            check(len(feature["rings"][0]) == CIRCLE_SEGMENTS + 1,
                  f"and holds a vertex more than it has segments: {len(feature['rings'][0])}")

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
    client.call("set_tool", tool="draw", kind="polyline")
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
    client.call("set_tool", tool="topology")
    check(client.call("get_tool")["tool"] == "topology", "the Topology tool is armed")

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


# The scene as ViewSettings draws it before a document says anything, which is
# what the preferences are put back to at the end of the scenario.
DEFAULT_VIEW_SETTINGS = {
    "background_color": [0.0, 0.0, 0.0, 1.0],
    "star_field": True,
    "graticule_color": [1.0, 1.0, 1.0, 0.3333],
    "graticule_spacing": 15.0,
    "light_direction": [0.0, 0.0],
    "ambient": 0.0,
    "backdrop_path": "",
    "backdrop_opacity": 1.0,
    "backdrop_visible": True,
}


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
    client.call("press", x=start[0], y=start[1])
    client.call("mouse_move", x=end[0], y=end[1])
    client.call("release", x=end[0], y=end[1])

    stored = client.call("get_view_settings")["view_settings"]["light_direction"]
    check(abs(stored[0] - target[0]) < 0.1 and abs(stored[1] - target[1]) < 0.1,
          f"the drag put the light at {stored}")

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
    # documents they expect rather than the ones this scenario asked for.
    client.call("load", path=str(sample))
    client.call("set_view_settings", button="RestoreDefaults")
    client.call("set_view_settings", view_settings=DEFAULT_VIEW_SETTINGS)
    client.call("view", projection="globe")
    client.call("set_view_settings", button="SaveAsDefault")
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
    client.call("set_tool", tool="draw", kind="polygon")
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
    client.call("set_tool", tool="draw", kind="polygon")
    if not draw(client, VERTEX_POLYGON):
        return
    client.call("key", key="Enter")
    client.call("set_property", field="name", value="Anchor")

    client.call("toolbar", button="AddFeature")
    client.call("set_tool", tool="draw", kind="polygon")
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
    client.call("set_tool", tool="draw", kind="polygon")
    if not draw(client, SPLIT_POLYGON):
        return
    client.call("key", key="Enter")
    client.call("set_property", field="name", value="Whole")
    client.call("set_property", field="color", value=[0.0, 0.0, 1.0, 1.0])
    client.call("set_property", field="time_to", value=1500)
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
    check(client.call("get_tool")["can_split"], "the Split button is offered")
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
        run_escape_session(client)
        run_properties_session(client)
        run_coordinate_session(client)
        run_colour_session(client)
        run_globe_menu_session(client)
        run_edit_menu_session(client)
        run_time_session(client)
        run_projection_session(client)
        folder = Path(tempfile.mkdtemp(prefix="middle-earth-scene-"))
        try:
            run_scene_session(client, folder)
        finally:
            shutil.rmtree(folder, ignore_errors=True)
        run_vertex_session(client)
        run_snap_session(client)
        run_measure_session(client)
        run_split_session(client)
        run_circle_session(client)
        run_topology_session(client)
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

    print(f"{len(failures)} failed" if failures else "all checks passed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
