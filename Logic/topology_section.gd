class_name TopologySection
extends RefCounted

# One piece of a topology: a run of vertices borrowed from another feature.
#
# The feature is named by its uuid rather than by its position in the tree,
# because a topology outlives a save and the tree is rebuilt from the file every
# time; see Docs/Editing.md#topologies. The range is a pair of indices into
# one part of that feature, both ends included, and the direction says which way
# round the run is walked.
#
# A section holds no vertices of its own. Where it is at a given time is worked
# out in Topology.resolve(), which is also where a section naming a feature that
# is no longer there becomes a broken one rather than an empty one.

# The uuid of the feature the run is taken from.
var feature_uuid: String = ""

# Which part of that feature, and which of its vertices, both ends included.
var part: int = 0
var from_index: int = 0
var to_index: int = 0

# Whether the run is walked from to_index back to from_index. A boundary is
# built by clicking one feature after another, and the vertices of the second
# one often run the other way round from the first.
var reversed: bool = false


static func create(feature_uuid_: String, part_: int, from_: int, to_: int,
		reversed_: bool = false) -> TopologySection:
	var section := TopologySection.new()
	section.feature_uuid = feature_uuid_
	section.part = part_
	section.from_index = from_
	section.to_index = to_
	section.reversed = reversed_
	return section


# A section covering the whole of one part of a feature.
static func whole_part(feature: Feature, part: int) -> TopologySection:
	var size := feature.rings[part].size() if part < feature.rings.size() else 0
	return create(feature.uuid, part, 0, maxi(0, size - 1))


func clone() -> TopologySection:
	return create(feature_uuid, part, from_index, to_index, reversed)


# How the range reads for a person: the vertex numbers the panel shows, which
# count from one, and which way round the run is walked.
func range_text() -> String:
	return "%d-%d%s" % [from_index + 1, to_index + 1, " reversed" if reversed else ""]


### JSON serialization


func to_json() -> Variant:
	return {
		"feature": feature_uuid,
		"part": part,
		"from": from_index,
		"to": to_index,
		"reversed": reversed,
	}


static func from_json(data: Variant) -> TopologySection:
	if data is not Dictionary:
		return create("", 0, 0, 0)
	return create(str(data.get("feature", "")), int(data.get("part", 0)),
		int(data.get("from", 0)), int(data.get("to", 0)), bool(data.get("reversed", false)))


static func list_to_json(sections: Array[TopologySection]) -> Array:
	var result: Array = []
	for section in sections:
		result.append(section.to_json())
	return result


static func list_from_json(data: Array) -> Array[TopologySection]:
	var result: Array[TopologySection] = []
	for section_data in data:
		result.append(TopologySection.from_json(section_data))
	return result


static func clone_list(sections: Array[TopologySection]) -> Array[TopologySection]:
	var result: Array[TopologySection] = []
	for section in sections:
		result.append(section.clone())
	return result
