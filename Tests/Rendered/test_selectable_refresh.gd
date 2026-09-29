extends RenderedCase

# GP-0153: the Properties panel refills its fields whenever anything moves.
# Filling a field with the text it already shows keeps what is selected in it;
# setting the text anew dropped the selection at the next refresh.


func test_the_same_text_keeps_the_selection() -> void:
	await load_sample("empty.geotekt")
	for field: Control in [SelectableLines.new(), SelectableText.new()]:
		app.add_child(field)
		field.show_data("%s of %s", ["12", "40"])
		await frames(2)
		field.select_range(0, 2)
		field.show_data("%s of %s", ["12", "40"])
		assert_eq(field.get_selected_text(), "12", "%s keeps the selection" % field.get_class())
		field.show_data("%s of %s", ["13", "40"])
		assert_eq(field.get_selected_text(), "", "%s drops it when the text changes" % field.get_class())
		field.queue_free()
