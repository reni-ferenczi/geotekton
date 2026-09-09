"""Reading the file list out of a GPlates project (`.gproj`) file.

A project file is a GPlates Scribe binary archive. It holds no geometry and no
rotations: it names the feature collection files that were loaded when the
project was saved, along with everything else about the session. This module
reads far less than GPlates does — the first transcription in the archive, which
is the session metadata, and out of it the list of loaded files.

The format is the one `src/scribe/ScribeBinaryArchiveWriter.cc` writes in the
GPlates sources. An archive starts with a signature and two version numbers,
then each transcription is a table of object tag names, a table of unique
strings, and the objects themselves in groups of contiguous ids. Integers are
protobuf style varints and strings are a length followed by raw bytes.

An object is a number, a string, or a composite: a map from a key, which is a
tag name and a version, to a list of child object ids. A path through the graph
is written as a tag name and, for the sequences GPlates uses, the reserved names
`size` and `item`. Object id 1 is the root.

See Docs/Import.md.
"""

from __future__ import annotations

import os
from pathlib import Path, PurePosixPath

SIGNATURE = b"GPlatesScribeBinaryArchive"

# TranscriptionScribeContext::ROOT_OBJECT_ID.
ROOT_OBJECT_ID = 1

# The type codes in ScribeArchiveCommon.h. Only three of them can be reached by
# the tags read here; the rest are still decoded, because an object has to be
# read past to reach the next one.
_SIGNED, _UNSIGNED, _FLOAT, _DOUBLE, _STRING, _COMPOSITE = range(6)

# ObjectTag's sequence protocol: the names an array's length and its items are
# written under.
_SIZE = "size"
_ITEM = "item"

# TranscribeQt.cc writes a QString as a composite holding its UTF-8 bytes.
_UTF8 = "utf8"


class ProjectError(Exception):
    """The file is not a project file, or not one this reader understands."""


class Project:
    """What a `.gproj` file says about where its data files are."""

    def __init__(self, path: Path, saved_as: str, recorded_files: list[str]) -> None:
        self.path = path
        # The project's own path as it was when it was saved, which is what the
        # recorded file paths sit relative to.
        self.saved_as = saved_as
        # The loaded feature collection paths, as the saving machine wrote them.
        self.recorded_files = recorded_files

    def __repr__(self) -> str:
        return f"Project({self.path.name!r}, {len(self.recorded_files)} files)"

    def files(self) -> list[Path]:
        """The data files, moved to where the project file is now.

        A project carries absolute paths from the machine it was saved on, so a
        bundle that was copied elsewhere — which is how GPlates ships its own
        sample projects — names files that are not there any more. Each one is
        looked for where it says first, then in the same place relative to the
        project file. One that is still missing comes back as it was recorded,
        so the caller can name the file it could not find.
        """
        saved_dir = PurePosixPath(self.saved_as).parent
        here = self.path.parent
        found = []
        for recorded in self.recorded_files:
            candidate = Path(recorded)
            if not candidate.exists():
                # walk_up lets a file that sits beside the project's directory
                # rather than under it come back as `../elsewhere/file.gpml`,
                # which is where most of a GPlates data bundle is.
                relative = PurePosixPath(recorded).relative_to(saved_dir, walk_up=True)
                moved = Path(os.path.normpath(here / relative))
                if moved.exists():
                    candidate = moved
            found.append(candidate)
        return found


def read_project(path) -> Project:
    """The project file at this path."""
    path = Path(path)
    reader = _Reader(path.read_bytes())
    if reader.take(len(SIGNATURE)) != SIGNATURE:
        raise ProjectError(f"{path.name} is not a GPlates project file")
    reader.unsigned()  # Archive format version, still 0 in GPlates 2.5.
    reader.unsigned()  # Scribe version.

    metadata = _Transcription(reader)
    saved_as = metadata.file_path(metadata.child(ROOT_OBJECT_ID, "original_project_filename"))
    loaded = metadata.child(ROOT_OBJECT_ID, "loaded_files")
    return Project(path, saved_as, metadata.file_paths(loaded))


