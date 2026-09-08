"""Shared fixtures for the Python tests. See Docs/Testing.md."""

import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SAMPLES = ROOT / "Tests" / "Data"


def sample_paths() -> list[Path]:
    """Every sample document, in a fixed order so the ids do not move."""
    return sorted(SAMPLES.glob("*.middle-earth"))


### The data an installed GPlates brings with it

# The import tests read the feature collections, rotation files and projects
# that ship inside a GPlates install, because nothing that large and that real
# belongs in this repository. Where they are is `GPLATES_GEODATA`, or the
# default install directory. Without them those tests do not run; the ones that
# build their own data still do.
GEODATA = Path(os.environ.get("GPLATES_GEODATA")
               or r"C:\Program Files\GPlates\GPlates 2.5.0\GeoData")


def geodata(*parts: str) -> Path | None:
    """A file inside the GPlates data, or None when it is not installed."""
    path = GEODATA.joinpath(*parts)
    return path if path.exists() else None


def gplates_projects() -> list[Path]:
    """The `.gproj` files a GPlates install ships, in a fixed order."""
    return sorted(GEODATA.glob("*/*.gproj")) if GEODATA.is_dir() else []
