# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name GrassYearTrack
extends Control
## The view strip's year: one track coloured by the meteorological seasons, the month letters above it (the current one
## brighter), the selected species' flowering windows in pink under it, the preview's date as a knob. Drag anywhere on
## the track to set the day (day_changed, live); click a month letter for its 15th. `locked`: greyed and deaf (the map
## fixes the date); `dimmed`: greyed (the grass is hidden).

signal day_changed(day: float)

## Winter, spring, summer, autumn.
const SEASON_COLOURS := [Color("8fa3b3"), Color("8bc34a"), Color("e6c34a"), Color("d9803a")]
const BLOOM := Color("f06292")
const TRACK_Y := 17.0
const TRACK_H := 6.0
const KNOB_R := 7.0

var day := 0.0
var windows: Array = []           # [Vector2(from, to)] days, wrapping the year's end
var locked := false
var dimmed := false
var accent := Color("8bc34a")
var _dragging := false


func _init() -> void:
	custom_minimum_size = Vector2(300.0, 36.0)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP


## The season of a month (0 = January): 0 winter (Dec to Feb), 1 spring, 2 summer, 3 autumn.
static func season_of_month(m: int) -> int:
	return int(((m + 1) % 12) / 3)


## The day at `x` across `width` (whole days, 0..364).
static func day_at(x: float, width: float) -> float:
	return clampf(floorf(x / maxf(width, 1.0) * GrassSeason.YEAR), 0.0, GrassSeason.YEAR - 1.0)


## The middle of day `d` across `width`.
static func x_of(d: float, width: float) -> float:
	return (fposmod(d, GrassSeason.YEAR) + 0.5) / GrassSeason.YEAR * width


## The month whose letter is at `x` in the letters' row (above the track), or -1 below it.
static func month_at(x: float, y: float, width: float) -> int:
	if y > TRACK_Y - 2.0:
		return -1
	return _month_of(day_at(x, width))


static func _month_of(d: float) -> int:
	for m in range(11, -1, -1):
		if d >= GrassSeason.MONTH_START[m]:
			return m
	return 0


func set_day(p_day: float) -> void:
	day = fposmod(p_day, GrassSeason.YEAR)
	queue_redraw()


func _gui_input(p_ev: InputEvent) -> void:
	if locked:
		return
	if p_ev is InputEventMouseButton and (p_ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		if p_ev.pressed:
			var m := month_at(p_ev.position.x, p_ev.position.y, size.x)
			if m >= 0:
				_emit(GrassPreviewMenu.DAYS[m])
			else:
				_dragging = true
				_emit(day_at(p_ev.position.x, size.x))
		else:
			_dragging = false
		if is_inside_tree():
			accept_event()
	elif p_ev is InputEventMouseMotion and _dragging:
		_emit(day_at(p_ev.position.x, size.x))
		if is_inside_tree():
			accept_event()


func _emit(p_day: float) -> void:
	if p_day != day:
		set_day(p_day)
		day_changed.emit(day)


func _draw() -> void:
	var font := get_theme_default_font()
	var a := 0.35 if locked or dimmed else 1.0
	var cur := _month_of(day)
	for m in 12:
		var x0: float = float(GrassSeason.MONTH_START[m]) / GrassSeason.YEAR * size.x
		var x1: float = (float(GrassSeason.MONTH_START[m + 1]) if m < 11 else GrassSeason.YEAR) / GrassSeason.YEAR * size.x
		draw_rect(Rect2(x0, TRACK_Y, x1 - x0, TRACK_H), Color(SEASON_COLOURS[season_of_month(m)], 0.8 * a))
		var letter: String = String(GrassSeason.MONTHS[m]).left(1)
		draw_string(font, Vector2((x0 + x1) * 0.5 - 3.0, 11.0), letter, HORIZONTAL_ALIGNMENT_LEFT, -1,
			11 if m == cur else 10, Color(1.0, 1.0, 1.0, (1.0 if m == cur else 0.55) * a))
	for w in windows:
		for s in GrassSeason.spans(w.x, w.y):
			draw_rect(Rect2(s.x / GrassSeason.YEAR * size.x, TRACK_Y + TRACK_H + 2.0,
				maxf((s.y - s.x) / GrassSeason.YEAR * size.x, 1.0), 3.0), Color(BLOOM, a))
	var k := Vector2(x_of(day, size.x), TRACK_Y + TRACK_H * 0.5)
	draw_circle(k, KNOB_R, Color(1.0, 1.0, 1.0, a))
	draw_arc(k, KNOB_R - 1.5, 0.0, TAU, 24, Color(accent, a), 3.0)
