"""Converting a GPlates reconstruction into a Geotekton document."""

import logging
import math
import re

import pygplates
import pytest

from geotekt.gplates import (KIND_TYPES, MAX_PRIMITIVES, MAX_TIME,
                                  decompose_rotation_degrees, import_files, import_project)

from conftest import ROOT, geodata
from test_gproj import _project_bytes

COASTLINES = geodata("FeatureCollections", "Coastlines",
                     "Global_EarthByte_GPlates_PresentDay_Coastlines.gpmlz")
ROTATIONS = geodata("FeatureCollections", "Rotations",
                    "Zahirovic_etal_2022_OptimisedMantleRef_and_NNRMantleRef.rot")

needs_gplates = pytest.mark.skipif(COASTLINES is None or ROTATIONS is None,
                                   reason="no GPlates install to read the sample data from")


### Data made here, so most of what the converter does is checked anywhere


def write_features(path, features):
    pygplates.FeatureCollection(features).write(str(path))
    return path


def a_feature(feature_type="gpml:Coastline", geometry=None, plate=101,
              name="Somewhere", valid=(600, 0)):
    feature = pygplates.Feature(pygplates.FeatureType.create_from_qualified_string(feature_type))
    if geometry is not None:
        feature.set_geometry(geometry)
    feature.set_reconstruction_plate_id(plate)
    feature.set_valid_time(*valid)
    feature.set_name(name)
    return feature


def a_polygon(offset=0.0):
    return pygplates.PolygonOnSphere([(0, offset), (0, offset + 10), (10, offset + 10)])


def write_rotations(path, turns={101: 30.0}, pole=(0, 0), oldest=100.0):
    """A rotation file where each plate turns to its angle by the oldest time."""
    features = []
    for plate, degrees in turns.items():
        samples = [
            pygplates.GpmlTimeSample(
                pygplates.GpmlFiniteRotation(pygplates.FiniteRotation(pole, 0.0)), 0.0),
            pygplates.GpmlTimeSample(
                pygplates.GpmlFiniteRotation(
                    pygplates.FiniteRotation(pole, math.radians(degrees))), oldest),
        ]
        features.append(pygplates.Feature.create_total_reconstruction_sequence(
            0, plate, pygplates.GpmlIrregularSampling(samples)))
    return write_features(path, features)


### The tree it builds


def test_each_plate_becomes_a_group_holding_its_features(tmp_path):
    features = write_features(tmp_path / "features.gpml", [
        a_feature(geometry=a_polygon(), plate=101, name="North"),
        a_feature(geometry=a_polygon(20), plate=101, name="South"),
        a_feature(geometry=a_polygon(40), plate=201, name="East"),
    ])
    document = import_files([features])
    assert [group.title for group in document.root.children] == ["Plate 101", "Plate 201"]
    assert [child.title for child in document.root.children[0].children] == ["North", "South"]
    assert len(document.features) == 3


def test_a_feature_without_geometry_is_left_out_and_said_so(tmp_path, caplog):
    features = write_features(tmp_path / "features.gpml", [
        a_feature(geometry=a_polygon(), name="Drawn"),
        a_feature(geometry=None, name="Nothing there"),
    ])
    with caplog.at_level(logging.DEBUG, logger="geotekt.gplates"):
        document = import_files([features])
    assert [feature.title for feature in document.features] == ["Drawn"]
    assert "Nothing there has no geometry of its own" in caplog.text


def test_a_file_that_cannot_be_read_is_reported_and_the_rest_imported(tmp_path, caplog):
    features = write_features(tmp_path / "features.gpml", [a_feature(geometry=a_polygon())])
    rubbish = tmp_path / "notes.txt"
    rubbish.write_text("not a feature collection", encoding="utf-8")
    with caplog.at_level(logging.WARNING, logger="geotekt.gplates"):
        document = import_files([rubbish, features])
    assert len(document.features) == 1
    assert "notes.txt could not be read" in caplog.text


def test_the_geometry_kinds_come_across(tmp_path):
    features = write_features(tmp_path / "features.gpml", [
        a_feature(geometry=a_polygon(), name="Area"),
        a_feature(geometry=pygplates.PolylineOnSphere([(0, 0), (10, 10)]), name="Line"),
        a_feature(geometry=pygplates.MultiPointOnSphere([(0, 0), (5, 5)]), name="Dots"),
        a_feature(geometry=pygplates.PointOnSphere((1, 2)), name="Dot"),
    ])
    document = import_files([features])
    assert {feature.title: feature.geometry_kind for feature in document.features} == {
        "Area": "polygon", "Line": "polyline", "Dots": "multipoint", "Dot": "multipoint"}


