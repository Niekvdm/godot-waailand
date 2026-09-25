# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
class_name TestGrassStarterPack
extends GrassSuite
## The addon's starter pack: five temperate species, meadow the fallback,
## meadow 0.6 and lawn 0.4 the default mix, tall grass with seed plumes and daisies with flowers; it builds clean, and
## its pictures are all there and current.

const PACK := "res://addons/waailand/packs/starter/starter.tres"


static func run() -> Dictionary:
	return await GrassSuite.run_suite(TestGrassStarterPack.new(), "grass_starter_pack")


func test_the_starter_pack() -> void:
	var pack := load(PACK) as GrassSpeciesPack
	assert_true(pack != null, "it loads")
	if pack == null:
		return
	var c := GrassSpeciesCatalog.build([pack], {})
	assert_eq(c.errors, PackedStringArray(), "it builds clean")
	assert_eq(c.species.map(func(s): return String(s.id)), ["lawn", "meadow", "tall_grass", "tufts", "daisies"],
		"five species")
	assert_eq([c.fallback, c.default_mix], [&"meadow", {"meadow": 0.6, "lawn": 0.4}], "meadow the fallback; the mix")
	var t := GrassTypes.from_catalog(c)
	var k := DecoKinds.from_catalog(c, t)
	assert_true(t.errors.is_empty() and k.errors.is_empty() and k.kinds.map(func(x): return x["name"])
		== ["tall_grass_plume", "daisy"], "tall grass's plumes, the daisies' flowers")
	assert_eq(GrassPictureTool.stale_of(pack), PackedStringArray(), "every picture there and current")
