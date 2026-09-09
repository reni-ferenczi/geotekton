"""Reading a GPlates project file: the archive format and where its files went."""

import pytest

from middle_earth.gproj import SIGNATURE, Project, ProjectError, read_project

from conftest import gplates_projects


### An archive written here, so the reader is exercised without GPlates installed


def _varint(value: int) -> bytes:
    out = bytearray()
    while value >= 0x80:
        out.append((value & 0x7F) | 0x80)
        value >>= 7
    out.append(value)
    return bytes(out)


def _string(text: str) -> bytes:
    encoded = text.encode("utf-8")
    return _varint(len(encoded)) + encoded


class _Archive:
    """The smallest archive holding a project's file list, built the way
    `ScribeBinaryArchiveWriter.cc` writes one."""

    #: The reader expects the session metadata in object id 1, so that id is
    #: reserved and filled in by `root()` once its children have been built.
    ROOT = 1

    def __init__(self) -> None:
        self.tags: list[str] = []
        self.strings: list[str] = []
        self.objects: dict[int, bytes] = {self.ROOT: b""}

    def _tag(self, name: str) -> int:
        if name not in self.tags:
            self.tags.append(name)
        return self.tags.index(name)

    def _add(self, body: bytes) -> int:
        object_id = len(self.objects) + 1
        self.objects[object_id] = body
        return object_id

    def root(self, children: dict[str, list[int]]) -> None:
        self.objects[self.ROOT] = self.objects.pop(self.composite(children))

    def unsigned(self, value: int) -> int:
        return self._add(_varint(1) + _varint(value))

    def string(self, text: str) -> int:
        if text not in self.strings:
            self.strings.append(text)
        return self._add(_varint(4) + _varint(self.strings.index(text)))

    def composite(self, children: dict[str, list[int]]) -> int:
        body = _varint(5) + _varint(len(children))
        for tag, ids in children.items():
            body += _varint(self._tag(tag)) + _varint(0) + _varint(len(ids))
            body += b"".join(_varint(child) for child in ids)
        return self._add(body)

    def text(self, value: str) -> int:
        return self.composite({"utf8": [self.string(value)]})

    def sequence(self, items: list[int]) -> int:
        return self.composite({"size": [self.unsigned(len(items))], "item": items})

    def file_path(self, path: str) -> int:
        return self.sequence([self.text(part) for part in path.split("/")])

    def to_bytes(self) -> bytes:
        out = bytearray(SIGNATURE)
        out += _varint(0) + _varint(1)
        out += _varint(len(self.tags)) + b"".join(_string(tag) for tag in self.tags)
        out += _varint(len(self.strings)) + b"".join(_string(text) for text in self.strings)
        out += _varint(len(self.objects)) + _varint(1)
        out += b"".join(self.objects[key] for key in sorted(self.objects))
        out += _varint(0)
        return bytes(out)


def _project_bytes(saved_as: str, files: list[str]) -> bytes:
    """An archive naming a project's own path and the files it loaded."""
    archive = _Archive()
    paths = [archive.file_path(path) for path in files]
    archive.root({
        "original_project_filename": [archive.file_path(saved_as)],
        "loaded_files": [archive.sequence(paths)],
    })
    return archive.to_bytes()


def _write_project(directory, saved_as: str, files: list[str]):
    path = directory / "session.gproj"
    path.write_bytes(_project_bytes(saved_as, files))
    return path


### The format


def test_a_project_lists_the_files_it_loaded(tmp_path):
    path = _write_project(tmp_path, "/home/a/session.gproj",
                          ["/home/a/coastlines.gpml", "/home/a/rotations.rot"])
    project = read_project(path)
    assert project.saved_as == "/home/a/session.gproj"
    assert project.recorded_files == ["/home/a/coastlines.gpml", "/home/a/rotations.rot"]


def test_a_project_with_no_files_reads_as_empty(tmp_path):
    project = read_project(_write_project(tmp_path, "/home/a/session.gproj", []))
    assert project.recorded_files == []


def test_a_file_that_is_not_an_archive_is_refused(tmp_path):
    path = tmp_path / "not.gproj"
    path.write_bytes(b"this is not a GPlates project at all")
    with pytest.raises(ProjectError, match="not a GPlates project file"):
        read_project(path)


def test_a_truncated_archive_is_refused(tmp_path):
    whole = _project_bytes("/home/a/session.gproj", ["/home/a/coastlines.gpml"])
    path = tmp_path / "cut.gproj"
    path.write_bytes(whole[:len(whole) // 2])
    with pytest.raises(ProjectError):
        read_project(path)


def test_an_archive_without_a_file_list_is_refused(tmp_path):
    archive = _Archive()
    archive.root({"time": [archive.text("Tuesday")]})
    path = tmp_path / "meta.gproj"
    path.write_bytes(archive.to_bytes())
    with pytest.raises(ProjectError, match="original_project_filename"):
        read_project(path)


### Finding the files again


def test_a_file_is_found_where_the_project_says(tmp_path):
    data = tmp_path / "coastlines.gpml"
    data.write_text("", encoding="utf-8")
    project = Project(tmp_path / "session.gproj", str(tmp_path / "session.gproj"), [str(data)])
    assert project.files() == [data]


def test_a_moved_bundle_is_followed_from_the_project_file(tmp_path):
    """The whole bundle was copied, so a file sits where it did relative to the project."""
    (tmp_path / "Session").mkdir()
    (tmp_path / "Data").mkdir()
    data = tmp_path / "Data" / "coastlines.gpml"
    data.write_text("", encoding="utf-8")
    project = Project(
        tmp_path / "Session" / "session.gproj",
        "/elsewhere/Session/session.gproj",
        ["/elsewhere/Data/coastlines.gpml"],
    )
    assert project.files() == [data]


def test_a_file_that_is_nowhere_comes_back_as_it_was_recorded(tmp_path):
    project = Project(tmp_path / "session.gproj", "/elsewhere/session.gproj",
                      ["/elsewhere/gone.gpml"])
    found = project.files()
    assert len(found) == 1 and not found[0].exists()
    assert found[0].name == "gone.gpml"


### The projects GPlates itself ships


@pytest.mark.parametrize("path", gplates_projects(), ids=lambda p: p.name)
def test_a_gplates_project_reads_and_its_files_are_found(path):
    """A real project, saved on another machine and shipped inside the install."""
    project = read_project(path)
    assert project.saved_as.endswith(".gproj")
    assert project.recorded_files
    missing = [found for found in project.files() if not found.exists()]
    assert missing == []
