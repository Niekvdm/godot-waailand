# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name SeasonYearStrip
extends Control
## A species' year in the Ground rules dialog's Seasons tab: one lane per flower kind (bud, bloom and seed bars across
## Jan..Dec from its window, wrapping the year's end), a white mark on
## the pinned day of each (its bars dimmed), and the preview date as a blue line. `header`: the month letters instead.

const BUD := Color("6f9f3a")
const SEED := Color("8d6e63")
const GRID := Color(1.0, 1.0, 1.0, 0.05)
const TODAY := Color(0.47, 0.75, 1.0, 0.8)
const TEXT := Color(1.0, 1.0, 1.0, 0.55)
const LANE := 8.0
const GAP := 3.0

var lanes: Array = []        # {keys: Vector4 (bud, bloom, bloom_end, gone; x < 0: every day), colour: Color}
var pins: Array = []         # the pinned day per lane; -1: none
var today := -1.0
var note := ""
var header := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _get_minimum_size() -> Vector2:
	return Vector2(120.0, 14.0 if header else maxf(float(lanes.size()), 1.0) * (LANE + GAP))


## The x of a day across `width`.
func x_of(day: float, width: float) -> float:
	return fposmod(day, GrassSeason.YEAR) / GrassSeason.YEAR * width


func _bar(a: float, b: float, y: float, col: Color) -> void:
	for s in GrassSeason.spans(a, b):
		var xa: float = s.x / GrassSeason.YEAR * size.x
		var xb: float = s.y / GrassSeason.YEAR * size.x
		draw_rect(Rect2(xa, y, maxf(xb - xa, 1.0), LANE), col)


func _draw() -> void:
	var font := get_theme_default_font()
	if header:
		for m in 12:
			draw_string(font, Vector2(x_of(GrassSeason.MONTH_START[m], size.x) + 2.0, 11.0), GrassSeason.MONTHS[m][0],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, TEXT)
		return
	for m in 12:
		var x := x_of(GrassSeason.MONTH_START[m], size.x)
		draw_line(Vector2(x, 0.0), Vector2(x, size.y), GRID)
	for i in lanes.size():
		var k: Vector4 = lanes[i]["keys"]
		var y := i * (LANE + GAP)
		var pinned := i < pins.size() and float(pins[i]) >= 0.0
		var a := 0.28 if pinned else 1.0
		if k.x < 0.0:
			draw_rect(Rect2(0.0, y, size.x, LANE), Color(lanes[i]["colour"], a))
		else:
			_bar(k.x, k.y, y, Color(BUD, a))
			_bar(k.y, k.z, y, Color(lanes[i]["colour"], a))
			_bar(k.z, k.w, y, Color(SEED, a))
		if pinned:
			draw_rect(Rect2(x_of(pins[i], size.x) - 1.5, y - 3.0, 3.0, LANE + 6.0), Color.WHITE)
	if note != "":
		draw_string(font, Vector2(4.0, 9.0), note, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, TEXT)
	if today >= 0.0:
		var x := x_of(today, size.x)
		draw_line(Vector2(x, -2.0), Vector2(x, size.y + 2.0), TODAY)
