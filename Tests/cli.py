"""Check the command line switches of the application.

The application is started headless, so nothing can open a window: whatever
--version and --help print, they print before any of the interface exists.

Usage:
    python Tests/cli.py
"""

import os
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from automation_client import DEFAULT_GODOT

ROOT = Path(__file__).resolve().parents[1]

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


def switches() -> list[str]:
    """Every switch the application declares in Logic/cli.gd."""
    text = (ROOT / "Logic" / "cli.gd").read_text(encoding="utf-8")
    block = text[text.index("const SWITCHES"):text.index("const AUTOMATION_PORT_PREFIX")]
    return re.findall(r'\["(--[^"]+)"', block)


def run(*args: str) -> subprocess.CompletedProcess:
    """Start the application headless with the given user arguments."""
    godot = os.environ.get("GODOT", DEFAULT_GODOT)
    command = [godot, "--headless", "--path", str(ROOT), "--"] + list(args)
    return subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=120)


def main() -> int:
    version = project_version()

    result = run("--version")
    check(result.returncode == 0, f"--version exits cleanly, code {result.returncode}")
    check(version in result.stdout, f"--version prints {version}")

    result = run("--help")
    check(result.returncode == 0, f"--help exits cleanly, code {result.returncode}")
    for switch in switches():
        check(switch in result.stdout, f"--help lists {switch}")

    result = run("--nonsense")
    check(result.returncode != 0, "an unknown switch exits with a failure code")

    print(f"{len(failures)} failed" if failures else "all checks passed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
