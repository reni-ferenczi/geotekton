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

# Name, sample file, view. Every scene states its whole view, so the scenes stay
# independent of each other and of the order they run in.
DEFAULT_VIEW = {"lat": 0.0, "lon": 0.0, "angle": 0.0, "fov": 60.0, "show_map": False}
SCENES = [
    ("triangle", "triangle.middle-earth", {}),
    ("two_cratons", "two_cratons.middle-earth", {}),
    ("two_cratons_tilted", "two_cratons.middle-earth", {"lat": 30.0, "lon": -45.0}),
    ("empty", "empty.middle-earth", {}),
    # The sample is laid out so that the polygon, the polyline and both markers
    # all fit the default view.
    ("mixed_geometry", "mixed_geometry.middle-earth", {}),
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
    for name, sample, view in SCENES:
        client.call("load", path=str(DATA / sample))
        client.call("set_view", **(DEFAULT_VIEW | view))
        # The port awaits two frames per command, so this round trip is the wait.
        client.call("get_view")
        path = temp_dir / f"{name}.png"
        client.call("screenshot", path=str(path))
        shots[name] = path
    return shots


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
        with tempfile.TemporaryDirectory(prefix="middle-earth-golden-") as temp:
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
