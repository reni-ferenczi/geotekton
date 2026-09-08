"""Check that the test runner reports a broken test as a failure.

GP-0022: a runtime error does not raise. The engine prints it, abandons the
method and returns, so the failure list stays empty and the runner used to
count the test as passed. Tests/SelfCheck holds a fixture that hits one; this
driver runs the runner over that folder and checks what it makes of it.

Usage:
    python Tests/self_check.py
"""

import os
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from automation_client import DEFAULT_GODOT

ROOT = Path(__file__).resolve().parents[1]
BROKEN = "test_reading_a_field_that_does_not_exist"
INTACT = "test_a_passing_method_still_passes"

failures: list[str] = []


def check(condition: bool, message: str) -> None:
    """Record and report one check."""
    print(f"{'PASS' if condition else 'FAIL'} {message}")
    if not condition:
        failures.append(message)


def main() -> int:
    godot = os.environ.get("GODOT", DEFAULT_GODOT)
    command = [godot, "--headless", "--path", str(ROOT), "-s", "res://Tests/run_tests.gd",
               "--", "--dir=res://Tests/SelfCheck"]
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=300)
    print(result.stdout)

    check(result.returncode != 0, f"the run fails, exit code {result.returncode}")
    check(f"FAIL Tests/SelfCheck/test_runtime_error.gd::{BROKEN}" in result.stdout,
          "the broken method is reported as a failure")
    check(f"PASS Tests/SelfCheck/test_runtime_error.gd::{BROKEN}" not in result.stdout,
          "the broken method is not reported as passed")
    check(f"PASS Tests/SelfCheck/test_runtime_error.gd::{INTACT}" in result.stdout,
          "the intact method beside it still passes")
    check("1 passed, 1 failed" in result.stdout,
          "the summary counts one pass and one failure")

    print(f"{len(failures)} failed" if failures else "all checks passed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
