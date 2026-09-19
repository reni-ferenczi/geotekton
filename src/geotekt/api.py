"""The running application, reached from a script.

`App` turns each method into one request over the bridge and hands back what
the application answered. It holds no state of its own: every query asks the
application again, so a script always sees what is on the screen.

The application is the one place a document is edited. A script that wants to
work on a file without a window open reads it with `Document` instead; the two
have deliberately different shapes, because one is a picture of a file and the
other is a conversation with a program.

See Docs/Scripting.md.
"""

from __future__ import annotations

from typing import Any, Callable

from geotekt.document import Document, Feature


class AppError(RuntimeError):
    """The application refused a request and said why."""


class App:
    """The document the application has open."""

    def __init__(self, call: Callable[..., dict]) -> None:
        # One argument, the request dictionary, answering with the reply. The
        # bridge supplies it; a test supplies a stand-in.
        self._call = call

    def __repr__(self) -> str:
        return f"<App {self.name!r}, {len(self.features)} features>"

    def _ask(self, cmd: str, **params) -> dict:
        reply = self._call({"cmd": cmd, **params})
        if not reply.get("ok"):
            raise AppError(reply.get("error", f"{cmd} failed"))
        return reply

    ### The document

    @property
    def document(self) -> Document:
        """What the application has open, as it would be written to a file.

        A copy taken when it is asked for. Editing it changes nothing; the
        methods below are what change the document.
        """
        return Document(self._ask("document")["document"])

    @property
    def name(self) -> str:
        return str(self._ask("document")["name"])

    @property
    def features(self) -> list[Feature]:
        return self.document.features

    def find(self, uuid: str) -> Feature | None:
        return self.document.find(uuid)

    def named(self, title: str) -> Feature | None:
        return self.document.named(title)

    def new(self) -> None:
        self._ask("new")

    def open(self, path: str) -> None:
        self._ask("open", path=str(path))

    def save(self, path: str = "") -> None:
        """Save, to the given path or over the file the document came from."""
        self._ask("save", path=str(path))

    def undo(self) -> None:
        self._ask("undo")

    def redo(self) -> None:
        self._ask("redo")

    ### Features

    def add_feature(self, title: str, rings=(), geometry_kind: str = "polygon",
                    feature_type: str = "", parent: str = "") -> str:
        """Add a feature and return its uuid. `parent` is a group's uuid."""
        return str(self._ask(
            "add_feature",
            title=title,
            rings=[[[float(lat), float(lon)] for lat, lon in ring] for ring in rings],
            geometry_kind=geometry_kind,
            feature_type=feature_type,
            parent=parent,
        )["uuid"])

    def add_group(self, title: str, parent: str = "") -> str:
        return str(self._ask("add_group", title=title, parent=parent)["uuid"])

    def edit_feature(self, uuid: str, **fields: Any) -> None:
        """Change named fields of one feature.

        Any of title, enabled, feature_type, color, time_range and rings. A
        field that is not named is left as it is.
        """
        known = {"title", "enabled", "feature_type", "color", "time_range", "rings"}
        unknown = sorted(set(fields) - known)
        if unknown:
            raise AppError("a feature has no %s" % ", ".join(unknown))
        self._ask("edit_feature", uuid=uuid, fields=fields)

    def delete_feature(self, uuid: str) -> None:
        self._ask("delete_feature", uuid=uuid)

    ### Motion

    def set_keyframe(self, uuid: str, time: float, rotation) -> None:
        """Write the rotation the feature has at this time, in degrees."""
        x, y, z = rotation
        self._ask("set_keyframe", uuid=uuid, time=float(time),
                  rotation=[float(x), float(y), float(z)])

    def delete_keyframe(self, uuid: str, time: float) -> None:
        self._ask("delete_keyframe", uuid=uuid, time=float(time))

    ### Time

    @property
    def time(self) -> float:
        """The current time, an age in millions of years before present."""
        return float(self._ask("time")["time"])

    @time.setter
    def time(self, value: float) -> None:
        self._ask("set_time", time=float(value))

    def play(self) -> None:
        self._ask("play")

    def pause(self) -> None:
        self._ask("pause")

    @property
    def playing(self) -> bool:
        return bool(self._ask("time")["playing"])

    ### Selection

    @property
    def selected(self) -> str:
        """The uuid of the selected node, empty when nothing is selected."""
        return str(self._ask("selection")["uuid"])

    def select(self, uuid: str) -> None:
        self._ask("select", uuid=uuid)

    ### Exporting

    def export_image(self, path: str, width: int | None = None) -> tuple[int, int]:
        """Write the map at the current age to a PNG and answer its size.

        The height follows from the projection, so `width` settles both. Left
        out, it is the one the preferences hold. Refused while the globe is
        shown, which is a view of one side of the planet rather than a map.
        """
        size = self._ask("export_image", path=str(path), width=int(width or 0))["size"]
        return int(size[0]), int(size[1])

    def export_video(self, path: str, **options: float) -> dict:
        """Write the animation to a video and answer what came of it.

        The options are `from_`, `to`, `speed`, `fps` and `width`; whatever is
        left out is the animation's own setting, thirty frames a second and the
        Export width preference. The answer holds `frames`, how many were
        rendered, `encoded`, whether ffmpeg made a file of them, and `folder`,
        where they were left when it did not. `from` is a keyword in Python, so
        the first age is spelled `from_` here.
        """
        wanted = {("from" if key == "from_" else key): float(value)
                  for key, value in options.items()}
        reply = self._ask("export_video", path=str(path), options=wanted)
        return {"frames": int(reply["frames"]), "encoded": bool(reply["encoded"]),
                "path": str(reply["path"]), "folder": str(reply["folder"])}
