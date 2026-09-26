# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
class_name TestGrassViewStrip
extends GrassSuite
## The view strip's year (GrassYearTrack) and the spans it shares with the Seasons tab (GrassSeason.spans): the
## meteorological seasons, a day's place and back, a month letter's 15th, a drag until the release, nothing while
## locked.


static func run() -> Dictionary:
	return await GrassSuite.run_suite(TestGrassViewStrip.new(), "grass_view_strip")


func test_spans() -> void:
	assert_eq(GrassSeason.spans(10.0, 20.0), [Vector2(10.0, 20.0)], "a window inside the year")
	assert_eq(GrassSeason.spans(300.0, 50.0), [Vector2(300.0, 365.0), Vector2(0.0, 50.0)], "one past the year's end: two")
	assert_eq(GrassSeason.spans(0.0, 365.0), [Vector2(0.0, 365.0)], "the whole year")


func test_seasons_and_places() -> void:
	assert_eq(range(12).map(func(m): return GrassYearTrack.season_of_month(m)), [0, 0, 1, 1, 1, 2, 2, 2, 3, 3, 3, 0],
		"winter Dec to Feb, spring Mar to May, summer Jun to Aug, autumn Sep to Nov")
	assert_eq(GrassYearTrack.day_at(GrassYearTrack.x_of(195.0, 365.0), 365.0), 195.0, "a day's place and back")
	assert_eq(GrassYearTrack.month_at(GrassYearTrack.x_of(195.0, 365.0), 4.0, 365.0), 6, "a month letter at the top")
	assert_eq(GrassYearTrack.month_at(100.0, 20.0, 365.0), -1, "none on the track")


func test_input() -> void:
	var t := GrassYearTrack.new()
	t.size = Vector2(365.0, 36.0)
	var got := []
	t.day_changed.connect(func(d: float) -> void: got.append(d))
	t._gui_input(_button(Vector2(GrassYearTrack.x_of(200.0, 365.0), 4.0), true))
	assert_eq(got, [GrassPreviewMenu.DAYS[6]], "a month letter: its 15th")
	t._gui_input(_button(Vector2(GrassYearTrack.x_of(40.0, 365.0), 20.0), true))
	t._gui_input(_motion(Vector2(GrassYearTrack.x_of(60.0, 365.0), 20.0)))
	t._gui_input(_button(Vector2.ZERO, false))
	t._gui_input(_motion(Vector2(GrassYearTrack.x_of(90.0, 365.0), 20.0)))
	assert_eq(got.slice(1), [40.0, 60.0], "the track: a press and a drag set the day, until the release")
	t.locked = true
	t._gui_input(_button(Vector2(10.0, 20.0), true))
	assert_eq(got.size(), 3, "locked: nothing")
	t.free()


static func _button(p: Vector2, p_down: bool) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = p_down
	e.position = p
	return e


static func _motion(p: Vector2) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.position = p
	return e
