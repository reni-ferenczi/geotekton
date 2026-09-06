"""Run the Middle Earth test suites.

Usage:
    python Tests/run.py headless [--filter=SUBSTRING]
    python Tests/run.py rendered [--filter=SUBSTRING]

Set the GODOT environment variable to use a different engine binary.
"""

import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_GODOT = r"C:\Tools\Godot\Godot_v4.6.2-stable_win64_console.exe"
RUNNER = "res://Tests/run_tests.gd"

USAGE = "usage: run.py headless|rendered [--filter=SUBSTRING]"


def run_godot(user_args: list[str]) -> int:
    """Run the GDScript test runner and return its exit code."""
    godot = os.environ.get("GODOT", DEFAULT_GODOT)
    command = [godot, "--headless"] if "--rendered" not in user_args else [godot]
    command += ["--path", str(ROOT), "-s", RUNNER, "--"] + user_args
    return subprocess.run(command, cwd=ROOT).returncode


def main(argv: list[str]) -> int:
    if not argv:
        print(USAGE, file=sys.stderr)
        return 2

    command = argv[0]
    options = argv[1:]
    for option in options:
        if not option.startswith("--filter="):
            print(f"unknown option: {option}\n{USAGE}", file=sys.stderr)
            return 2

    if command == "headless":
        return run_godot(options)
    if command == "rendered":
        return run_godot(["--rendered"] + options)
    if command in ("session", "golden"):
        print(f"the {command} command is not implemented yet", file=sys.stderr)
        return 2

    print(f"unknown command: {command}\n{USAGE}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