def test_a_polygon_keeps_its_vertices(tmp_path):
    features = write_features(tmp_path / "features.gpml", [a_feature(geometry=a_polygon())])
    ring = import_files([features]).features[0].rings[0]
    assert len(ring) == 3
    assert ring[0] == pytest.approx([0.0, 0.0])
    assert ring[2] == pytest.approx([10.0, 10.0])


def test_an_interior_ring_becomes_an_outline_of_its_own(tmp_path):
    polygon = pygplates.PolygonOnSphere([(0, 0), (0, 30), (30, 30), (30, 0)])
    hole = pygplates.PolygonOnSphere([(10, 10), (10, 20), (20, 20)])
    feature = a_feature(geometry=None)
    feature.set_geometry(pygplates.PolygonOnSphere(polygon, [hole]))
    features = write_features(tmp_path / "features.gpml", [feature])
    assert len(import_files([features]).features[0].rings) == 2


### What a feature is called and what it is


def test_the_gpgim_types_map_onto_the_five_by_geometry(tmp_path):
    """Whatever GPlates calls a feature, its Geotekton type is its geometry's."""
    line = pygplates.PolylineOnSphere([(0, 0), (10, 10)])
    points = pygplates.MultiPointOnSphere([(0, 0), (10, 10)])
    features = write_features(tmp_path / "features.gpml", [
        a_feature("gpml:Coastline", a_polygon(), name="Shore"),
        a_feature("gpml:Craton", a_polygon(20), name="Shield"),
        a_feature("gpml:Basin", a_polygon(40), name="Deep"),
        a_feature("gpml:Coastline", line, name="Shoreline"),
        a_feature("gpml:MidOceanRidge", line, name="Ridge"),
        a_feature("gpml:MidOceanRidge", a_polygon(60), name="Ridge Area"),
        a_feature("gpml:UnclassifiedFeature", points, name="Hot Spots"),
    ])
    document = import_files([features])
    assert {feature.title: feature.feature_type for feature in document.features} == {
        "Shore": "polygon", "Shield": "polygon", "Deep": "polygon", "Shoreline": "line",
        "Ridge": "line", "Ridge Area": "polygon", "Hot Spots": "points"}


### What this module copies from the application

# Three values are written down in GDScript and again here, because the
# converter has to know them and cannot ask a running application. These read
# the GDScript and hold the copies to it, so a change on that side fails here
# rather than showing up as a strange import.


def gdscript(*parts: str) -> str:
    return (ROOT.joinpath(*parts)).read_text(encoding="utf-8")


def test_the_type_of_each_kind_is_the_application_s():
    """Every type the import gives is in the catalog and holds the kind it is given for."""
    source = gdscript("Logic", "feature_type.gd")
    catalog = {identifier: set(re.findall(r'"(\w+)"', kinds))
               for identifier, kinds in re.findall(r'"(\w+)": \{[^}]*?"kinds": (\[[^]]*\])', source)}
    for kind, identifier in KIND_TYPES.items():
        assert identifier in catalog, f"{identifier} is not a type the application has"
        assert kind in catalog[identifier], f"{identifier} does not hold a {kind}"
        assert f'"{kind}": "{identifier}"' in source, f"the application gives a {kind} another type"


def test_the_oldest_age_is_the_one_the_application_takes():
    assert "const MAX_TIME := %d.0" % MAX_TIME in gdscript("Logic", "document.gd")


def test_the_primitive_limit_is_the_one_the_planet_draws():
    assert ("const MAX_PRIMITIVES := %d" % MAX_PRIMITIVES
            in gdscript("Scenes", "Planet", "planet.gd"))


def test_an_unnamed_feature_is_called_after_its_type_and_plate(tmp_path):
    features = write_features(tmp_path / "features.gpml",
                              [a_feature("gpml:Isochron", a_polygon(), plate=802, name="")])
    assert import_files([features]).features[0].title == "Isochron 802"


def test_the_features_of_a_plate_share_a_colour_and_two_plates_do_not(tmp_path):
    features = write_features(tmp_path / "features.gpml", [
        a_feature(geometry=a_polygon(), plate=101, name="North"),
        a_feature(geometry=a_polygon(20), plate=101, name="South"),
        a_feature(geometry=a_polygon(40), plate=201, name="East"),
    ])
    colors = {feature.title: feature.color for feature in import_files([features]).features}
    assert colors["North"] == colors["South"] != colors["East"]


### Being there at all


@pytest.mark.parametrize("valid, expected", [
    ((600, 0), (0, 600)),
    ((600.2, 10.8), (10, 601)),
    ((float("inf"), float("-inf")), (0, 10000)),
    ((250, float("-inf")), (0, 250)),
])
def test_the_time_range_follows_the_gplates_valid_time(tmp_path, valid, expected):
    features = write_features(tmp_path / "features.gpml",
                              [a_feature(geometry=a_polygon(), valid=valid)])
    assert import_files([features]).features[0].time_range == expected


