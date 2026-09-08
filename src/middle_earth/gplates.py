"""Turning a GPlates reconstruction into a Middle Earth document.

GPlates keeps a reconstruction in two halves: feature collections holding
present day geometry, each feature naming the plate it rides on, and rotation
files saying where every plate was at every time. Middle Earth keeps motion on
the tree instead, so the import puts one group per plate at the root, gives the
group the plate's rotation sampled into keyframes, and hangs the plate's
features under it. A group's motion reaches everything below it, which is what
GPlates builds out of plate ids and a rotation tree.

Nothing is reconstructed here. The geometry is written down as GPlates holds
it, at present day, and the keyframes are what move it, so the imported
document animates rather than being a snapshot.

What is imported and what is dropped is in Docs/Import.md.
"""

from __future__ import annotations

import colorsys
import logging
import math
from pathlib import Path
from uuid import uuid4

import pygplates

from .document import CURRENT_VERSION, Document, Feature
from .gproj import read_project

log = logging.getLogger(__name__)

# Logic/document.gd. An age older than this cannot be typed into the
# application, so a feature that GPlates says is valid forever stops here.
MAX_TIME = 10000

# The GPGIM feature types that have a Middle Earth type of their own. Anything
# else becomes the unclassified type, which allows every geometry kind, and so
# does anything whose geometry the type below would not allow — a terrane
# boundary is a line and the terrane type is for polygons.
FEATURE_TYPES = {
    "gpml:ClosedContinentalBoundary": "craton",
    "gpml:ContinentalCrust": "craton",
    "gpml:Craton": "craton",
    "gpml:ExtendedContinentalCrust": "craton",
    "gpml:TransitionalCrust": "craton",
    "gpml:ContinentalFragment": "terrane",
    "gpml:IslandArc": "terrane",
    "gpml:OrogenicBelt": "terrane",
    "gpml:Suture": "terrane",
    "gpml:Coastline": "coastline",
    "gpml:ContinentalRift": "ridge",
    "gpml:FractureZone": "ridge",
    "gpml:MidOceanRidge": "ridge",
    "gpml:SubductionZone": "ridge",
    "gpml:Transform": "ridge",
    "gpml:HotSpot": "marker",
    "gpml:MeshNode": "marker",
    "gpml:PolygonCentroidPoint": "marker",
    "gpml:VirtualGeomagneticPole": "marker",
}

DEFAULT_FEATURE_TYPE = "unclassified"

# Logic/feature_type.gd. Which geometry kinds each Middle Earth type allows.
ALLOWED_KINDS = {
    "unclassified": {"polygon", "polyline", "multipoint"},
    "craton": {"polygon"},
    "terrane": {"polygon"},
    "coastline": {"polygon", "polyline"},
    "ridge": {"polyline"},
    "marker": {"multipoint"},
}


def import_project(path, **options) -> Document:
    """The document a GPlates project file converts into.

    The project names the files; everything after that is `import_files`.
    """
    project = read_project(path)
    files = project.files()
    missing = [file for file in files if not file.exists()]
    for file in missing:
        log.warning("the project names %s, which is not there", file)
    return import_files([file for file in files if file.exists()], **options)


def import_files(paths, *, step: float = 10.0, oldest: float | None = None,
                 anchor_plate: int = 0) -> Document:
    """The document these GPlates files convert into.

    Rotation files and feature collections may be given in any order and are
    told apart by what is in them. `step` is how far apart the sampled
    keyframes are in millions of years, and `oldest` how far back they go; by
    default that is as far as both the rotation model and the features reach.
    """
    collections = _load(paths)
    rotations = [feature for collection in collections for feature in collection
                 if feature.get_feature_type() == pygplates.FeatureType.gpml_total_reconstruction_sequence]
    model = pygplates.RotationModel(pygplates.FeatureCollection(rotations),
                                    default_anchor_plate_id=anchor_plate) if rotations else None

    plates: dict[int, list[Feature]] = {}
    for collection in collections:
        for feature in collection:
            converted = _convert_feature(feature)
            if converted is not None:
                plates.setdefault(feature.get_reconstruction_plate_id(), []).append(converted)

    document = Document.empty(CURRENT_VERSION)
    root = document.root
    span = _span(rotations, plates, oldest)
    for plate in sorted(plates):
        group = Feature.new_group(f"Plate {plate}", uuid=str(uuid4()))
        for keyframe in _keyframes(model, plate, step, span):
            group.set_keyframe(*keyframe)
        for feature in plates[plate]:
            group.add(feature)
        root.add(group)
    log.info("imported %d features on %d plates", sum(map(len, plates.values())), len(plates))
    return document


