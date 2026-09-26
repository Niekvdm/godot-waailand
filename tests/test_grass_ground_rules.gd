# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
class_name TestGrassGroundRules
extends GrassSuite
## A map's ground rules: the file's round trip and validation, the operations
## the Ground rules dialog uses, the snapshots.

const SAMPLE := {"format": 1, "default_grass": true, "rules": [
	{"name": "Meadows", "colour": "#8bc34a", "surfaces": ["Pasture", "Town Ground"], "default_grass": true,
		"density": 1.0, "species": {"pasture": 0.65, "verge": 0.35}},
	{"name": "Susuki slopes", "colour": "#d4b36a", "surfaces": ["Susuki Grass"], "default_grass": false, "density": 0.8,
		"species": {"susuki": 0.5, "chigaya": 0.3}, "band": {"above_m": 700.0, "species": {"summit": 0.8, "susuki": 0.2}}},
	{"name": "Bare", "colour": "#616161", "surfaces": ["Asphalt"], "default_grass": true, "density": 0.0, "species": {}}],
	"everything_else": {"default_grass": true, "density": 1.0, "species": {"verge": 0.6, "pasture": 0.4}},
	"seasons": {"freesia": {"mode": "bloom"}, "higanbana": {"mode": "stage", "stage": 0.3},
		"pasture": {"mode": "date", "day": 196.0}},
	"map_date": null}


static func run() -> Dictionary:
	var keep := GrassSuite.use_fixture_species()           # the addon's own species: it passes in any project
	var r := await GrassSuite.run_suite(TestGrassGroundRules.new(), "grass_ground_rules")
	GrassBladesConfig.use(keep)
	return r


func _sample() -> GrassGroundRules:
	return GrassGroundRules.from_text(JSON.stringify(SAMPLE))


func test_the_file_round_trips() -> void:
	var r := _sample()
	assert_eq(r.errors, PackedStringArray(), "no errors")
	assert_eq([r.rules.size(), r.rule_of("town ground"), r.rule_of("Susuki Grass"), r.rule_of("Mud")], [3, 0, 1, -1],
		"three rules; a surface's rule by name (any case); -1 = Everything else")
	assert_eq(r.rules[1]["band"], {"above_m": 700.0, "species": {"summit": 0.8, "susuki": 0.2}}, "the band")
	assert_eq(r.seasons["higanbana"], {"mode": "stage", "stage": 0.3}, "a pinned stage")
	assert_true(r.map_date < 0.0, "no map date: the clock")
	var again := GrassGroundRules.from_text(r.to_text())
	assert_eq(again.snapshot(), r.snapshot(), "to_text, then from_text: the same rules")
	assert_eq(again.to_text(), r.to_text(), "and the same text (a stable writer)")
	var lines := r.to_text().split("\n")
	assert_true(lines.has('\t\t{"name":"Meadows","colour":"#8bc34a","surfaces":["Pasture","Town Ground"],"default_grass":true,"density":1.0,"species":{"pasture":0.65,"verge":0.35}},'),
		"one rule a line, its keys in a fixed order (not sorted)")
	assert_true(lines.has('\t"map_date": null'), "no map date is null")


func test_what_is_wrong_is_dropped_and_listed() -> void:
	var doc: Dictionary = SAMPLE.duplicate(true)
	doc["rules"][0]["species"]["dragonfruit"] = 1.0
	doc["rules"][2]["surfaces"].append("Pasture")
	doc["rules"][1]["density"] = 1.5
	doc["seasons"]["fern"] = {"mode": "blooming"}
	var r := GrassGroundRules.from_text(JSON.stringify(doc))
	assert_eq(r.errors.size(), 4, "four errors (%s)" % [r.errors])
	assert_eq(r.rules[0]["species"], {"pasture": 0.65, "verge": 0.35}, "the unknown species dropped, the others kept")
	assert_eq(r.rules[2]["surfaces"], ["Asphalt"], "a surface stays in its first rule")
	assert_near(float(r.rules[1]["density"]), 1.0, 1e-6, "the density clamped to 0..1")
	assert_true(not r.seasons.has("fern"), "the bad season dropped")
	assert_eq(GrassGroundRules.from_text('{"format": 2}').errors.size(), 1, "another format is refused")
	assert_eq(GrassGroundRules.from_text("[1]").errors.size(), 1, "not a rules file")
	assert_true(GrassGroundRules.load_file("res://no/such/rules.json") == null, "no file: null (the shared table)")