### Motion


def test_a_plate_that_never_moves_gets_no_keyframes(tmp_path):
    features = write_features(tmp_path / "features.gpml", [a_feature(geometry=a_polygon())])
    rotations = write_rotations(tmp_path / "rotations.rot", turns={101: 0.0})
    assert import_files([features, rotations]).features[0].keyframes == []


def test_a_moving_plate_is_sampled_at_the_step_and_stops_repeating_itself(tmp_path):
    features = write_features(tmp_path / "features.gpml", [a_feature(geometry=a_polygon())])
    rotations = write_rotations(tmp_path / "rotations.rot", turns={101: 90.0}, oldest=50.0)
    keyframes = import_files([features, rotations], step=10.0, oldest=100.0).features[0].keyframes
    times = [key.time for key in keyframes]
    # The plate turns until 50 Ma and stands still after it, so the samples
    # between the one that says it has stopped and the last one go.
    assert times == [0.0, 10.0, 20.0, 30.0, 40.0, 50.0, 60.0, 100.0]


def test_a_rotation_sequence_in_the_feature_file_is_used(tmp_path):
    """One file may hold both, which is what a hand made import fixture does."""
    both = tmp_path / "both.gpml"
    pygplates.FeatureCollection([
        a_feature(geometry=a_polygon()),
        pygplates.Feature.create_total_reconstruction_sequence(0, 101,
            pygplates.GpmlIrregularSampling([
                pygplates.GpmlTimeSample(pygplates.GpmlFiniteRotation(
                    pygplates.FiniteRotation((90, 0), 0.0)), 0.0),
                pygplates.GpmlTimeSample(pygplates.GpmlFiniteRotation(
                    pygplates.FiniteRotation((90, 0), math.radians(20.0))), 100.0)])),
    ]).write(str(both))
    document = import_files([both])
    assert len(document.features) == 1, "the rotation sequence is not a feature of its own"
    assert [key.time for key in document.features[0].keyframes][-1] == 100.0


def test_no_rotation_file_leaves_every_feature_still(tmp_path):
    features = write_features(tmp_path / "features.gpml", [a_feature(geometry=a_polygon())])
    document = import_files([features])
    assert all(feature.keyframes == [] for feature in document.features)
    assert all("keyframes" not in group.data for group in document.groups), \
        "a group carries no motion and no keyframe list"


### The rotation convention, pinned to what the application computes

# `Feature.build_rotation_basis()` in `Logic/feature.gd` printed these matrices,
# in reading order, for these angles. The importer has to decompose them back
# into the same angles, or an imported plate would turn a different way from one
# the application moved by hand.
GODOT_BASES = {
    (10.0, 20.0, 30.0): [[0.882564068, -0.440969616, 0.163175911],
                         [0.469846308, 0.813797653, -0.342020124],
                         [0.018028304, 0.378522277, 0.925416529]],
    (-45.0, 5.0, 170.0): [[-0.707065880, -0.062095750, -0.704416037],
                          [0.172987521, -0.981060266, -0.087155737],
                          [-0.685662568, -0.183480024, 0.704416037]],
    (0.5, -0.25, 0.125): [[0.999959469, -0.002219653, 0.008726452],
                          [0.002181639, 0.999988079, 0.004363309],
                          [-0.008736034, -0.004344094, 0.999952376]],
}


@pytest.mark.parametrize("angles", list(GODOT_BASES), ids=str)
def test_the_decomposition_answers_what_the_application_started_from(angles):
    assert decompose_rotation_degrees(GODOT_BASES[angles]) == pytest.approx(angles, abs=1e-5)


### Against the data GPlates ships


@needs_gplates
def test_the_coastlines_import_feature_for_feature():
    document = import_files([COASTLINES, ROTATIONS])
    expected = [feature for feature in pygplates.FeatureCollection(str(COASTLINES))
                if feature.get_all_geometries()]
    assert len(document.features) == len(expected)
    assert len(document.root.children) == len({feature.get_reconstruction_plate_id()
                                               for feature in expected})


@needs_gplates
def test_every_imported_time_range_matches_the_gplates_valid_time():
    """Names repeat in the data, so the two lists are lined up rather than looked up."""
    document = import_files([COASTLINES, ROTATIONS])
    expected = [feature for feature in pygplates.FeatureCollection(str(COASTLINES))
                if feature.get_all_geometries()]
    expected.sort(key=lambda feature: feature.get_reconstruction_plate_id())
    assert len(document.features) == len(expected)
    for imported, feature in zip(document.features, expected):
        assert imported.title == feature.get_name(imported.title)
        begin, end = feature.get_valid_time()
        younger, older = imported.time_range
        assert younger == (0 if math.isinf(end) else max(math.floor(end), 0))
        assert older == (10000 if math.isinf(begin) else min(math.ceil(begin), 10000))


