"""The scripting API against a fake application.

The fake answers the same requests the application answers, over the same
dictionaries, so what is checked here is the API's half of the conversation:
which request each call sends and what it makes of the reply.
"""

import pytest

from middle_earth.api import App, AppError
from middle_earth.document import Document, Feature


class FakeApplication:
    """Enough of the application to hold a document and edit it."""

    def __init__(self) -> None:
        self.document = Document.empty("0.7.0")
        self.time = 0.0
        self.playing = False
        self.selection = ""
        self.saved_to = ""
        self.requests: list[dict] = []
        self._counter = 0

    def __call__(self, request: dict) -> dict:
        self.requests.append(request)
        handler = getattr(self, "do_" + request["cmd"], None)
        if handler is None:
            return {"ok": False, "error": "unknown command: %s" % request["cmd"]}
        return {"ok": True, **(handler(request) or {})}

    def _uuid(self) -> str:
        self._counter += 1
        return "uuid-%d" % self._counter

    def _node(self, request: dict) -> Feature:
        node = self.document.find(request["uuid"])
        if node is None:
            raise AssertionError("no feature %s" % request["uuid"])
        return node

    def _parent(self, request: dict) -> Feature:
        return self.document.find(request["parent"]) if request.get("parent") else self.document.root

    ### The commands

    def do_document(self, _request):
        return {"document": self.document.data, "name": "Untitled"}

    def do_time(self, _request):
        return {"time": self.time, "playing": self.playing}

    def do_set_time(self, request):
        self.time = request["time"]

    def do_play(self, _request):
        self.playing = True

    def do_pause(self, _request):
        self.playing = False

    def do_selection(self, _request):
        return {"uuid": self.selection}

    def do_select(self, request):
        self.selection = request["uuid"]

    def do_add_feature(self, request):
        uuid = self._uuid()
        feature = Feature.new_feature(
            request["title"], rings=request["rings"],
            geometry_kind=request["geometry_kind"], uuid=uuid)
        if request["feature_type"]:
            feature.feature_type = request["feature_type"]
        self._parent(request).add(feature)
        return {"uuid": uuid}

    def do_add_group(self, request):
        uuid = self._uuid()
        self._parent(request).add(Feature.new_group(request["title"], uuid=uuid))
        return {"uuid": uuid}

    def do_edit_feature(self, request):
        node = self._node(request)
        for name, value in request["fields"].items():
            if name == "rings":
                node.data["rings"] = value
            else:
                setattr(node, name, value)

    def do_delete_feature(self, request):
        node = self._node(request)
        for group in self.document.groups:
            if group.remove(node):
                return None
        raise AssertionError("%s has no parent" % node.uuid)

    def do_set_keyframe(self, request):
        self._node(request).set_keyframe(request["time"], request["rotation"])

    def do_delete_keyframe(self, request):
        if not self._node(request).delete_keyframe(request["time"]):
            raise AssertionError("no keyframe at %s" % request["time"])

    def do_save(self, request):
        self.saved_to = request["path"]


@pytest.fixture
def fake():
    return FakeApplication()


@pytest.fixture
def app(fake):
    return App(fake)


def test_adding_a_feature_answers_with_its_uuid(app, fake):
    uuid = app.add_feature("Craton", rings=[[(0, 0), (0, 10), (10, 0)]], feature_type="craton")
    assert uuid == "uuid-1"
    feature = fake.document.find(uuid)
    assert feature.title == "Craton"
    assert feature.feature_type == "craton"
    assert feature.rings == [[[0.0, 0.0], [0.0, 10.0], [10.0, 0.0]]]


def test_a_feature_can_be_added_to_a_group(app, fake):
    group = app.add_group("Plates")
    uuid = app.add_feature("Craton", parent=group)
    assert [child.uuid for child in fake.document.find(group).children] == [uuid]


def test_editing_changes_only_the_fields_it_names(app, fake):
    uuid = app.add_feature("Craton")
    app.edit_feature(uuid, title="Renamed", enabled=False)
    feature = fake.document.find(uuid)
    assert feature.title == "Renamed"
    assert not feature.enabled
    assert feature.feature_type == "unclassified"


def test_editing_a_field_a_feature_does_not_have_is_refused(app, fake):
    uuid = app.add_feature("Craton")
    with pytest.raises(AppError):
        app.edit_feature(uuid, nonsense=1)
    assert [request["cmd"] for request in fake.requests] == ["add_feature"]


def test_moving_a_feature_writes_and_removes_keyframes(app, fake):
    uuid = app.add_feature("Craton")
    app.set_keyframe(uuid, 0.0, (0, 0, 0))
    app.set_keyframe(uuid, 600.0, (-30, 10, 0))
    feature = fake.document.find(uuid)
    assert [key.time for key in feature.keyframes] == [0.0, 600.0]
    assert feature.keyframes[1].rotation == (-30.0, 10.0, 0.0)

    app.delete_keyframe(uuid, 0.0)
    assert [key.time for key in feature.keyframes] == [600.0]


def test_deleting_a_feature_takes_it_out_of_the_tree(app, fake):
    uuid = app.add_feature("Craton")
    app.delete_feature(uuid)
    assert fake.document.features == []


def test_the_document_is_read_back_as_a_document(app):
    app.add_feature("Craton")
    document = app.document
    assert isinstance(document, Document)
    assert [feature.title for feature in document.features] == ["Craton"]
    assert app.named("Craton") is not None
    assert app.find("no-such-uuid") is None


def test_time_reads_and_writes(app, fake):
    app.time = 600.0
    assert fake.time == 600.0
    assert app.time == 600.0
    app.play()
    assert app.playing
    app.pause()
    assert not app.playing


def test_selection_reads_and_writes(app, fake):
    uuid = app.add_feature("Craton")
    app.select(uuid)
    assert fake.selection == uuid
    assert app.selected == uuid


def test_saving_passes_the_path_through(app, fake):
    app.save("C:/tmp/out.middle-earth")
    assert fake.saved_to == "C:/tmp/out.middle-earth"


def test_a_refusal_from_the_application_is_raised(app):
    with pytest.raises(AppError, match="unknown command: undo"):
        app.undo()
