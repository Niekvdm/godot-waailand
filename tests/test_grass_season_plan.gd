# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
class_name TestGrassSeasonPlan
extends GrassSuite
## A map's season settings: a stage on a flower's own window (wrapping the
## year), each mode, two kinds pinned at one stage, a species without flowers, the map's date, and what the blades
## (apply_types) and the flowers (DecorationStreams.set_day) get.

const FREESIA := Vector4(68.0, 80.0, 99.0, 109.0)      # 10 Mar, 22 Mar, 10 Apr, 20 Apr
const PLUME := Vector4(212.0, 231.0, 292.0, 30.0)      # 1 Aug, 20 Aug, 20 Oct, 31 Jan: over the year's end

var types := GrassTypes.new()
var kinds := DecoKinds.new(DecoKinds.FROM_CONFIG, types)


static func run() -> Dictionary:
	var keep := GrassSuite.use_fixture_species()           # the addon's own species: it passes in any project
	var r := await GrassSuite.run_suite(TestGrassSeasonPlan.new(), "grass_season_plan")
	GrassBladesConfig.use(keep)
	return r


func _plan(seasons: Dictionary, map_date := -1.0) -> GrassSeasonPlan:
	var r := GrassGroundRules.new()
	for sp in seasons:
		r.set_season(sp, seasons[sp]["mode"], float(seasons[sp].get("stage", seasons[sp].get("day", 0.0))))
	r.set_map_date(map_date)
	var p := GrassSeasonPlan.from_rules(r)
	p.bind(kinds, types)
	return p


func _keys(nm: String) -> Vector4:
	return kinds.kinds[kinds.index_of(nm)]["bloom"]


func test_a_stage_on_a_window() -> void:
	assert_near(GrassSeasonPlan.stage_day(FREESIA, 0.0), 68.0, 1e-6, "0: the bud")
	assert_near(GrassSeasonPlan.stage_day(FREESIA, 0.25), 80.0, 1e-6, "0.25: the bloom starts")
	assert_near(GrassSeasonPlan.stage_day(FREESIA, 0.5), 89.5, 1e-6, "0.5, Prime: mid-bloom")
	assert_near(GrassSeasonPlan.stage_day(FREESIA, 0.75), 99.0, 1e-6, "0.75: the bloom's end")
	assert_near(GrassSeasonPlan.stage_day(FREESIA, 1.0), 108.0, 1e-6, "1: the last day before it is gone")
	assert_near(GrassSeasonPlan.stage_day(PLUME, 0.75), 292.0, 1e-6, "a window over the year's end: its bloom's end")
	assert_near(GrassSeasonPlan.stage_day(PLUME, 1.0), 29.0, 1e-6, "and its last day, in January")
	assert_eq(GrassSeason.bloom(FREESIA, GrassSeasonPlan.stage_day(FREESIA, 0.5)), Vector2(1.0, 1.0), "Prime is full bloom")


func test_the_modes() -> void:
	var fr := _keys("freesia")
	var sept := 257.0
	assert_eq(_plan({}).kind_state(fr, "freesia", sept), Vector2.ZERO, "the calendar: gone in September")
	assert_eq(_plan({"freesia": {"mode": "bloom"}}).kind_state(fr, "freesia", sept), Vector2(1.0, 1.0),
		"always in bloom: in flower in September")
	var seed := _plan({"freesia": {"mode": "stage", "stage": 0.9}}).kind_state(fr, "freesia", sept)
	assert_true(seed.x > 0.0 and seed.y > 1.0, "pinned at Seed: out, in its seed colours (%s)" % seed)
	assert_eq(_plan({"freesia": {"mode": "date", "day": 85.0}}).kind_state(fr, "freesia", sept), Vector2(1.0, 1.0),
		"a fixed date, 26 Mar: in bloom")
	assert_eq(_plan({"freesia": {"mode": "bloom"}}).kind_state(GrassSeason.ALWAYS, "coral", sept), Vector2(1.0, 1.0),
		"an ALWAYS kind stays out")
	var md := _plan({}, 85.0)
	assert_eq([md.day(sept), md.kind_state(fr, "freesia", sept)], [85.0, Vector2(1.0, 1.0)],
		"the map's date (26 Mar) wins over the clock")


func test_two_kinds_at_one_stage() -> void:
	var p := _plan({"susuki": {"mode": "stage", "stage": 0.75}})
	for nm in ["susuki_plume", "sakuyuri"]:
		assert_near(p.kind_day(_keys(nm), "susuki", 100.0), _keys(nm).z, 1e-6, "%s at its own bloom's end" % nm)
	assert_near(p.type_day("susuki", 100.0), _keys("susuki_plume").z, 1e-6, "the blades: the first kind's pinned day")


func test_a_species_without_flowers() -> void:
	var p := _plan({"pasture": {"mode": "bloom"}, "fern": {"mode": "date", "day": 200.0}})
	assert_eq(p.errors.size(), 1, "bloom on pasture, which has no flowers, is an error (%s)" % [p.errors])
	assert_near(p.type_day("pasture", 40.0), 40.0, 1e-6, "and reads as the calendar")
	assert_near(p.type_day("fern", 40.0), 200.0, 1e-6, "a fixed date works without flowers")
	assert_true(p.has_flowers("freesia") and not p.has_flowers("pasture"), "has_flowers")


func test_the_blades_and_flowers_follow_the_plan() -> void:
	var t := GrassTypes.new()
	GrassSeason.apply_types(t, 300.0, _plan({"chigaya": {"mode": "date", "day": 135.0}}))
	var ch: Dictionary = t.row(t.names().find("chigaya"))
	assert_near(float(ch["accent"]), 1.0, 1e-6, "chigaya's accent at its fixed date's peak (15 May)")
	var su: Dictionary = t.row(t.names().find("susuki"))
	assert_near(float(su["accent"]), GrassSeason.accent(su["accent_peak"], su["accent_width"], 300.0), 1e-6,
		"susuki on the calendar")
	var ds := DecorationStreams.new()
	ds.kinds = kinds
	ds.prepare(types)
	ds.set_day(257.0, _plan({"freesia": {"mode": "bloom"}}))
	assert_eq(ds.state(kinds.index_of("freesia")), Vector2(1.0, 1.0), "the flowers: freesia out in September")
	assert_eq(ds.state(kinds.index_of("spider_lily")), GrassSeason.bloom(_keys("spider_lily"), 257.0),
		"spider lily on the calendar")
	ds.set_day(257.0)
	assert_eq(ds.state(kinds.index_of("freesia")), Vector2.ZERO, "no plan: the calendar, as before")
