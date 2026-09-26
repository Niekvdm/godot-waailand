# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
class_name TestGrassWaterGrowth
extends GrassSuite
## The growth table's water section: each water kind's density and floating mix, in the table's order (the kind's
## index); a water mix names surface species only, a ground mix ground species only; the kernels' table; a map's
## ground rules carry water kinds the same way.

const TABLE := {"slots": {"A": 1.0}, "water": {
	"Vijver": {"density": 0.4, "species": {"t_lily": 0.6, "t_duck": 0.4}},
	"Sloot": {"density": 0.8, "species": {"t_duck": 1.0}},
	"Zee": {"density": 0.0}}}


static func run() -> Dictionary:
	var keep := use_water_fixture()
	var r := await GrassSuite.run_suite(TestGrassWaterGrowth.new(), "grass_water_growth")
	GrassBladesConfig.use(keep)
	return r


## The fixture species (GrassSuite.use_fixture_species) and two surface species, t_lily and t_duck, in a pack of their
## own: the water suites' config. Returns the config it replaced.
static func use_water_fixture(extra: Array[GrassSpecies] = []) -> GrassBladesConfig:
	var keep := GrassSuite.use_fixture_species()
	var cfg := GrassBladesConfig.current().duplicate() as GrassBladesConfig
	var lily := GrassSpecies.new()
	lily.id = &"t_lily"
	lily.layer = GrassSpecies.Layer.SURFACE
	lily.host_only = true
	lily.density = 0.0
	var duck := GrassSpecies.new()
	duck.id = &"t_duck"
	duck.layer = GrassSpecies.Layer.SURFACE
	var pack := GrassSpeciesPack.new()
	pack.name = "water fixture"
	pack.species.assign([lily, duck] + extra)
	var packs := cfg.packs.duplicate()
	packs.append(pack)
	cfg.packs = packs
	cfg.slots_path = ""
	GrassBladesConfig.use(cfg)
	return keep


func test_the_section() -> void:
	var g := GrassTerrainGrowth.from_json_text(JSON.stringify(TABLE, "", false))
	assert_true(g.errors.is_empty(), "no errors: %s" % [g.errors])
	assert_eq(g.water_names, PackedStringArray(["Vijver", "Sloot", "Zee"]), "in the table's order")
	assert_eq(g.water_index(), {"vijver": 0, "sloot": 1, "zee": 2}, "the index by lower-case name")
	assert_near(float(g.water_mix("VIJVER")["density"]), 0.4, 1e-6, "by name, any case")
	assert_eq((g.water_mix("Zee")["species"] as Dictionary), {}, "a kind with no species floats nothing")
	assert_near(float(g.water_mix("Nowhere")["density"]), 0.0, 1e-6, "a kind the table lacks: nothing")


func test_layers_are_checked() -> void:
	var t := {"slots": {"A": {"density": 1.0, "species": {"t_lily": 1.0}}},
		"water": {"Vijver": {"density": 1.0, "species": {"pasture": 1.0}}}}
	var g := GrassTerrainGrowth.from_json_text(JSON.stringify(t))
	assert_eq(g.errors.size(), 2, "both wrong: %s" % [g.errors])
	assert_true(g.errors[0].contains("t_lily") and g.errors[0].contains("floats"), "a surface species on ground")
	assert_true(g.errors[1].contains("pasture") and g.errors[1].contains("ground"), "a ground species on water")


func test_the_kernel_table() -> void:
	var g := GrassTerrainGrowth.from_json_text(JSON.stringify(TABLE, "", false))
	var types := GrassTypes.new()
	var f := g.water_bytes(types).to_float32_array()
	assert_eq(f.size(), GrassTerrainGrowth.WATER_KINDS * GrassTerrainGrowth.WATER_VEC4 * 4, "16 kinds x 4 vec4")
	var lily := types.names().find("t_lily")
	var duck := types.names().find("t_duck")
	assert_true(lily >= 0 and duck >= 0, "the fixture's surface species have slots")
	assert_eq(int(f[0]), lily, "Vijver's first pair: the lily")
	assert_near(f[1], 0.6, 1e-6, "at 0.6")
	assert_eq(int(f[2]), duck, "then the duckweed")
	assert_near(f[3], 1.0, 1e-6, "to 1")
	assert_near(f[12], 0.4, 1e-6, "Vijver's density")
	assert_near(f[16 + 12], 0.8, 1e-6, "Sloot's density")
	assert_eq(int(f[32]), -1, "Zee: no pair")
	assert_eq(int(f[3 * 16]), -1, "an unused kind: no pair")


func test_ground_rules_water_kinds() -> void:
	var r := GrassGroundRules.new()
	var i := r.add_water("Vijver")
	r.set_field(i, "density", 0.5)
	assert_true(r.set_weight(i, "t_lily", 1.0), "a surface species goes in")
	assert_true(r.is_water(i), "a water kind")
	assert_true(not r.set_weight(i, "t_lily", 1.0, true), "a water kind has no band")
	var back := GrassGroundRules.from_text(r.to_text())
	assert_true(back.errors.is_empty(), "round trip: %s" % [back.errors])
	assert_true(back.is_water(0), "still water")
	assert_true(r.to_text().contains("\"water\":true") and not r.to_text().contains("\"surfaces\":[]"),
		"written as water, without surfaces")
	var g := GrassTerrainGrowth.from_rules(back)
	assert_true(g.errors.is_empty(), "no errors: %s" % [g.errors])
	assert_eq(g.water_names, PackedStringArray(["Vijver"]), "the growth table has it")
	assert_near(float(g.water_mix("Vijver")["density"]), 0.5, 1e-6, "its density")
	assert_true(back.unassigned(PackedStringArray(["A"])).has("A"), "a water kind claims no surface")
	var bad := GrassGroundRules.from_text(JSON.stringify({"format": GrassGroundRules.FORMAT, "rules": [
		{"name": "Vijver", "water": true, "density": 1.0, "species": {"pasture": 1.0}}]}))
	assert_true(bad.errors.size() == 1 and bad.errors[0].contains("pasture"), "a ground species cannot float")


func test_from_growth_table() -> void:
	var r := GrassGroundRules.from_growth_table(TABLE, PackedStringArray(["A"]))
	var waters := PackedStringArray()
	for i in r.rules.size():
		if r.is_water(i):
			waters.append(String(r.rules[i]["name"]))
	assert_eq(waters, PackedStringArray(["Vijver", "Sloot", "Zee"]), "the table's water kinds become water rules")
