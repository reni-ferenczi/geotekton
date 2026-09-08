"""Check that the test runner reports a broken run as a failure.

The runner has been wrong about this twice, and Tests/SelfCheck holds a fixture
for each case. This driver runs the runner over them and checks what it makes
of them.

GP-0022: a runtime error does not raise. The engine prints it, abandons the
method and returns, so the failure list stays empty and the runner used to
count the test as passed.

GP-0029: the errors printed while the application scene was being set up were
taken and thrown away by the first test that ran, so a run whose application
script did not compile reported every test as passed. That case needs a window
like the rendered mode, since the runner only builds the scene there.

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
RUNNER = "res://Tests/run_tests.gd"
FIXTURES = "--dir=res://Tests/SelfCheck"
BROKEN_SCENE = "--scene=res://Tests/SelfCheck/broken_application.tscn"
RUNTIME_ERROR_FILE = "Tests/SelfCheck/test_runtime_error.gd"
INTACT_FILE = "Tests/SelfCheck/test_intact.gd"
BROKEN = "test_reading_a_field_that_does_not_exist"
INTACT = "test_a_passing_method_still_passes"

failures: list[str] = []


def check(condition: bool, message: str) -> None:
    """Record and report one check."""
    print(f"{'PASS' if condition else 'FAIL'} {message}")
    if not condition:
        failures.append(message)


def run_runner(user_args: list[str], headless: bool = True) -> subprocess.CompletedProcess:
    """Run the GDScript runner over the fixtures and return what it did."""
    godot = os.environ.get("GODOT", DEFAULT_GODOT)
    command = [godot] + (["--headless"] if headless else [])
    command += ["--path", str(ROOT), "-s", RUNNER, "--"] + user_args
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=300)
    print(result.stdout)
    return result


def check_runtime_error() -> None:
    """A test method that hits a runtime error is a failure, not a pass."""
    result = run_runner([FIXTURES, "--filter=runtime_error"])

    check(result.returncode != 0, f"the run fails, exit code {result.returncode}")
    check(f"FAIL {RUNTIME_ERROR_FILE}::{BROKEN}" in result.stdout,
          "the broken method is reported as a failure")
    check(f"PASS {RUNTIME_ERROR_FILE}::{BROKEN}" not in result.stdout,
          "the broken method is not reported as passed")
    check(f"PASS {RUNTIME_ERROR_FILE}::{INTACT}" in result.stdout,
          "the intact method beside it still passes")
    check("1 passed, 1 failed" in result.stdout,
          "the summary counts one pass and one failure")


def check_scene_that_does_not_compile() -> None:
    """A script the hosted scene needs failing to compile fails the whole run."""
    result = run_runner(["--rendered", FIXTURES, "--filter=intact", BROKEN_SCENE],
                        headless=False)
    setup_errors = [line for line in result.stdout.splitlines()
                    if line.startswith("FAIL setup: script error:")]

    check(result.returncode != 0, f"the run fails, exit code {result.returncode}")
    check(any("broken_application.gd" in line for line in setup_errors),
          "the parse error is reported against the setup, naming the script")
    check("0 passed," in result.stdout, "no test is run after a setup that failed")
    check(f"PASS {INTACT_FILE}" not in result.stdout,
          "the test that would have passed is not reported as passed")


def main() -> int:
    check_runtime_error()
    check_scene_that_does_not_compile()

    print(f"{len(failures)} failed" if failures else "all checks passed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
