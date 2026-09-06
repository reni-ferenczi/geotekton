"""Run the Middle Earth test suites.

Usage:
    python Tests/run.py headless [--filter=SUBSTRING]
    python Tests/run.py rendered [--filter=SUBSTRING]
    python Tests/run.py session
    uv run Tests/run.py golden
    uv run Tests/run.py all

Set the GODOT environment variable to use a different engine binary.
See Docs/Testing.md.
"""

import importlib.util
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TESTS = ROOT / "Tests"
DEFAULT_GODOT = r"C:\Tools\Godot\Godot_v4.6.2-stable_win64_console.exe"
RUNNER = "res://Tests/run_tests.gd"

USAGE = "usage: run.py headless|rendered [--filter=SUBSTRING] | session | golden | all"


def godot() -> str:
    return os.environ.get("GODOT", DEFAULT_GODOT)


def import_project() -> int:
    """Import assets and refresh the script class cache; a clean checkout has neither."""
    command = [godot(), "--headless", "--path", str(ROOT), "--import", "--quit"]
    return subprocess.run(command, cwd=ROOT, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode


def run_godot(user_args: list[str]) -> int:
    """Run the GDScript test runner and return its exit code."""
    command = [godot(), "--headless"] if "--rendered" not in user_args else [godot()]
    command += ["--path", str(ROOT), "-s", RUNNER, "--"] + user_args
    return subprocess.run(command, cwd=ROOT).returncode


def run_script(name: str, script_args: list[str]) -> int:
    """Run one of the Python drivers next to this file."""
    command = [sys.executable, str(TESTS / name)] + script_args
    return subprocess.run(command, cwd=ROOT).returncode


def run_golden() -> int:
    """Run the golden image comparison, which needs Pillow."""
    if importlib.util.find_spec("PIL") is None:
        print("golden needs Pillow, run: uv run Tests/run.py golden", file=sys.stderr)
        return 2
    return run_script("golden.py", ["check"])


def run_all() -> int:
    """Run every mode in order and stop at the first failure."""
    for name, run in (
        ("headless", lambda: run_godot([])),
        ("rendered", lambda: run_godot(["--rendered"])),
        ("session", lambda: run_script("session.py", [])),
        ("golden", run_golden),
    ):
        print(f"=== {name} ===")
        code = run()
        if code != 0:
            print(f"{name} failed with exit code {code}", file=sys.stderr)
            return code
    return 0


def main(argv: list[str]) -> int:
    if not argv:
        print(USAGE, file=sys.stderr)
        return 2

    command = argv[0]
    options = argv[1:]
    if command not in ("headless", "rendered", "session", "golden", "all"):
        print(f"unknown command: {command}\n{USAGE}", file=sys.stderr)
        return 2
    if import_project() != 0:
        print("the Godot import step failed", file=sys.stderr)
        return 1

    if command in ("headless", "rendered"):
        for option in options:
            if not option.startswith("--filter="):
                print(f"unknown option: {option}\n{USAGE}", file=sys.stderr)
                return 2
        return run_godot((["--rendered"] if command == "rendered" else []) + options)

    if options:
        print(f"{command} takes no options\n{USAGE}", file=sys.stderr)
        return 2
    if command == "session":
        return run_script("session.py", [])
    if command == "golden":
        return run_golden()
    return run_all()


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
