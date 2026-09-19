"""Start the scripting bridge: python src/geotekt/__main__.py --port=PORT

Runnable as a file as well as with -m, because the application starts it by
path: the package is not installed into the interpreter it is given, so the
folder holding it is put on the import path here.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from geotekt.bridge import main  # noqa: E402  (the path has to come first)

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