func test_the_operations() -> void:
	var r := _sample()
	r.move_surface("Town Ground", 2)
	assert_eq([r.rule_of("Town Ground"), r.rules[0]["surfaces"]], [2, ["Pasture"]], "moved from Meadows to Bare")
	r.move_surface("Town Ground", -1)
	assert_eq(r.rule_of("Town Ground"), -1, "out of every rule: Everything else")
	var i := r.new_rule_from("Pasture")
	assert_eq([i, r.rules[i]["name"], r.rules[i]["surfaces"], r.rules[i]["species"], r.rules[0]["surfaces"]],
		[3, "Pasture", ["Pasture"], {"pasture": 0.65, "verge": 0.35}, []], "a rule of its own, with the settings it had")
	var j := r.new_rule_from("Mud")
	assert_eq([r.rules[j]["density"], r.rules[j]["species"]], [1.0, {"verge": 0.6, "pasture": 0.4}],
		"from Everything else: its settings")
	assert_true(r.rules[j]["colour"] != r.rules[i]["colour"], "each new rule takes the next colour")
	r.delete_rule(1)
	assert_eq(r.rule_of("Susuki Grass"), -1, "deleting a rule sends its surfaces to Everything else")
	r.set_field(0, "density", 2.0)
	r.set_field(-1, "default_grass", false)
	assert_eq([r.rules[0]["density"], r.everything_else["default_grass"]], [1.0, false], "fields; the density clamped")
	assert_true(r.set_weight(0, "susuki", 0.2) and r.rules[0]["species"].has("susuki"), "a species added")
	for sp in ["chigaya", "isogiku", "sedge"]:
		r.set_weight(0, sp, 0.1)
	assert_true(not r.set_weight(0, "tsuwabuki", 0.1), "a seventh species is refused")
	r.set_weight(0, "susuki", 0.0)
	assert_true(not r.rules[0]["species"].has("susuki"), "0 removes it")
	r.set_band(0, 500.0)
	assert_eq([r.rules[0]["band"]["above_m"], r.rules[0]["band"]["species"]], [500.0, r.rules[0]["species"]],
		"a band, starting from the rule's own mix")
	r.set_band(0, -1.0)
	assert_true((r.rules[0]["band"] as Dictionary).is_empty(), "a negative height removes it")
	r.set_season("susuki", "stage", 0.8)
	r.set_season("freesia", "calendar")
	r.set_map_date(104.0)
	assert_eq([r.season_of("susuki"), r.seasons.has("freesia"), r.map_date], [{"mode": "stage", "stage": 0.8}, false, 104.0],
		"seasons and the map's date")
	assert_eq(r.unassigned(PackedStringArray(["Pasture", "Mud", "Town Ground", "Rock"])),
		PackedStringArray(["Town Ground", "Rock"]), "the map's surfaces in no rule")
	assert_eq(r.missing(PackedStringArray(["Pasture"])), PackedStringArray(["Asphalt", "Mud"]),
		"rule surfaces this map does not have")


func test_snapshots_and_species() -> void:
	var r := _sample()
	var s := r.snapshot()
	r.move_surface("Pasture", -1)
	r.default_grass = false
	r.restore(s)
	assert_eq([r.rule_of("Pasture"), r.default_grass], [0, true], "a snapshot restores the rules")
	r.move_surface("Pasture", -1)
	assert_eq(s["rules"][0]["surfaces"], ["Pasture", "Town Ground"], "a snapshot is a deep copy")
	var used := r.species_used()
	used.sort()
	assert_eq(used, PackedStringArray(["chigaya", "pasture", "summit", "susuki", "verge"]),
		"the species the map can grow: every mix and band, and Everything else's")


## Start from defaults: surfaces with the same allowance, species and band share a rule ("A +1"); a surface
## the table does not list stays in Everything else, which takes the table's default and default_species.
func test_the_converter_groups() -> void:
	var doc := {"default": 0.5, "default_species": {"verge": 1.0}, "slots": {"A": 1.0, "b": 1.0,
		"C": {"density": 0.3, "species": {"fern": 2.0, "sedge": 1.0}}, "E": {"density": 0.3, "species": {"sedge": 1.0, "fern": 2.0}}}}
	var r := GrassGroundRules.from_growth_table(doc, PackedStringArray(["A", "B", "C", "D", "E"]))
	assert_eq(r.rules.map(func(x): return [x["name"], x["surfaces"]]), [["A +1", ["A", "B"]], ["C", ["C"]], ["E", ["E"]]],
		"A and B share a rule; C and E do not (their mixes are written in another order: another pick order)")
	assert_eq(r.rules[1]["species"], {"fern": 2.0, "sedge": 1.0}, "the weights as written (raw)")
	assert_eq([r.rule_of("D"), r.everything_else["density"], r.everything_else["species"]], [-1, 0.5, {"verge": 1.0}],
		"D is unlisted: Everything else, with the table's default")


