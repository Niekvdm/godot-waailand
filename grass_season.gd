# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name GrassSeason
extends RefCounted
## The calendar. Pure: a day of the year in, bloom state and type accents out. Days are 0-based in a
## non-leap year (1 Jan = 0, 31 Dec = 364). A game feeds the day from its own clock (GrassBlades.set_date);
## it is cosmetic, so it needs no multiplayer state.

## Days in the (non-leap) year.
const YEAR := 365.0
## The day of the year each month starts on.
const MONTH_START := [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334]
## The months' short names.
const MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
## A kind that is out every day (corals): bloom() reads it as grown and
## in bloom whatever the date.
const ALWAYS := Vector4(-1.0, -1.0, -1.0, -1.0)


## The day of the year of a date (month 1..12, day 1..31).
static func day_of_year(month: int, day: int) -> float:
	return float(MONTH_START[clampi(month, 1, 12) - 1] + day - 1)


## A day of the year as a date: "15 Feb".
static func label(doy: float) -> String:
	var d := int(fposmod(doy, YEAR))
	for m in range(11, -1, -1):
		if d >= MONTH_START[m]:
			return "%d %s" % [d - MONTH_START[m] + 1, MONTHS[m]]
	return "?"


## A window from day `a` to day `b` as spans inside one year ([Vector2(from, to)]), split in two where it runs past
## the year's end; a window of a year or more is the whole year. The seasons' drawings share it (SeasonYearStrip,
## GrassYearTrack).
static func spans(a: float, b: float) -> Array:
	if b - a >= YEAR:
		return [Vector2(0.0, YEAR)]
	var fa := fposmod(a, YEAR)
	var fb := fposmod(b, YEAR)
	if fb >= fa:
		return [Vector2(fa, fb)]
	return [Vector2(fa, YEAR), Vector2(0.0, fb)]


## Bloom state for keys (bud, bloom, bloom_end, gone) as days of the year, wrapping past the
## year's end: x = grow 0..1 (buds rise; full through bloom and seed; shrink over the last
## 30 % of the seed stage), y = phase 0..2 (0 bud -> 1 bloom -> 2 seed colour). Outside: 0.
## GrassSeason.ALWAYS: (1, 1) every day.
static func bloom(keys: Vector4, doy: float) -> Vector2:
	if keys.x < 0.0:
		return Vector2(1.0, 1.0)
	var t := fposmod(doy - keys.x, YEAR)
	var b1 := fposmod(keys.y - keys.x, YEAR)
	var b2 := fposmod(keys.z - keys.x, YEAR)
	var b3 := fposmod(keys.w - keys.x, YEAR)
	if t >= b3:
		return Vector2.ZERO
	if t < b1:
		return Vector2(smoothstep(0.0, b1, t), t / b1)
	if t <= b2:
		return Vector2(1.0, 1.0)
	var s := (t - b2) / maxf(b3 - b2, 1.0)
	return Vector2(1.0 - smoothstep(0.7, 1.0, s), 1.0 + s)


## A type's accent weight on a day: a bump `width` days wide around `peak`, wrapping the year.
static func accent(peak: float, width: float, doy: float) -> float:
	var d := absf(fposmod(doy - peak + YEAR * 0.5, YEAR) - YEAR * 0.5)
	return exp(-(d / width) * (d / width))


## A type's height factor on a day from its (day, factor) knots (ascending days), linear between them
## and wrapping the year (the last knot runs on into the first). No knots: 1.
static func height_factor(knots: Array, doy: float) -> float:
	if knots.is_empty():
		return 1.0
	var d := fposmod(doy, YEAR)
	var n := knots.size()
	for i in n:
		var a: Vector2 = knots[i]
		var b: Vector2 = knots[(i + 1) % n]
		var span := fposmod(b.x - a.x, YEAR)
		var t := fposmod(d - a.x, YEAR)
		if span <= 0.0:
			return a.y                       # one knot: the whole year
		if t <= span:
			return lerpf(a.y, b.y, t / span)
	return (knots[0] as Vector2).y


## Sets each row's `accent` from its accent_peak / accent_width (rows without them keep 0), and its
## `season_h` from its height_season knots (rows without them: 1), the compute's height factor. `plan`: a map's
## season settings (GrassSeasonPlan), each type on its own day.
static func apply_types(types: GrassTypes, doy: float, plan: GrassSeasonPlan = null) -> void:
	for r in types.rows:
		if r.is_empty():
			continue
		var d := plan.type_day(String(r.get("name", "")), doy) if plan != null else doy
		if r.has("accent_peak"):
			r["accent"] = accent(r["accent_peak"], r["accent_width"], d)
		r["season_h"] = height_factor(r.get("height_season", []), d)
