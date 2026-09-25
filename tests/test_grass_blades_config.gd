# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
class_name TestGrassBladesConfig
extends GrassSuite
## GrassBladesConfig: the project's config resource, or an empty
## one when there is none, loaded once; the catalogs and the bake read their paths from it; the packs in use.

const PACK_ROOT := "res://addons/waailand/tests/fixtures/pack_addons"


static func run() -> Dictionary:
	return await GrassSuite.run_suite(TestGrassBladesConfig.new(), "grass_blades_config")


func test_a_missing_config_is_empty_and_loaded_once() -> void:
	var keep := GrassBladesConfig.current()
	var had := ProjectSettings.has_setting(GrassBladesConfig.SETTING)
	var old = ProjectSettings.get_setting(GrassBladesConfig.SETTING) if had else null
	ProjectSettings.set_setting(GrassBladesConfig.SETTING, "res://no_such_grass_config.tres")
	GrassBladesConfig.use(null)
	var c := GrassBladesConfig.current()
	assert_true(c != null, "a config object even without the file")
	assert_true(c.runtime_inputs.is_empty() and c.editor_inputs.is_empty(), "no feeders")
	assert_true(c.packs.is_empty() and c.growth_path == "" and c.far_grain_dir == "", "no packs, no paths")
	assert_eq(c.slots_path, "", "the stand-in saves no slot table (a config that failed to load grows the starter pack)")
	assert_true(GrassBladesConfig.current() == c, "loaded once: the second call returns the same object")
	ProjectSettings.set_setting(GrassBladesConfig.SETTING, old)     # null erases it again
	GrassBladesConfig.use(keep)
	assert_true(GrassBladesConfig.current() == keep, "restored")


func test_the_catalogs_and_the_bake_follow_the_config() -> void:
	var keep := GrassBladesConfig.current()
	var c := GrassBladesConfig.new()
	var pack := GrassSpeciesPack.new()
	var sp := GrassSpecies.new()
	sp.id = &"x_meadow"
	pack.species.append(sp)
	c.packs.append(pack)
	c.slots_path = ""
	c.growth_path = "res://x_growth.json"
	c.far_grain_dir = "res://x_baked"
	GrassBladesConfig.use(c)
	assert_eq(GrassTypes.new().row(0)["name"], "x_meadow", "GrassTypes reads its species from the config's packs")
	assert_eq(GrassTerrainGrowth.catalog_path(), "res://x_growth.json", "GrassTerrainGrowth too")
	assert_eq(GrassFarGrain.dir(), "res://x_baked", "GrassFarGrain's bake directory too")
	var filled := 0
	for r in GrassTypes.new("").rows:
		filled += 0 if r.is_empty() else 1
	assert_eq(filled, 0, "an explicit empty path is still an empty catalog (every slot empty)")
	GrassBladesConfig.use(keep)


## Pack addons: each addon folder's set (waailand_packs.tres), sorted by folder; the config's packs first, each pack
## once; a set's packs in the set's own order; a whole set or one pack of it disabled; the starter pack only when
## nothing else is in use; the catalog grows what resolves.
func test_pack_addons_resolve() -> void:
	var keep := GrassBladesConfig.current()
	var sets := GrassBladesConfig.discovered_set_paths(PACK_ROOT)
	assert_eq(Array(sets), [PACK_ROOT + "/alpha/waailand_packs.tres", PACK_ROOT + "/beta/waailand_packs.tres"],
		"every folder's waailand_packs.tres, sorted; a folder without one is skipped")
	var c := GrassBladesConfig.new()
	var b := load(PACK_ROOT + "/beta/b.tres") as GrassSpeciesPack
	c.packs = [b] as Array[GrassSpeciesPack]
	assert_eq(_names(c.resolved_packs(PACK_ROOT)), ["B", "A2", "A1"],
		"the config's first, then each set's in its own order; a pack the config lists counts once")
	c.disabled_packs = PackedStringArray([PACK_ROOT + "/alpha/a1.tres"])
	assert_eq(_names(c.resolved_packs(PACK_ROOT)), ["B", "A2"], "one pack of a set disabled")
	c.packs = [] as Array[GrassSpeciesPack]
	c.disabled_packs = PackedStringArray([PACK_ROOT + "/alpha/waailand_packs.tres"])
	assert_eq(_names(c.resolved_packs(PACK_ROOT)), ["B"], "a whole set disabled")
	var e := GrassBladesConfig.new()
	var got := e.resolved_packs(PACK_ROOT + "/no_pack")
	assert_true(got.size() == 1 and got[0].resource_path == e.starter_pack_path(), "nothing else: the starter pack")
	e.disabled_packs = PackedStringArray([e.starter_pack_path()])
	assert_eq(e.resolved_packs(PACK_ROOT + "/no_pack").size(), 0, "the starter pack can be disabled too")
	var bare := GrassBladesConfig.new()
	bare.slots_path = ""
	bare.disabled_packs = GrassBladesConfig.discovered_set_paths()   # whatever pack addons this project has
	GrassBladesConfig.use(bare)
	var cat := GrassSpeciesCatalog.from_config()
	assert_true(cat.species.size() == 5 and cat.fallback == &"meadow", "a config with no packs grows the starter pack")
	GrassBladesConfig.use(keep)


func _names(p_packs: Array) -> Array:
	return p_packs.map(func(p): return p.name)
