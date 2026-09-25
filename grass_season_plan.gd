# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name GrassSeasonPlan
extends RefCounted
## A map's season settings: per species the Calendar, Always in bloom, a
## pinned stage of its own cycle or a fixed date; and the map's date (the clock, or one fixed day). Pure: GrassSeason.
## apply_types asks it each type's day, DecorationStreams.set_day each flower kind's state.

const PRIME := 0.5
## The stage slider's named ticks.
const TICKS := [["Bud", 0.1], ["Early bloom", 0.25], ["Prime", 0.5], ["Fading", 0.75], ["Seed", 0.9]]

var map_date := -1.0              # < 0: the clock (the game's day, the editor's preview date)
var by_species := {}              # species name -> {mode, stage, day} (GrassGroundRules.seasons)
var errors: PackedStringArray = []
var _first := {}                  # species name -> its first flower kind's window (bind)


static func from_rules(r: GrassGroundRules) -> GrassSeasonPlan:
	var p := GrassSeasonPlan.new()
	p.map_date = r.map_date
	p.by_species = r.seasons.duplicate(true)
	return p


## The flower windows: each species' first hosted kind that is not out every day (its blades' day follows it). Bloom or
## stage on a species without one reads as the calendar (an error).
func bind(kinds: DecoKinds, types: GrassTypes) -> void:
	_first.clear()
	for k in kinds.kinds:
		var nm := String(types.row(int(k["host"])).get("name", ""))
		var keys: Vector4 = k["bloom"]
		if nm != "" and not _first.has(nm) and keys.x >= 0.0:
			_first[nm] = keys
	errors.clear()
	for nm in by_species:
		var m := String(by_species[nm].get("mode", "calendar"))
		if (m == "bloom" or m == "stage") and not _first.has(nm):
			errors.append("%s has no flowers: \"%s\" reads as the calendar" % [nm, m])


func has_flowers(species: String) -> bool:
	return _first.has(species)


## The day the map shows: its fixed date, else the clock's.
func day(doy: float) -> float:
	return map_date if map_date >= 0.0 else doy


## The day of a flower window (bud, bloom, bloom_end, gone) at stage t: 0 the bud, 0.25 the bloom, 0.5 mid-bloom (Prime),
## 0.75 the bloom's end, 1 the last day before it is gone; linear between, wrapping the year.
static func stage_day(keys: Vector4, t: float) -> float:
	var y := GrassSeason.YEAR
	var b1 := fposmod(keys.y - keys.x, y)
	var b2 := fposmod(keys.z - keys.x, y)
	var pts := [Vector2(0.0, 0.0), Vector2(0.25, b1), Vector2(0.5, b1 + (b2 - b1) * 0.5), Vector2(0.75, b2),
		Vector2(1.0, fposmod(keys.w - keys.x, y) - 1.0)]
	t = clampf(t, 0.0, 1.0)
	for i in 4:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		if t <= b.x:
			return fposmod(keys.x + lerpf(a.y, b.y, (t - a.x) / (b.x - a.x)), y)
	return fposmod(keys.w - 1.0, y)


## The day a species' flower kind (its window `keys`) is shown at.
func kind_day(keys: Vector4, species: String, doy: float) -> float:
	var s: Dictionary = by_species.get(species, {})
	match String(s.get("mode", "calendar")):
		"bloom":
			return stage_day(keys, PRIME)
		"stage":
			return stage_day(keys, float(s.get("stage", PRIME)))
		"date":
			return float(s.get("day", doy))
	return day(doy)


## A flower kind's (grow, phase) (GrassSeason.bloom) on the clock's day, its species' setting applied.
func kind_state(keys: Vector4, species: String, doy: float) -> Vector2:
	if keys.x < 0.0:
		return GrassSeason.bloom(keys, doy)
	return GrassSeason.bloom(keys, kind_day(keys, species, doy))


## The day a species' blades are shown at (its accent, its height knots): its first kind's pinned day, its fixed date,
## or the map's day.
func type_day(species: String, doy: float) -> float:
	var m := String(by_species.get(species, {}).get("mode", "calendar"))
	if m == "date":
		return float(by_species[species].get("day", doy))
	if (m == "bloom" or m == "stage") and _first.has(species):
		return kind_day(_first[species], species, doy)
	return day(doy)
