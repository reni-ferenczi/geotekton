"""The file model: reading, writing and editing a document without the application."""

import json

import pytest

from middle_earth.document import CURRENT_VERSION, Document, Feature

from conftest import ROOT, SAMPLES, sample_paths


@pytest.mark.parametrize("path", sample_paths(), ids=lambda p: p.name)
def test_sample_round_trips_byte_for_byte(path, tmp_path):
    """Every sample survives a load and a save unchanged, whatever version it is at."""
    document = Document.load(path)
    written = document.save(tmp_path / path.name)
    assert written.read_bytes() == path.read_bytes()


def test_a_file_that_is_not_a_document_is_refused(tmp_path):
    other = tmp_path / "other.json"
    other.write_text(json.dumps({"application": "something else"}), encoding="utf-8")
    with pytest.raises(ValueError):
        Document.load(other)


def test_the_tree_reads_as_features_and_groups():
    document = Document.load(SAMPLES / "motion.middle-earth")
    assert document.version == "0.7.0"
    assert [feature.title for feature in document.features] == ["Drifting Craton"]
    assert [group.title for group in document.groups] == ["Planet", "Plates"]


def test_a_feature_reads_its_geometry_and_motion():
    document = Document.load(SAMPLES / "motion.middle-earth")
    craton = document.named("Drifting Craton")
    assert craton.geometry_kind == "polygon"
    assert craton.feature_type == "craton"
    assert craton.time_range == (0, 2000)
    assert craton.rings[0][0] == [-12.0, -12.0]
    assert [key.time for key in craton.keyframes] == [0.0, 600.0, 1400.0]
    assert craton.keyframes[1].rotation == (-30.0, 10.0, 0.0)


def test_find_answers_by_uuid():
    document = Document.load(SAMPLES / "motion.middle-earth")
    craton = document.named("Drifting Craton")
    assert document.find(craton.uuid).title == "Drifting Craton"
    assert document.find("no-such-uuid") is None


def test_a_keyframe_is_written_in_time_order_and_replaced_in_place():
    craton = Feature.new_feature("Craton")
    craton.set_keyframe(600.0, (10.0, 0.0, 0.0))
    craton.set_keyframe(0.0, (0.0, 0.0, 0.0))
    assert [key.time for key in craton.keyframes] == [0.0, 600.0]

    craton.set_keyframe(600.0, (20.0, 0.0, 0.0))
    assert [key.time for key in craton.keyframes] == [0.0, 600.0]
    assert craton.keyframes[1].rotation == (20.0, 0.0, 0.0)

    assert craton.delete_keyframe(600.0)
    assert not craton.delete_keyframe(600.0)
    assert [key.time for key in craton.keyframes] == [0.0]


def test_a_group_takes_children_and_a_feature_does_not():
    document = Document.empty("0.7.0")
    plates = document.root.add(Feature.new_group("Plates"))
    craton = plates.add(Feature.new_feature("Craton", rings=[[(0, 0), (0, 10), (10, 0)]]))
    assert [feature.title for feature in document.features] == ["Craton"]

    with pytest.raises(TypeError):
        craton.add(Feature.new_feature("Nested"))

    assert plates.remove(craton)
    assert document.features == []


def test_editing_writes_through_to_what_is_saved(tmp_path):
    document = Document.load(SAMPLES / "motion.middle-earth")
    craton = document.named("Drifting Craton")
    craton.title = "Renamed"
    craton.enabled = False
    craton.color = (0.0, 0.5, 1.0, 1.0)
    craton.time_range = (100, 900)
    craton.rings[0][0] = [-11.0, -12.0]

    path = document.save(tmp_path / "edited.middle-earth")
    reloaded = Document.load(path)
    changed = reloaded.named("Renamed")
    assert not changed.enabled
    assert changed.color == (0.0, 0.5, 1.0, 1.0)
    assert changed.time_range == (100, 900)
    assert changed.rings[0][0] == [-11.0, -12.0]


def test_saving_without_a_path_is_refused():
    with pytest.raises(ValueError):
        Document.empty("0.7.0").save()


def test_what_is_written_is_what_godot_writes(tmp_path):
    """The application's own writer is JSON with a tab indent and sorted keys."""
    document = Document.load(SAMPLES / "craton.middle-earth")
    text = document.dumps()
    assert text == json.dumps(json.loads(text), indent="\t", sort_keys=True)
    assert not text.endswith("\n")


def test_the_version_this_package_writes_is_the_application_version():
    """A document the package builds has to say what the application says."""
    settings = (ROOT / "project.godot").read_text(encoding="utf-8")
    assert 'config/version="%s"' % CURRENT_VERSION in settings


def test_a_feature_reads_the_spans_it_rides_on():
    feature = Feature({"type": "Feature", "is_group": False, "couplings": [
        {"from": 500.0, "to": 200.0, "parent": "6b0d6b1e"}]})
    assert feature.couplings == [{"from": 500.0, "to": 200.0, "parent": "6b0d6b1e"}]
    assert Feature.new_feature("Rider").couplings == []
    assert Feature.new_group("Plates").couplings == []