class _Reader:
    """The archive's primitives, read out of the bytes in order."""

    def __init__(self, data: bytes) -> None:
        self.data = data
        self.at = 0

    def take(self, count: int) -> bytes:
        chunk = self.data[self.at:self.at + count]
        if len(chunk) != count:
            raise ProjectError("the project file ends in the middle of a value")
        self.at += count
        return chunk

    def unsigned(self) -> int:
        value = 0
        for shift in range(0, 35, 7):
            byte = self.take(1)[0]
            value |= (byte & 0x7F) << shift
            if not byte & 0x80:
                return value
        raise ProjectError("an integer in the project file does not end")

    def signed(self) -> int:
        # Zig-zag: 0, -1, 1, -2, 2 ... so a small negative stays a short varint.
        value = self.unsigned()
        return value // 2 if value % 2 == 0 else -(value + 1) // 2

    def string(self) -> str:
        return self.take(self.unsigned()).decode("utf-8", errors="replace")


class _Transcription:
    """One transcription: its tag names, its strings and its objects."""

    def __init__(self, reader: _Reader) -> None:
        self.tags = [reader.string() for _ in range(reader.unsigned())]
        self.strings = [reader.string() for _ in range(reader.unsigned())]
        self.objects: dict[int, object] = {}
        while True:
            count = reader.unsigned()
            if count == 0:
                break
            object_id = reader.unsigned()
            for _ in range(count):
                self.objects[object_id] = self._read_object(reader)
                object_id += 1

    def _read_object(self, reader: _Reader):
        code = reader.unsigned()
        if code == _SIGNED:
            return reader.signed()
        if code == _UNSIGNED:
            return reader.unsigned()
        if code == _FLOAT:
            return reader.take(4)
        if code == _DOUBLE:
            return reader.take(8)
        if code == _STRING:
            return self.strings[reader.unsigned()]
        if code == _COMPOSITE:
            keys: dict[tuple[int, int], list[int]] = {}
            for _ in range(reader.unsigned()):
                key = (reader.unsigned(), reader.unsigned())
                keys[key] = [reader.unsigned() for _ in range(reader.unsigned())]
            return keys
        raise ProjectError(f"unknown object type {code} in the project file")

    ### Walking the object graph

    def child(self, object_id: int, tag: str, index: int = 0) -> int:
        """The id of a composite's child under that tag name."""
        keys = self.objects.get(object_id)
        if not isinstance(keys, dict):
            raise ProjectError(f"the project file has no {tag!r} to read")
        # Version 0 is the only version anything read here is written at, and a
        # tag name that was never written has no id in the table at all.
        key = (self.tags.index(tag), 0) if tag in self.tags else None
        children = keys.get(key, [])
        if index >= len(children):
            raise ProjectError(f"the project file has no {tag!r} to read")
        return children[index]

    def count(self, object_id: int) -> int:
        """How long the sequence this composite holds is."""
        size = self.objects[self.child(object_id, _SIZE)]
        if not isinstance(size, int):
            raise ProjectError("a sequence in the project file has no length")
        return size

    def text(self, object_id: int) -> str:
        """A QString, which is a composite holding its UTF-8 bytes."""
        value = self.objects[self.child(object_id, _UTF8)]
        if not isinstance(value, str):
            raise ProjectError("a string in the project file is not a string")
        return value

    ### The file paths

    def file_path(self, object_id: int) -> str:
        """A TranscribeUtils::FilePath, which is a path split on its slashes."""
        parts = [self.text(self.child(object_id, _ITEM, i)) for i in range(self.count(object_id))]
        return "/".join(parts)

    def file_paths(self, object_id: int) -> list[str]:
        """A sequence of them, which is how a project holds its loaded files."""
        return [self.file_path(self.child(object_id, _ITEM, index))
                for index in range(self.count(object_id))]