## A growth table from rules: a rule's surfaces get its density, mix and band; an empty mix is Everything
## else's; a rule whose own grass is off (or all of them, with the master switch off) is painted only, which
## table_for writes as -a.
func test_from_rules() -> void:
	var r := _sample()
	var g := GrassTerrainGrowth.from_rules(r)
	assert_eq(g.errors, PackedStringArray(), "no errors")
	assert_near(g.allowance("Susuki Grass"), 0.8, 1e-6, "a rule's density")
	assert_near(float(g.mix_for("Pasture", 0.0)["pasture"]), 0.65, 1e-6, "its mix, normalised")
	assert_eq(g.mix_for("Susuki Grass", 800.0).keys(), ["summit", "susuki"], "its band above 700 m")
	assert_eq(g.mix_for("Asphalt", 0.0), g.default_species, "an empty mix: Everything else's")
	assert_true(g.painted_only.has("susuki grass") and not g.painted_only.has("pasture") and not g.painted_only_rest,
		"Susuki slopes grows only what is painted")
	var assets := _assets(["Pasture", "Susuki Grass", "Mud"])
	var t := g.table_for(assets)          # float32: compare near
	assert_true(is_equal_approx(t[0], 1.0) and is_equal_approx(t[1], -0.8) and is_equal_approx(t[2], 1.0),
		"the table: painted only is negated; Mud gets Everything else (%s)" % [t.slice(0, 3)])
	r.default_grass = false
	var off := GrassTerrainGrowth.from_rules(r).table_for(assets)
	assert_true(is_equal_approx(off[0], -1.0) and is_equal_approx(off[1], -0.8) and is_equal_approx(off[2], -1.0),
		"the master switch off: everything painted only (%s)" % [off.slice(0, 3)])
	var zero := GrassGroundRules.from_text(JSON.stringify(SAMPLE))
	zero.set_field(2, "default_grass", false)
	var tz := GrassTerrainGrowth.from_rules(zero).table_for(_assets(["Asphalt"]))
	assert_eq(tz[0], 0.0, "a rule that grows nothing stays 0, painted only or not")


## The shared growth table says it too: a slot with "painted_only": true grows nothing of its own, and what is painted
## there grows at its density (a fallow bulb bed): table_for negates it as for a rule whose own grass is off.
func test_the_growth_table_painted_only() -> void:
	var g := GrassTerrainGrowth.from_json_text(JSON.stringify({"default": 1.0, "slots": {
		"Fallow": {"density": 0.8, "painted_only": true}, "Lawn": 1.0, "Bed": {"density": 1.0, "painted_only": false}}}))
	assert_eq(g.errors, PackedStringArray(), "no errors")
	assert_true(g.painted_only.has("fallow") and not g.painted_only.has("lawn") and not g.painted_only.has("bed")
		and not g.painted_only_rest, "Fallow alone is painted only")
	var t := g.table_for(_assets(["Lawn", "Fallow", "Bed"]))
	assert_true(is_equal_approx(t[0], 1.0) and is_equal_approx(t[1], -0.8) and is_equal_approx(t[2], 1.0),
		"its allowance negated (%s)" % [t.slice(0, 3)])
	g._load_text(JSON.stringify({"slots": {"Lawn": 1.0}}))
	assert_true(g.painted_only.is_empty(), "a reload forgets it")
	var r := GrassGroundRules.from_growth_table({"slots": {"Fallow": {"density": 0.8, "painted_only": true},
		"Bed": {"density": 0.8}}}, PackedStringArray(["Fallow", "Bed"]))
	assert_eq(r.rules.map(func(x): return [x["surfaces"], x["default_grass"]]), [[["Fallow"], false], [["Bed"], true]],
		"Start from defaults keeps it: its own rule, its own grass off (not grouped with a same-density bed)")
	assert_true(GrassTerrainGrowth.from_rules(r).painted_only.has("fallow"), "and the rules grow the same")


func _assets(names: Array) -> Resource:
	var a: Resource = ClassDB.instantiate("Terrain3DAssets")
	for i in names.size():
		var ta: Resource = ClassDB.instantiate("Terrain3DTextureAsset")
		ta.set("name", names[i])
		a.call("set_texture_asset", i, ta)
	return a


## The blades find their map's rules: <grounds_dir>/<the scene they are saved in>.json, the node's own path
## winning; no scene (a test world) or no file: the shared table. reload_rules() re-reads the file.
func test_the_blades_load_the_maps_rules() -> void:
	assert_eq(GrassBlades.rules_path_for("res://maps/isle.scn", "res://data/grounds", ""), "res://data/grounds/isle.json",
		"<grounds_dir>/<map>.json")
	assert_eq(GrassBlades.rules_path_for("res://maps/isle.scn", "res://data/grounds", "res://x.json"), "res://x.json",
		"the node's path wins")
	assert_eq(GrassBlades.rules_path_for("", "res://data/grounds", ""), "", "no scene (a test world): none")
	var path := OS.get_temp_dir().path_join("grass_rules_%d.json" % Time.get_ticks_usec())
	var r := _sample()
	r.default_grass = false
	assert_eq(r.save_file(path), OK, "written")
	var b := GrassBlades.new()
	b.ground_rules_path = path
	b.reload_rules()
	assert_true(b.rules != null and b.growth.painted_only_rest and b.growth.painted_only.has("pasture"),
		"the file reaches the growth table (the master switch off)")
	r.set_map_date(104.0)
	r.save_file(path)
	b.reload_rules()
	assert_near(b.season.map_date, 104.0, 1e-6, "the season plan comes with the rules")
	DirAccess.remove_absolute(path)
	b.reload_rules()
	assert_true(b.rules == null and not b.growth.painted_only_rest, "the file gone: the shared table")
	b.free()