def _load(paths) -> list:
    """Every file that reads as a feature collection, in the order given.

    A file GPlates could read and pygplates cannot — and a project names its
    colour palettes and rasters alongside its features — is reported and
    passed over, because the rest of the import is still worth having.
    """
    collections = []
    for path in paths:
        try:
            collections.append(pygplates.FeatureCollection(str(path)))
        except Exception as error:
            log.warning("%s could not be read: %s", Path(path).name, error)
    return collections


### One feature at a time


def _convert_feature(feature) -> Feature | None:
    """The Middle Earth feature this GPlates feature becomes, or None.

    A feature with no geometry of its own — a topological polygon, a raster, a
    rotation sequence — has nothing to convert and is left out.
    """
    geometries = feature.get_all_geometries()
    if not geometries:
        log.debug("%s has no geometry of its own", _name(feature))
        return None

    kind = _kind(geometries[0])
    rings = []
    for geometry in geometries:
        if _kind(geometry) != kind:
            log.debug("%s mixes geometry kinds; its %s is left out",
                      _name(feature), _kind(geometry))
            continue
        rings += _rings(geometry)

    plate = feature.get_reconstruction_plate_id()
    converted = Feature.new_feature(
        _name(feature), rings, geometry_kind=kind,
        feature_type=_feature_type(feature, kind), uuid=str(uuid4()))
    converted.color = _plate_color(plate)
    converted.time_range = _time_range(feature)
    return converted


def _name(feature) -> str:
    """What to call the feature. GPlates lets one go unnamed; Middle Earth does not."""
    name = feature.get_name(None)
    if name:
        return name
    return f"{str(feature.get_feature_type()).split(':')[-1]} {feature.get_reconstruction_plate_id()}"


def _kind(geometry) -> str:
    """The Middle Earth geometry kind this GPlates geometry is."""
    if isinstance(geometry, pygplates.PolygonOnSphere):
        return "polygon"
    if isinstance(geometry, pygplates.PolylineOnSphere):
        return "polyline"
    return "multipoint"


def _rings(geometry) -> list[list[tuple[float, float]]]:
    """The outlines it holds, each a list of [latitude, longitude] pairs.

    A polygon's interior rings come back as further outlines rather than as
    holes, because Middle Earth has no holes; see Docs/Import.md.
    """
    if not isinstance(geometry, pygplates.PolygonOnSphere):
        return [geometry.to_lat_lon_list()]
    rings = [_lat_lon(geometry.get_exterior_ring_points())]
    for index in range(geometry.get_number_of_interior_rings()):
        rings.append(_lat_lon(geometry.get_interior_ring_points(index)))
    return rings


def _lat_lon(points) -> list[tuple[float, float]]:
    return [point.to_lat_lon() for point in points]


def _feature_type(feature, kind: str) -> str:
    """The Middle Earth type, which has to allow the geometry the feature holds."""
    mapped = FEATURE_TYPES.get(str(feature.get_feature_type()), DEFAULT_FEATURE_TYPE)
    if kind in ALLOWED_KINDS[mapped]:
        return mapped
    log.debug("%s is a %s, which the %s type does not hold", _name(feature), kind, mapped)
    return DEFAULT_FEATURE_TYPE


