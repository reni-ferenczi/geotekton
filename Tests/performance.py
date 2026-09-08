"""Frame time during playback, on a document big enough to be worth measuring.

Builds a sample of a chosen triangle count, every feature of it moving, plays
the animation and samples the engine's own frame counters while it runs. The
number is read off the counters, never off how the animation looks.

This is not part of `run.py all`: a frame time depends on the machine and on
what else it is doing, so it is run on purpose rather than on every change.

Usage:
    uv run Tests/performance.py [--port N] [--triangles N] [--budget MS]
"""

import json
import statistics
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from automation_client import AutomationClient, launch_app

DEFAULT_PORT = 45457

# What the phase set out to hold: one frame at 60 frames per second, with the
# triangle count Docs/Shader.md calls heavy.
DEFAULT_TRIANGLES = 5000
DEFAULT_BUDGET_MS = 1000.0 / 60.0

# How the sample is built: this many features, each a circle cut into
# (VERTICES - 2) triangles, all of them moving between two keyframes.
FEATURES = 50
LATITUDES = [-40.0, -20.0, 0.0, 20.0, 40.0]
CIRCLE_RADIUS = 6.0

# How long to watch, and how much of the start to throw away while the shader
# compiles and the caches fill. One reading is answered per frame, so the run
# takes about as many frames as it takes samples.
#
# Only the frame time is reported. The engine's processor time counter is no
# use here, because reading it is itself a request per frame and the port
# traffic ends up larger than the work being measured.
SAMPLES = 120
WARMUP_SAMPLES = 30

USAGE = "usage: performance.py [--port N] [--triangles N] [--budget MS]"


def circle(lat: float, lon: float, vertices: int) -> list[list[float]]:
    """A ring of `vertices` points around a centre, as [latitude, longitude]."""
    from math import cos, pi, sin

    return [
        [
            lat + CIRCLE_RADIUS * sin(2.0 * pi * i / vertices),
            lon + CIRCLE_RADIUS * cos(2.0 * pi * i / vertices),
        ]
        for i in range(vertices)
    ]


def build_sample(path: Path, triangles: int) -> int:
    """Write a document of about `triangles` triangles. Returns the real count."""
    # Ear clipping turns a ring of n vertices into n - 2 triangles.
    per_feature = max(1, round(triangles / FEATURES))
    vertices = per_feature + 2

    children = []
    for i in range(FEATURES):
        lat = LATITUDES[i % len(LATITUDES)]
        lon = -170.0 + 340.0 * (i // len(LATITUDES)) / max(1, (FEATURES // len(LATITUDES)))
        children.append({
            "title": f"Blob {i}",
            "enabled": True,
            "is_group": False,
            "type": "Feature",
            "feature_type": "unclassified",
            "color": [0.2, 0.7, 0.3, 1.0],
            "geometry_kind": "polygon",
            "rings": [circle(lat, lon, vertices)],
            "time_range": [0, 2000],
            # Every feature moves, so a frame changes every rotation there is.
            "keyframes": [
                {"time": 0.0, "rotation": [0.0, 0.0, 0.0]},
                {"time": 400.0, "rotation": [40.0 + i, 10.0, 0.0]},
            ],
        })

    path.write_text(json.dumps({
        "application": "middle-earth",
        "version": "0.4.0",
        "features": {
            "title": "Planet",
            "enabled": True,
            "is_group": True,
            "type": "Group",
            "keyframes": [],
            "children": children,
        },
    }, indent="\t"), encoding="utf-8")
    return FEATURES * per_feature


def sample_frames(client: AutomationClient) -> list[float]:
    """Frame times in milliseconds, once the first few have settled."""
    frame_times: list[float] = []
    for i in range(SAMPLES):
        reading = client.call("get_performance")["performance"]
        if i >= WARMUP_SAMPLES and reading["fps"] > 0.0:
            frame_times.append(1000.0 / reading["fps"])
    return frame_times


def report(label: str, frame_times: list[float]) -> float:
    """Print how a run went and return its median frame time."""
    if not frame_times:
        print(f"{label}: the engine reported no frames")
        return float("inf")
    median = statistics.median(frame_times)
    print(f"{label}: median frame {median:.2f} ms, "
          f"95th percentile {sorted(frame_times)[int(len(frame_times) * 0.95) - 1]:.2f} ms, "
          f"worst {max(frame_times):.2f} ms")
    return median


def measure(client: AutomationClient, budget_ms: float) -> bool:
    """Report the frame time standing still and playing. False when over budget."""
    counts = client.call("get_performance")["performance"]
    print(f"{counts['primitives']} primitives from {counts['features']} features, "
          f"budget {budget_ms:.2f} ms")

    # Standing still first, so what playback adds can be told from what drawing
    # this much geometry costs whether anything moves or not.
    still = report("standing still", sample_frames(client))

    client.call("set_animation", animation={
        "start": 400.0, "end": 0.0, "increment": 2.0,
        "frames_per_second": 240.0, "loop": True, "land_on_end": True,
    })
    client.call("timeline", button="Reset")
    client.call("timeline", button="Play")
    playing = report("playing", sample_frames(client))
    client.call("timeline", button="Pause")

    print(f"playback costs {playing - still:+.2f} ms a frame")
    within = playing <= budget_ms
    print(f"{'PASS' if within else 'FAIL'} the median frame while playing is within the budget")
    return within


def main(argv: list[str]) -> int:
    port, triangles, budget = DEFAULT_PORT, DEFAULT_TRIANGLES, DEFAULT_BUDGET_MS
    while argv:
        if len(argv) < 2:
            print(USAGE, file=sys.stderr)
            return 2
        switch, value, argv = argv[0], argv[1], argv[2:]
        if switch == "--port":
            port = int(value)
        elif switch == "--triangles":
            triangles = int(value)
        elif switch == "--budget":
            budget = float(value)
        else:
            print(USAGE, file=sys.stderr)
            return 2

    folder = Path(tempfile.mkdtemp(prefix="middle-earth-performance-"))
    sample = folder / "performance.middle-earth"
    wanted = build_sample(sample, triangles)
    print(f"{wanted} triangles in {FEATURES} features written to {sample}")

    process = launch_app(port)
    client = AutomationClient(port)
    within = False
    try:
        client.connect()
        client.call("load", path=str(sample))
        within = measure(client, budget)
    finally:
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

    return 0 if within else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
