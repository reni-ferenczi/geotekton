"""Scripting for Geotekton.

Two halves live here. `document` reads and writes `.geotekt` files on
their own, with no application running. `api` drives the application that
started this interpreter, over the bridge in `bridge`.

A script run from the application finds the running document as `app`; a
script run on its own imports what it needs from here.
"""

from geotekt.api import App
from geotekt.document import Document, Feature, Keyframe

__all__ = ["App", "Document", "Feature", "Keyframe"]