@needs_gplates
@pytest.mark.parametrize("name", ["Africa", "Australia", "India"])
def test_a_feature_stands_where_gplates_reconstructs_it_at_fifty(name):
    document = import_files([COASTLINES, ROTATIONS])
    group = next(group for group in document.root.children
                 if any(child.title == name for child in group.children))
    feature = next(child for child in group.children if child.title == name)
    plate = int(group.title.split()[1])

    matrix = build_rotation_basis(rotation_at(feature.keyframes, 50.0))
    model = pygplates.RotationModel(str(ROTATIONS))
    for latitude, longitude in feature.rings[0][::17]:
        here = xyz_to_lat_lon(multiply(matrix, lat_lon_to_xyz(latitude, longitude)))
        there = (model.get_rotation(50.0, plate)
                 * pygplates.PointOnSphere((latitude, longitude))).to_lat_lon()
        gap = math.degrees(pygplates.GeometryOnSphere.distance(
            pygplates.PointOnSphere(here), pygplates.PointOnSphere(there)))
        assert gap < 0.1


### The Geotekton side of the rotation, which the application does in GDScript


def rotation_at(keyframes, time):
    """Where the keyframes put a node at that time.

    Only the two cases the sampling can produce: a keyframe landing on the time,
    or two keyframes around it that agree, since a sample the ones on either
    side already said is what the converter leaves out.
    """
    before = [key for key in keyframes if key.time <= time][-1]
    after = [key for key in keyframes if key.time >= time][0]
    assert before.rotation == after.rotation or before.time == after.time == time
    return before.rotation


def build_rotation_basis(angles):
    """R = Ry(x) Rx(y) Rz(z), as `Feature.build_rotation_basis()` builds it."""
    x, y, z = (math.radians(angle) for angle in angles)
    turns = ([[math.cos(x), 0, math.sin(x)], [0, 1, 0], [-math.sin(x), 0, math.cos(x)]],
             [[1, 0, 0], [0, math.cos(y), -math.sin(y)], [0, math.sin(y), math.cos(y)]],
             [[math.cos(z), -math.sin(z), 0], [math.sin(z), math.cos(z), 0], [0, 0, 1]])
    matrix = turns[0]
    for turn in turns[1:]:
        matrix = [[sum(matrix[row][k] * turn[k][column] for k in range(3))
                   for column in range(3)] for row in range(3)]
    return matrix


def multiply(matrix, vector):
    return [sum(matrix[row][column] * vector[column] for column in range(3)) for row in range(3)]


def lat_lon_to_xyz(latitude, longitude):
    lat, lon = math.radians(latitude), math.radians(longitude)
    return (math.cos(lat) * math.cos(lon), math.sin(lat), math.cos(lat) * math.sin(lon))


def xyz_to_lat_lon(point):
    return (math.degrees(math.asin(max(-1.0, min(1.0, point[1])))),
            math.degrees(math.atan2(point[2], point[0])))


def test_the_helper_matches_what_the_application_builds():
    for angles, expected in GODOT_BASES.items():
        built = build_rotation_basis(angles)
        assert [value for row in built for value in row] == pytest.approx(
            [value for row in expected for value in row], abs=1e-6)


### A project rather than a list of files


def test_a_project_names_the_files_and_they_are_imported(tmp_path):
    features = write_features(tmp_path / "features.gpml", [a_feature(geometry=a_polygon())])
    rotations = write_rotations(tmp_path / "rotations.rot")
    project = tmp_path / "session.gproj"
    project.write_bytes(_project_bytes(str(project).replace("\\", "/"),
                                       [str(path).replace("\\", "/")
                                        for path in (features, rotations)]))
    document = import_project(project)
    assert [feature.title for feature in document.features] == ["Somewhere"]
    assert document.features[0].keyframes != []


def test_a_project_naming_a_file_that_is_gone_says_so_and_imports_the_rest(tmp_path, caplog):
    features = write_features(tmp_path / "features.gpml", [a_feature(geometry=a_polygon())])
    project = tmp_path / "session.gproj"
    project.write_bytes(_project_bytes(str(project).replace("\\", "/"), [
        str(features).replace("\\", "/"), str(tmp_path / "gone.rot").replace("\\", "/")]))
    with caplog.at_level(logging.WARNING, logger="geotekt.gplates"):
        document = import_project(project)
    assert len(document.features) == 1
    assert "gone.rot" in caplog.text
