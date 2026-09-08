"""Shared fixtures for the Python tests. See Docs/Testing.md."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SAMPLES = ROOT / "Tests" / "Data"


def sample_paths() -> list[Path]:
    """Every sample document, in a fixed order so the ids do not move."""
    return sorted(SAMPLES.glob("*.middle-earth"))
