"""The Middle Earth file format, read and written as the application writes it.

A document is kept as the JSON it was parsed from, and the classes here are
views onto that JSON rather than a second copy of it. Reading a file and
writing it back therefore gives the same bytes, whatever format version the
file was written at, and this module does not have to carry a copy of the
migrations in `Logic/document.gd`.

`json.dumps` with a tab indent and sorted keys is what Godot's
`JSON.stringify(data, "\t")` produces, which is what makes the round trip
exact. The one place the two can part company is a float with no short
decimal form: Godot prints fourteen significant digits and Python prints the
shortest text that reads back as the same double. Both are valid JSON and
both load, so only byte equality is affected, and only for numbers a script
computed rather than ones a person typed.

See Docs/Scripting.md and Docs/Persistence.md.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Iterator

APPLICATION = "middle-earth"
EXTENSION = ".middle-earth"

# What a document this package writes from scratch says it is. It follows
# `application/config/version` in `project.godot`, which is what the
# application writes, and a test holds the two together.
CURRENT_VERSION = "0.20.0"

# What a feature without the key is taken to be, matching Logic/feature.gd.
DEFAULT_COLOR = [0.82, 0.41, 0.12, 1.0]
DEFAULT_TIME_RANGE = [0, 2000]
DEFAULT_GEOMETRY_KIND = "polygon"
DEFAULT_FEATURE_TYPE = ""
# The glyph a feature's tree row carries; empty is none, which is the default
# and is left out of the file. Ids are in Logic/feature_icon.gd.
DEFAULT_ICON = ""


def dumps(data: Any) -> str:
    """The JSON text the application would write for this data."""
    return json.dumps(data, indent="\t", sort_keys=True)


class Keyframe:
    """A time and the rotation a feature has then, in degrees."""

    def __init__(self, data: dict) -> None:
        self.data = data

    def __repr__(self) -> str:
        return f"Keyframe(time={self.time!r}, rotation={self.rotation!r})"

    @property
    def time(self) -> float:
        return float(self.data.get("time", 0.0))

    @time.setter
    def time(self, value: float) -> None:
        self.data["time"] = float(value)

    @property
    def rotation(self) -> tuple[float, float, float]:
        x, y, z = self.data.get("rotation", [0.0, 0.0, 0.0])
        return float(x), float(y), float(z)

    @rotation.setter
    def rotation(self, value) -> None:
        x, y, z = value
        self.data["rotation"] = [float(x), float(y), float(z)]


class Feature:
    """A feature or a group in the tree, as the file holds it."""

    def __init__(self, data: dict) -> None:
        self.data = data

    def __repr__(self) -> str:
        kind = "Group" if self.is_group else self.geometry_kind
        return f"Feature({self.title!r}, {kind}, uuid={self.uuid!r})"

    ### What it is

    @property
    def uuid(self) -> str:
        return str(self.data.get("uuid", ""))

    @property
    def title(self) -> str:
        return str(self.data.get("title", ""))

    @title.setter
    def title(self, value: str) -> None:
        self.data["title"] = str(value)

    @property
    def is_group(self) -> bool:
        return bool(self.data.get("is_group", self.data.get("type") == "Group"))

    @property
    def enabled(self) -> bool:
        return bool(self.data.get("enabled", True))

    @enabled.setter
    def enabled(self, value: bool) -> None:
        self.data["enabled"] = bool(value)

    @property
    def feature_type(self) -> str:
        return str(self.data.get("feature_type", DEFAULT_FEATURE_TYPE))

    @feature_type.setter
    def feature_type(self, value: str) -> None:
        self.data["feature_type"] = str(value)

    @property
    def icon(self) -> str:
        return str(self.data.get("icon", DEFAULT_ICON))

    @icon.setter
    def icon(self, value: str) -> None:
        # No icon is written as no key, the way the application writes it.
        if str(value):
            self.data["icon"] = str(value)
        else:
            self.data.pop("icon", None)

    @property
    def geometry_kind(self) -> str:
        return str(self.data.get("geometry_kind", DEFAULT_GEOMETRY_KIND))

    @property
    def color(self) -> tuple[float, float, float, float]:
        r, g, b, a = self.data.get("color", DEFAULT_COLOR)
        return float(r), float(g), float(b), float(a)

    @color.setter
    def color(self, value) -> None:
        self.data["color"] = [float(c) for c in value]

    @property
    def time_range(self) -> tuple[int, int]:
        start, end = self.data.get("time_range", DEFAULT_TIME_RANGE)
        return int(start), int(end)

    @time_range.setter
    def time_range(self, value) -> None:
        start, end = value
        self.data["time_range"] = [int(start), int(end)]

    ### Geometry and motion

    @property
    def rings(self) -> list[list[list[float]]]:
        """The outline rings, each a list of [latitude, longitude] pairs.

        For a feature this is the list inside the document, so writing to it
        changes the document. A group has no geometry at all and a topology
        none of its own, since its geometry is resolved from the sections it
        names; both answer with an empty list of their own.
        """
        return self.data.setdefault("rings", []) if not self.is_group else []

    @property
    def sections(self) -> list[dict]:
        return self.data.get("sections", [])

    @property
    def keyframes(self) -> list[Keyframe]:
        return [Keyframe(entry) for entry in self.data.get("keyframes", [])]

    @property
    def couplings(self) -> list[dict]:
        """The spans over which the feature rides on another, since 0.12.0.

        Each is `from`, the older age, `to`, the younger one, and the `parent`
        uuid. Inside a span the keyframes are relative to the parent, so a
        keyframe written there by `set_keyframe` is too. A group has none.

        Since 0.15.0 a span may also carry `parent_b`, a second uuid, which a
        ridge left by the Split tool rides on. Its frame is then midway
        between the two.
        """
        return self.data.get("couplings", []) if not self.is_group else []

    def set_keyframe(self, time: float, rotation) -> Keyframe:
        """Write the keyframe at this time, replacing one already there.

        Only a feature moves: a group is organization and carries no motion,
        since 0.8.0.
        """
        if self.is_group:
            raise ValueError(f"{self.title!r} is a group and does not move")
        x, y, z = rotation
        entry = {"time": float(time), "rotation": [float(x), float(y), float(z)]}
        keyframes = self.data.setdefault("keyframes", [])
        for index, existing in enumerate(keyframes):
            if float(existing.get("time", 0.0)) == float(time):
                keyframes[index] = entry
                break
        else:
            keyframes.append(entry)
            keyframes.sort(key=lambda k: float(k.get("time", 0.0)))
        return Keyframe(entry)

    def delete_keyframe(self, time: float) -> bool:
        """Drop the keyframe at this time. False when there is none."""
        keyframes = self.data.get("keyframes", [])
        for index, existing in enumerate(keyframes):
            if float(existing.get("time", 0.0)) == float(time):
                del keyframes[index]
                return True
        return False

    ### The tree below it

    @property
    def children(self) -> list[Feature]:
        return [Feature(child) for child in self.data.get("children", [])]

    def walk(self) -> Iterator[Feature]:
        """This node and every node under it, parents before children."""
        yield self
        for child in self.children:
            yield from child.walk()

    def add(self, child: Feature) -> Feature:
        """Append a feature or a group. Only a group may hold children."""
        if not self.is_group:
            raise TypeError(f"{self.title!r} is a feature, not a group")
        self.data.setdefault("children", []).append(child.data)
        return child

    def remove(self, child: Feature) -> bool:
        """Drop a direct child. False when it is not one."""
        children = self.data.get("children", [])
        for index, entry in enumerate(children):
            if entry is child.data:
                del children[index]
                return True
        return False

    ### Building new nodes

    @staticmethod
    def new_feature(title: str, rings=(), geometry_kind: str = DEFAULT_GEOMETRY_KIND,
                    feature_type: str = DEFAULT_FEATURE_TYPE, uuid: str = "") -> Feature:
        return Feature({
            "type": "Feature",
            "uuid": uuid,
            "title": title,
            "enabled": True,
            "is_group": False,
            "keyframes": [],
            "couplings": [],
            "feature_type": feature_type,
            "geometry_kind": geometry_kind,
            "color": list(DEFAULT_COLOR),
            "rings": [[[float(lat), float(lon)] for lat, lon in ring] for ring in rings],
            "time_range": list(DEFAULT_TIME_RANGE),
        })

    @staticmethod
    def new_group(title: str, uuid: str = "") -> Feature:
        return Feature({
            "type": "Group",
            "uuid": uuid,
            "title": title,
            "enabled": True,
            "is_group": True,
            "children": [],
        })


class Document:
    """A `.middle-earth` file: the feature tree and the view settings."""

    def __init__(self, data: dict) -> None:
        self.data = data
        self.path: Path | None = None

    def __repr__(self) -> str:
        where = self.path.name if self.path is not None else "in memory"
        return f"Document({where}, version {self.version}, {len(self.features)} features)"

    ### Files

    @classmethod
    def loads(cls, text: str) -> Document:
        data = json.loads(text)
        if not isinstance(data, dict):
            raise ValueError("not a Middle Earth file: the root is not an object")
        if data.get("application") != APPLICATION:
            raise ValueError("not a Middle Earth file")
        return cls(data)

    @classmethod
    def load(cls, path) -> Document:
        document = cls.loads(Path(path).read_text(encoding="utf-8"))
        document.path = Path(path)
        return document

    @classmethod
    def empty(cls, version: str) -> Document:
        return cls({
            "application": APPLICATION,
            "version": version,
            "features": Feature.new_group("Planet").data,
        })

    def dumps(self) -> str:
        return dumps(self.data)

    def save(self, path=None) -> Path:
        target = Path(path) if path is not None else self.path
        if target is None:
            raise ValueError("no path to save to")
        target.write_text(self.dumps(), encoding="utf-8", newline="")
        self.path = target
        return target

    ### What is in it

    @property
    def version(self) -> str:
        return str(self.data.get("version", ""))

    @property
    def view(self) -> dict:
        return self.data.setdefault("view", {})

    @property
    def root(self) -> Feature:
        return Feature(self.data.setdefault("features", Feature.new_group("Planet").data))

    @property
    def features(self) -> list[Feature]:
        """Every feature in the tree, groups left out, parents first."""
        return [node for node in self.root.walk() if not node.is_group]

    @property
    def groups(self) -> list[Feature]:
        return [node for node in self.root.walk() if node.is_group]

    def find(self, uuid: str) -> Feature | None:
        for node in self.root.walk():
            if node.uuid == uuid:
                return node
        return None

    def named(self, title: str) -> Feature | None:
        for node in self.root.walk():
            if node.title == title:
                return node
        return None
