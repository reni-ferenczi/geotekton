"""Scripted automation session against a running application.

Launches the application with the automation port open, drives it through a
short scenario and checks the answers. Nothing here is judged by looking at a
screenshot: every claim about what is on screen is a pixel probe or a
coordinate returned by the port.

Usage:
    python Tests/session.py [--port N]
"""

import json
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


def is_green(color: list[float]) -> bool:
    """True when the pixel is dominated by the green channel."""
    red, green, blue = color[0], color[1], color[2]
    return green > 0.5 and red < 0.3 and blue < 0.3


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
    check(len(selected["vertices"]) == 6, "Blue Quad has 6 vertices (two triangles)")

    client.call("select", title=None)
    clear = client.call("latlon_to_screen", lat=5.0, lon=40.0)["screen"]
    if check(clear is not None, "lat/lon (5, 40) is on the visible hemisphere"):
        clear_color = client.call("get_pixel", x=clear[0], y=clear[1])["color"]
        check(not is_green(clear_color), f"the pixel at (5, 40) is not green: {clear_color}")

    # Turn the globe so that Green Moved faces the camera. At the default view it
    # sits within two degrees of the horizon, where the surface is barely lit and
    # the collision sphere is a touch smaller than the drawn one, so clicks there
    # miss the globe.
    client.call("set_view", lon=-60.0)
    check(client.call("get_view")["lon"] == -60.0, "set_view turns the globe to longitude -60")

    screen = client.call("latlon_to_screen", lat=-3.0, lon=-60.0)["screen"]
    if not check(screen is not None, "lat/lon (-3, -60) is on the visible hemisphere"):
        return

    client.call("click", x=screen[0], y=screen[1], button="left")
    selected = client.call("get_selected")["feature"]
    check(selected["title"] == "Green Moved", "clicking (-3, -60) selects Green Moved")
    check(len(selected["vertices"]) == 3, "Green Moved has 3 vertices")
    check(len(selected["world_vertices"]) == 3, "Green Moved has 3 world vertices")
    check(selected["world_vertices"] != selected["vertices"], "Green Moved is rotated")

    # Take the mouse off the craton first: the one under the pointer is drawn
    # highlighted, which is a different green from the one the file asks for.
    away = client.call("latlon_to_screen", lat=30.0, lon=-90.0)["screen"]
    client.call("mouse_move", x=away[0], y=away[1])
    color = client.call("get_pixel", x=screen[0], y=screen[1])["color"]
    check(is_green(color), f"the pixel at (-3, -60) is green: {color}")

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
