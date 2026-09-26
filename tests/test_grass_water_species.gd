# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
class_name TestGrassWaterSpecies
extends GrassSuite
## A species' layer and wet depth: the row carries them, GrassTypes parses them into its depth range, and the land
## rule's 0.3 m is the sea's shore (unchanged at the sea, none inland).


static func run() -> Dictionary:
	var keep := GrassSuite.use_fixture_species()
	var r := await GrassSuite.run_suite(TestGrassWaterSpecies.new(), "grass_water_species")
	GrassBladesConfig.use(keep)
	return r


## A row for GrassTypes: a default species' row with `extra` merged in.
static func _row(nm: String, slot: int, extra := {}) -> Dictionary:
	var sp := GrassSpecies.new()
	sp.id = StringName(nm)
	var r := sp.to_row_json(slot)
	r.merge(extra, true)
	return r


static func _types(rows: Array) -> GrassTypes:
	return GrassTypes.from_json_text(JSON.stringify({"types": rows}))


func test_the_row_carries_layer_and_wet_depth() -> void:
	var sp := GrassSpecies.new()
	sp.id = &"lily"
	sp.layer = GrassSpecies.Layer.SURFACE
	var r := sp.to_row_json(3)
	assert_eq(r.get("layer"), "surface", "a surface species says so")
	assert_true(not r.has("wet_depth_m"), "no wet depth unless set")
	var g := GrassSpecies.new()
	g.id = &"rice"
	g.wet_depth_m = 0.3
	var rg := g.to_row_json(4)
	assert_true(not rg.has("layer"), "a ground species writes no layer")
	assert_near(float(rg["wet_depth_m"]), 0.3, 1e-6, "the wet depth")


func test_parsing() -> void:
	var t := _types([_row("land", 0), _row("rice", 1, {"wet_depth_m": 0.3}), _row("reed", 2, {"wet_depth_m": 0.1}),
		_row("lily", 3, {"layer": "surface"})])
	assert_true(t.errors.is_empty(), "no errors: %s" % [t.errors])
	assert_true(not t.rows[0].has("layer"), "ground by default, and no key (a row is part of the pictures' stamps)")
	assert_eq(t.rows[0]["depth"], GrassTypes.LAND_DEPTH, "land")
	assert_eq(t.rows[1]["depth"], Vector3(-10000.0, 0.3, 0.3), "rice: to 0.3 m of water, thinning over 0.3 m")
	assert_eq(t.rows[2]["depth"], Vector3(-10000.0, 0.1, 0.1), "a shallow wet depth thins over itself")
	assert_eq(t.rows[3]["layer"], GrassTypes.LAYER_SURFACE, "surface")
	assert_eq(t.rows[3]["depth"], GrassTypes.SURFACE_DEPTH, "any water 5 cm deep")
	var d: Array = t.depth_table()
	assert_eq((d[3] as Vector4).w, 1.0, "the depth row's w is the layer")
	assert_eq((d[0] as Vector4).w, 0.0, "a ground row's w is 0")


func test_bad_rows() -> void:
	var t := _types([_row("a", 0, {"layer": "air"})])
	assert_true(t.errors.size() == 1 and t.errors[0].contains("layer"), "an unknown layer: %s" % [t.errors])
	t = _types([_row("b", 0, {"layer": "surface", "wet_depth_m": 0.3})])
	assert_true(t.errors.size() == 1 and t.errors[0].contains("wet_depth_m"), "wet depth on a surface species")
	t = _types([_row("c", 0, {"wet_depth_m": 0.3, "depth_m": [1.0, 5.0]})])
	assert_true(t.errors.size() == 1 and t.errors[0].contains("wet_depth_m"), "wet depth with depth_m")


## The sea's numbers are today's: land at least 0.3 m above the sea, thinning over the 0.3 m before.
func test_the_shore_keeps_the_sea() -> void:
	var land := {"depth": GrassTypes.LAND_DEPTH}
	assert_eq(GrassTypes.LAND_DEPTH, Vector3(-10000.0, -0.3, 0.3), "the land range is as it was")
	for d in [-2.0, -0.7, -0.6, -0.5, -0.45, -0.35, -0.3, -0.1, 0.0, 0.5]:
		var old := 0.0 if d > -0.3 else 1.0 - smoothstep(-0.6, -0.3, d)
		assert_near(GrassTypes.eligibility(land, d), old, 1e-6, "at the sea, %.2f m: as before" % d)


func test_inland_water_has_no_shore() -> void:
	var land := {"depth": GrassTypes.LAND_DEPTH}
	assert_near(GrassTypes.eligibility(land, -0.35, 0.0), 1.0, 1e-6, "0.35 m above a ditch: full grass")
	assert_near(GrassTypes.eligibility(land, -0.15, 0.0), 0.5, 1e-6, "0.15 m above: half")
	assert_near(GrassTypes.eligibility(land, 0.05, 0.0), 0.0, 1e-6, "in the water: none")
	var rice := {"depth": Vector3(-10000.0, 0.3, 0.3)}
	assert_true(GrassTypes.eligibility(rice, 0.2, 0.0) > 0.2, "rice in 0.2 m of water grows")
	assert_near(GrassTypes.eligibility(rice, 0.4, 0.0), 0.0, 1e-6, "rice in 0.4 m of water: none")
	assert_near(GrassTypes.eligibility(land, 0.2, 0.0), 0.0, 1e-6, "a land species in 0.2 m: none")
	var bed := {"depth": Vector3(0.2, 3.0, 0.1)}
	assert_near(GrassTypes.eligibility(bed, 1.0, 0.3), 1.0, 1e-6, "a closed range ignores the shore")


func test_the_palette_names_the_layer() -> void:
	var t := _types([_row("land", 0), _row("lily", 1, {"layer": "surface"})])
	var p := GrassPaintTool.palette(t)
	assert_eq(int(p[0]["layer"]), 0, "land: ground")
	assert_eq(int(p[1]["layer"]), 1, "lily: surface")
	assert_true(not bool(p[1]["sea"]), "a surface species is not a sea species")


func test_a_default_mix_takes_ground_species_only() -> void:
	var a := GrassSpecies.new()
	a.id = &"meadow"
	var b := GrassSpecies.new()
	b.id = &"lily"
	b.layer = GrassSpecies.Layer.SURFACE
	var pack := GrassSpeciesPack.new()
	pack.species.assign([a, b])
	var c := GrassSpeciesCatalog.build([pack], {}, &"", {"meadow": 0.5, "lily": 0.5})
	assert_true(c.errors.size() == 1 and c.errors[0].contains("lily"), "the surface species is refused: %s" % [c.errors])
	assert_eq(c.default_mix.keys(), ["meadow"], "the rest stays")
