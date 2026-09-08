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


def dominant(color: list[float]) -> str:
    """The channel a probed pixel is dominated by, empty when none is."""
    red, green, blue = color[0], color[1], color[2]
    for name, value, others in (
        ("red", red, (green, blue)),
        ("green", green, (red, blue)),
        ("blue", blue, (red, green)),
    ):
        if value > 0.5 and max(others) < 0.3:
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

    client.call("menu", item="copy")
    try:
        client.call("menu", item="paste")
    except RuntimeError as error:
        check(False, f"Edit > Paste is available right after Edit > Copy: {error}")
    else:
        check(len(client.call("get_features")["features"]) == before + 1,
              "Edit > Copy then Edit > Paste adds a feature")
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