def _time_range(feature) -> tuple[int, int]:
    """The age span the feature is there for, as whole millions of years.

    GPlates counts the same way — a larger number is older — but allows
    fractions and both infinities. The ends are rounded outwards, so a feature
    is never shown for less time than GPlates says it is there.
    """
    begin, end = feature.get_valid_time()
    older = MAX_TIME if math.isinf(begin) else min(math.ceil(begin), MAX_TIME)
    younger = 0 if math.isinf(end) else max(math.floor(end), 0)
    return younger, older


def _plate_color(plate: int) -> list[float]:
    """A colour of the plate's own, which is what GPlates identifies a plate by.

    Consecutive plate ids belong to neighbouring plates, so stepping the hue by
    the golden angle rather than by the id keeps them apart on screen.
    """
    red, green, blue = colorsys.hsv_to_rgb((plate * 0.6180339887498949) % 1.0, 0.55, 0.85)
    return [round(channel, 4) for channel in (red, green, blue)] + [1.0]


### Motion


def _span(rotations, plates, oldest: float | None) -> float:
    """How far back to sample, when the caller did not say.

    No further than the rotation model reaches, since past that every plate
    stands still, and no further than the oldest feature, since past that there
    is nothing to look at.
    """
    if oldest is not None:
        return oldest
    model_reaches = 0.0
    for feature in rotations:
        pole = feature.get_total_reconstruction_pole()
        if pole is not None:
            model_reaches = max(model_reaches,
                                max(sample.get_time() for sample in pole[2].get_time_samples()))
    features_reach = max((feature.time_range[1] for group in plates.values()
                          for feature in group), default=0)
    return min(model_reaches, features_reach)


def _keyframes(model, plate: int, step: float, oldest: float):
    """The plate's rotation sampled into keyframes, in time order.

    A sample the ones on either side of it already say is left out, so a plate
    that stops moving costs two keyframes rather than one per step, and a plate
    that never moves costs none.
    """
    if model is None or step <= 0.0:
        return []
    times = [index * step for index in range(int(oldest / step) + 1)]
    sampled = [(time, _rotation_degrees(model.get_rotation(time, plate))) for time in times]
    kept = [entry for index, entry in enumerate(sampled)
            if index in (0, len(sampled) - 1)
            or entry[1] != sampled[index - 1][1] or entry[1] != sampled[index + 1][1]]
    if len(kept) == 2 and kept[0][1] == kept[1][1] == (0.0, 0.0, 0.0):
        return []
    return kept


def _rotation_degrees(rotation) -> tuple[float, float, float]:
    """A GPlates finite rotation as the three angles Middle Earth writes.

    GPlates works in a frame with x through zero degrees, y through ninety
    degrees east and z through the north pole; Middle Earth's y is the pole and
    its z is ninety degrees east, so the two frames differ by swapping the last
    two axes. Swapping them in both the rows and the columns of the rotation
    carries it from one frame to the other.
    """
    columns = [(rotation * pygplates.PointOnSphere(axis)).to_xyz()
               for axis in ((1, 0, 0), (0, 1, 0), (0, 0, 1))]
    swap = (0, 2, 1)
    matrix = [[columns[swap[column]][swap[row]] for column in range(3)] for row in range(3)]
    return decompose_rotation_degrees(matrix)


def decompose_rotation_degrees(matrix) -> tuple[float, float, float]:
    """The three angles Middle Earth writes for a rotation matrix.

    The same decomposition as `Feature.decompose_rotation_degrees()` in
    `Logic/feature.gd`: the matrix is read as Ry(alpha) Rx(beta) Rz(gamma), and
    where beta pins the other two axes together gamma is given up and alpha
    takes the whole turn.
    """
    beta = math.asin(max(-1.0, min(1.0, -matrix[1][2])))
    if math.cos(beta) > 0.0001:
        alpha = math.atan2(matrix[0][2], matrix[2][2])
        gamma = math.atan2(matrix[1][0], matrix[1][1])
    else:
        gamma = 0.0
        alpha = math.atan2(-matrix[2][0], matrix[0][0])
    return tuple(round(math.degrees(angle), 9) for angle in (alpha, beta, gamma))
