"""Golden image tests: render known scenes and diff them against reference PNGs.

The references in Tests/Golden are looked at once by a human when they are
regenerated, and never again: a run compares pixels, it does not ask anyone to
judge a screenshot. A built-in negative control proves on every run that the
comparison can still tell two different scenes apart.

Usage:
    uv run Tests/golden.py check [--port N]
    uv run Tests/golden.py update [--port N]

Needs Pillow, which the uv environment provides.
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
DATA = ROOT / "Tests" / "Data"
GOLDEN = ROOT / "Tests" / "Golden"
DEFAULT_PORT = 45456

# A pixel counts as different when a channel is off by more than this, out of 255.
PIXEL_TOLERANCE = 8

# A scene fails when more than this fraction of its pixels are different.
MAX_DIFFERENT_FRACTION = 0.002

# Name, sample file, view, the scene settings the document carries, and the
# steps to take once it is loaded. Every scene states all of it, so the scenes
# stay independent of each other and of the order they run in.
DEFAULT_VIEW = {
    "lat": 0.0,
    "lon": 0.0,
    "angle": 0.0,
    "zoom": 1.0,
    "show_map": False,
    "projection": 0,
}

# The scene settings a document carries. A scene names only what it wants: a
# view block is read key by key, so everything it leaves out is the default,
# which is the scene as it was drawn before any of it was settable.
RASTER = str(ROOT / "Tests" / "Data" / "Rasters" / "quarters.png")

SCENES = [
    ("triangle", "triangle.geotekt", {}, {}, {}),
    ("two_cratons", "two_cratons.geotekt", {}, {}, {}),
    ("two_cratons_tilted", "two_cratons.geotekt", {"lat": 30.0, "lon": -45.0}, {}, {}),
    ("empty", "empty.geotekt", {}, {}, {}),
    # The sample is laid out so that the polygon, the polyline and both markers
    # all fit the default view.
    ("mixed_geometry", "mixed_geometry.geotekt", {}, {}, {}),
    # The one outline shaped like something real, drawn facing the camera so
    # that its bay, its neck and its northern lobe are all in the reference and
    # none of it runs off the limb. See GP-0026.
    ("craton", "craton.geotekt", {}, {}, {}),
    # The grid and the features in each projection, which is what says the
    # inverse in the shader agrees with the one in MapProjection. The sample is
    # the one with features north, south and either side of the middle, so the
    # whole sheet has something on it.
    ("map_rectangular", "two_cratons.geotekt", {"show_map": True, "projection": 0}, {}, {}),
    ("map_mercator", "two_cratons.geotekt", {"show_map": True, "projection": 1}, {}, {}),
    ("map_mollweide", "two_cratons.geotekt", {"show_map": True, "projection": 2}, {}, {}),
    ("map_robinson", "two_cratons.geotekt", {"show_map": True, "projection": 3}, {}, {}),
    ("map_orthographic", "two_cratons.geotekt", {"show_map": True, "projection": 4}, {}, {}),
    # The scene around the features. Every other scene has the star field on and
    # the light straight from the camera, so those two are covered already; what
    # is left is the star field off, the light somewhere else, and the planet
    # wearing an image.
    ("scene_no_stars", "two_cratons.geotekt", {},
        {"star_field": False, "background_color": [0.05, 0.02, 0.12, 1.0]}, {}),
    ("scene_light_east", "empty.geotekt", {}, {"light_direction": [0.0, 45.0]}, {}),
    ("scene_light_high", "empty.geotekt", {},
        {"light_direction": [55.0, -35.0], "ambient": 0.25}, {}),
    ("scene_raster", "empty.geotekt", {}, {"raster_path": RASTER}, {}),
    ("scene_raster_half", "empty.geotekt", {},
        {"raster_path": RASTER, "raster_opacity": 0.5}, {}),
    # The planet with no raster, in a color of its own.
    ("planet_colour", "empty.geotekt", {},
        {"raster_path": "", "planet_color": [0.55, 0.35, 0.2, 1.0]}, {}),
    # The kinematics panel, drawn for a feature that moves. The only scene that
    # shows that panel and the only one that selects anything: the graphs are
    # drawn for whatever the feature tree has selected, with the cursor on the
    # current time.
    ("kinematics", "motion.geotekt", {}, {},
        {"kinematics": True, "select": "Drifting Craton", "time": 500.0}),
]

USAGE = "usage: golden.py check|update [--port N]"


def compare(a, b) -> float:
    """Fraction of pixels where the two images differ by more than the tolerance."""
    from PIL import ImageChops

    if a.size != b.size:
        return 1.0
    difference = ImageChops.difference(a.convert("RGB"), b.convert("RGB"))
    red, green, blue = difference.split()
    worst = ImageChops.lighter(ImageChops.lighter(red, green), blue)
    different = sum(worst.histogram()[PIXEL_TOLERANCE + 1:])
    return different / (a.width * a.height)


def capture(client: AutomationClient, temp_dir: Path) -> dict[str, Path]:
    """Render every scene and return the path of each fresh screenshot."""
    shots: dict[str, Path] = {}
    for name, sample, view, settings, steps in SCENES:
        # Loading clears the selection and puts the time at the oldest age the
        # animation covers, so a scene only has to state what it wants beyond
        # that. The kinematics panel is not part of a document, so every scene
        # says whether it is up.
        client.call("load", path=str(sample_with_settings(sample, settings, temp_dir, name)))
        client.call("set_view", **(DEFAULT_VIEW | view))
        show_kinematics(client, steps.get("kinematics", False))
        if "select" in steps:
            client.call("select", title=steps["select"])
        if "time" in steps:
            client.call("set_time", time=steps["time"])
        # The port awaits two frames per command, so this round trip is the wait.
        client.call("get_view")
        path = temp_dir / f"{name}.png"
        client.call("screenshot", path=str(path))
        shots[name] = path
    return shots


def show_kinematics(client: AutomationClient, shown: bool) -> None:
    """Put the kinematics panel up or down, whichever the scene asks for."""
    if client.call("get_panels")["panels"]["kinematics"] != shown:
        client.call("menu", item="kinematics")


def sample_with_settings(sample: str, settings: dict, temp_dir: Path, name: str) -> Path:
    """The sample file, or a copy of it carrying the scene settings this scene wants.

    The settings are put in the file rather than set through the dialog so that
    every scene renders a document that has just been opened and has nothing to
    save: a dirty document writes a marker into the title and the status bar,
    which would be the only difference between half the references.
    """
    if not settings:
        return DATA / sample
    data = json.loads((DATA / sample).read_text(encoding="utf-8"))
    data["view"] = settings
    # A file from before 0.17.0 that names no raster opens wearing the built in
    # Earth, so a scene stating its raster is written in the current format.
    if "raster_path" in settings:
        data["version"] = project_version()
    path = temp_dir / f"{name}.geotekt"
    path.write_text(json.dumps(data, indent="	"), encoding="utf-8")
    return path


def project_version() -> str:
    """The application version declared in project.godot."""
    text = (ROOT / "project.godot").read_text(encoding="utf-8")
    match = re.search(r'^config/version\s*=\s*"([^"]+)"', text, re.MULTILINE)
    assert match is not None, "config/version not found in project.godot"
    return match.group(1)


def check(shots: dict[str, Path]) -> bool:
    """Diff every screenshot against its reference and run the negative control."""
    from PIL import Image

    ok = True
    for name, shot in shots.items():
        reference = GOLDEN / f"{name}.png"
        if not reference.exists():
            print(f"FAIL {name}: no reference, run 'uv run Tests/golden.py update'")
            ok = False
            continue
        fraction = compare(Image.open(shot), Image.open(reference))
        passed = fraction <= MAX_DIFFERENT_FRACTION
        print(f"{name}: {fraction:.6f} different {'PASS' if passed else 'FAIL'}")
        if not passed:
            actual = GOLDEN / f"{name}.actual.png"
            shutil.copyfile(shot, actual)
            print(f"    wrote {actual}")
            ok = False

    fraction = compare(Image.open(shots["triangle"]), Image.open(GOLDEN / "empty.png"))
    if fraction > MAX_DIFFERENT_FRACTION:
        print(f"negative control: {fraction:.6f} different PASS")
    else:
        print(f"negative control: {fraction:.6f} different FAIL, the comparison is blind")
        ok = False
    return ok


def update(shots: dict[str, Path]) -> bool:
    """Overwrite the references and report which ones changed."""
    for name, shot in shots.items():
        reference = GOLDEN / f"{name}.png"
        changed = not reference.exists() or reference.read_bytes() != shot.read_bytes()
        shutil.copyfile(shot, reference)
        print(f"{name}: {'updated' if changed else 'unchanged'} {reference}")
    print("look at the references once, then commit them")
    return True


def main(argv: list[str]) -> int:
    if not argv or argv[0] not in ("check", "update"):
        print(USAGE, file=sys.stderr)
        return 2
    command = argv[0]
    port = DEFAULT_PORT
    if argv[1:]:
        if len(argv) != 3 or argv[1] != "--port":
            print(USAGE, file=sys.stderr)
            return 2
        port = int(argv[2])

    GOLDEN.mkdir(parents=True, exist_ok=True)
    process = launch_app(port)
    client = AutomationClient(port)
    connected = False
    try:
        client.connect()
        connected = True
        with tempfile.TemporaryDirectory(prefix="geotekt-golden-") as temp:
            shots = capture(client, Path(temp))
            ok = check(shots) if command == "check" else update(shots)
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

    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
