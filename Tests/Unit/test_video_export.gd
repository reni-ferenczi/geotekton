extends TestCase

# What a video export is made of before anything is rendered: how many frames
# a range at a speed and a frame rate comes to, which age each of them is, and
# the size an encoder will take. See Docs/Shell.md#exporting-a-video-of-the-animation.


func test_the_frame_count_covers_both_ends_of_the_range() -> void:
	# The gate case: a hundred million years at a hundred My a second, ten
	# frames a second, is ten steps and so eleven frames.
	assert_eq(Application.video_frame_count(2000.0, 1900.0, 100.0, 10.0), 11)
	assert_eq(Application.video_frame_count(1900.0, 2000.0, 100.0, 10.0), 11,
		"the direction does not change how many there are")
	assert_eq(Application.video_frame_count(2000.0, 0.0, 50.0, 30.0), 1201,
		"the default animation at thirty frames a second")
	assert_eq(Application.video_frame_count(100.0, 100.0, 50.0, 30.0), 1,
		"a range of no length is one frame")


func test_a_range_that_does_not_divide_gets_a_frame_of_its_own() -> void:
	# Ten million years at four a second and one frame a second is two and a
	# half steps, and the half is a frame like any other.
	assert_eq(Application.video_frame_count(10.0, 0.0, 4.0, 1.0), 4)
	var times := _times(10.0, 0.0, 4.0, 1.0, 4)
	assert_close(times[2], 2.0, 1e-9, "the third frame is two million years in")
	assert_close(times[3], 0.0, 1e-9, "and the last one lands on the end exactly")


func test_every_frame_has_its_age_and_the_last_is_the_end() -> void:
	var times := _times(2000.0, 1900.0, 100.0, 10.0, 11)
	assert_close(times[0], 2000.0, 1e-9, "the first frame is the age it starts from")
	assert_close(times[1], 1990.0, 1e-9, "and one frame is speed over fps older")
	assert_close(times[10], 1900.0, 1e-9, "the last frame is the age it ends at")
	for index in times.size() - 1:
		assert_true(times[index] > times[index + 1], "the ages run towards the present")

	var backwards := _times(0.0, 100.0, 100.0, 10.0, 11)
	assert_close(backwards[0], 0.0, 1e-9, "a range the other way round starts at its own end")
	assert_close(backwards[10], 100.0, 1e-9, "and finishes at the older age")


func test_a_frame_is_never_past_the_end() -> void:
	# The clamp matters where the range does not divide: the index of the last
	# frame walks past the end and the end is what it holds.
	assert_close(Application.video_frame_time(10.0, 0.0, 4.0, 1.0, 3), 0.0, 1e-9)
	assert_close(Application.video_frame_time(0.0, 10.0, 4.0, 1.0, 3), 10.0, 1e-9)


func test_an_encoder_is_given_even_sides() -> void:
	assert_eq(Application.even_size(Vector2i(720, 360)), Vector2i(720, 360),
		"a rectangular sheet is even already")
	assert_eq(Application.even_size(
		PlanetView.export_size(MapProjection.Kind.ROBINSON, 720)), Vector2i(720, 364),
		"a Robinson sheet is 365 pixels tall and loses the odd row")
	assert_eq(Application.even_size(Vector2i(241, 121)), Vector2i(240, 120),
		"both sides round down")
	assert_eq(Application.even_size(Vector2i(1, 1)), Vector2i(2, 2),
		"and neither side is ever nought pixels")


func test_settings_nothing_can_be_made_of_are_refused() -> void:
	var options := {"from": 2000.0, "to": 0.0, "speed": 50.0, "fps": 30.0, "width": 720.0}
	assert_eq(Application.video_problem(options), "", "the defaults are fine")

	assert_true("speed" in Application.video_problem(
		options.merged({"speed": 0.0}, true)), "a speed of nought goes nowhere")
	assert_true("frame rate" in Application.video_problem(
		options.merged({"fps": 0.5}, true)), "and half a frame a second is not a rate")
	assert_true("outside" in Application.video_problem(
		options.merged({"from": -1.0}, true)), "an age before the present is not an age")
	assert_true("frames" in Application.video_problem(
		options.merged({"speed": 0.001}, true)),
		"two thousand million years at a thousandth a second is more frames than anyone wants")


# The age of each of count frames, which is what the export walks through.
func _times(from: float, to: float, speed: float, fps: float,
		count: int) -> PackedFloat64Array:
	assert_eq(Application.video_frame_count(from, to, speed, fps), count,
		"the count these times are asked for")
	var times := PackedFloat64Array()
	for index in count:
		times.append(Application.video_frame_time(from, to, speed, fps, index))
	return times
