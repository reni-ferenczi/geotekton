extends TestCase

# GP-0151: a feature coupled to a plate can be shown under the plate's row in
# the feature tree, "Show under parent". See Coupling.folds() and
# Document.set_under_parent().


### Helpers


# A document with a plate in one group and an add-on following it, from 500 Ma
# to the present, in another.
func _document() -> Document:
	var document := Document.new()
	var plates := Feature.create_group("Plates")
	var plate := Feature.create_feature("Plate")
	plates.children.append(plate)
	var extras := Feature.create_group("Extras")
	var add_on := Feature.create_feature("Add-on", Color.RED, Vector2i(0, 500))
	add_on.couplings.append(Coupling.create(500.0, 0.0, plate.uuid))
	extras.children.append(add_on)
	document.root.children.append_array([plates, extras])
	document.record()
	return document


func _find(document: Document, title: String) -> Feature:
	var stack: Array[Feature] = [document.root]
	while not stack.is_empty():
		var node: Feature = stack.pop_back()
		if node.title == title:
			return node
		stack.append_array(node.children)
	return null


### Which parent


func test_the_parent_is_the_one_the_youngest_span_follows() -> void:
	var document := _document()
	var add_on := _find(document, "Add-on")
	var other := Feature.create_feature("Other")
	document.root.children.append(other)
	add_on.couplings.append(Coupling.create(900.0, 500.0, other.uuid))
	Coupling.sort(add_on.couplings)
	var nodes := Coupling.index(document.root)
	assert_eq(Coupling.fold_parent(nodes, add_on), _find(document, "Plate"),
		"the span running to the present names the plate")


func test_no_parent_without_a_coupling_or_with_two_parents() -> void:
	var document := _document()
	var add_on := _find(document, "Add-on")
	var plate := _find(document, "Plate")
	var nodes := Coupling.index(document.root)
	assert_eq(Coupling.fold_parent(nodes, plate), null, "an uncoupled feature has none")
	add_on.couplings[0].parent_b = plate.uuid
	assert_eq(Coupling.fold_parent(nodes, add_on), null, "a span midway between two has none")
	assert_true(document.set_under_parent(add_on, true) != "", "so it cannot be shown under one")
	assert_true(not add_on.under_parent, "and the flag stays off")


### Turning it on and off


func test_turning_it_on_moves_the_add_on_after_its_plate() -> void:
	var document := _document()
	var add_on := _find(document, "Add-on")
	var plates := _find(document, "Plates")
	var versions := document.applied
	assert_eq(document.set_under_parent(add_on, true), "", "the add-on can go under its plate")
	assert_eq(document.root.find_parent(add_on), plates, "it moved into the plate's group")
	assert_eq(plates.find_child(add_on), 1, "right after the plate")
	assert_eq(document.applied, versions + 1, "in one undo step")
	assert_eq(Coupling.folds(document.root), {add_on: _find(document, "Plate")},
		"and is shown under the plate")

	assert_eq(document.set_under_parent(add_on, false), "", "turning it off works")
	assert_eq(document.root.find_parent(add_on), plates, "and leaves it next to the plate")
	assert_true(Coupling.folds(document.root).is_empty(), "as an ordinary row")


func test_the_flag_is_saved_only_when_set() -> void:
	var document := _document()
	var add_on := _find(document, "Add-on")
	assert_true(not add_on.to_json().has("under_parent"), "an ordinary feature writes no key")
	document.set_under_parent(add_on, true)
	assert_eq(add_on.to_json()["under_parent"], true, "one shown under its parent does")
	assert_true(Feature.from_json(add_on.to_json()).under_parent, "and reads it back")
	assert_true(add_on.clone().under_parent, "a clone, which every undo step is, keeps it")


### Chains, loops, moves and deletes


func test_an_add_on_of_an_add_on_nests_and_loops_stay_in_their_groups() -> void:
	var document := _document()
	var plate := _find(document, "Plate")
	var add_on := _find(document, "Add-on")
	var second := Feature.create_feature("Second", Color.RED, Vector2i(0, 300))
	second.couplings.append(Coupling.create(300.0, 0.0, add_on.uuid))
	second.under_parent = true
	document.root.children.append(second)
	add_on.under_parent = true
	assert_eq(Coupling.add_ons(document.root, plate), [add_on, second] as Array[Feature],
		"the plate holds its add-on and the add-on's add-on")

	# Two features each shown under the other: neither is.
	plate.couplings.append(Coupling.create(2000.0, 0.0, second.uuid))
	plate.under_parent = true
	assert_true(Coupling.folds(document.root).is_empty(), "a loop leaves every row in its group")


func test_gather_brings_the_add_ons_after_their_plate() -> void:
	var document := _document()
	var plate := _find(document, "Plate")
	var add_on := _find(document, "Add-on")
	document.set_under_parent(add_on, true)
	var elsewhere := Feature.create_group("Elsewhere")
	document.root.children.append(elsewhere)
	_find(document, "Plates").children.erase(plate)
	elsewhere.children.append(plate)
	Coupling.gather(document.root, plate)
	assert_eq(elsewhere.children, [plate, add_on] as Array[Feature],
		"the add-on followed the plate to its new group")


func test_deleting_a_plate_can_take_its_add_ons() -> void:
	var document := _document()
	var plate := _find(document, "Plate")
	var add_on := _find(document, "Add-on")
	document.set_under_parent(add_on, true)
	assert_eq(document.delete_node(plate, Coupling.add_ons(document.root, plate)), "",
		"the plate and its add-on can go together")
	assert_eq(_find(document, "Add-on"), null, "the add-on is gone")
	document.undo()
	var back := _find(document, "Add-on")
	assert_true(back != null and back.under_parent, "one undo brings both back")


### On and off on the globe


func test_an_add_on_is_drawn_only_while_its_plate_is() -> void:
	var document := _document()
	var plate := _find(document, "Plate")
	var add_on := _find(document, "Add-on")
	var drawn := func() -> Array[Feature]: return Planet._drawing_order(document.root)
	plate.enabled = false
	assert_true(add_on in drawn.call(), "an ordinary coupled feature is drawn without its parent")
	document.set_under_parent(add_on, true)
	plate = _find(document, "Plate")
	plate.enabled = false
	assert_true(not add_on in drawn.call(), "shown under the plate, it goes off with it")
	plate.enabled = true
	_find(document, "Plates").enabled = false
	assert_true(not add_on in drawn.call(), "and with the plate's group")
