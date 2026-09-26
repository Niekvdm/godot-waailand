# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
class_name TestGrassSpeciesReload
extends GrassSuite
## The active set changed (the Species dialog): the grass and the Grass panel take the new species at once. GrassBlades
## builds its type rows, flowers and colours again from the config's catalog; the panel's library follows, the bar is
## told, each layer's selection stays when its species is still active.


static func run() -> Dictionary:
	return await GrassSuite.run_suite(TestGrassSpeciesReload.new(), "grass_species_reload")


static func _config(ids: Array, flowers := {}) -> GrassBladesConfig:
	var pack := GrassSpeciesPack.new()
	pack.name = "reload fixture"
	for id in ids:
		var sp := GrassSpecies.new()
		sp.id = StringName(id)
		for i in int(flowers.get(id, 0)):
			var d := GrassDecoration.new()
			d.name = StringName("%s_flower_%d" % [id, i])
			d.mesh_builder = IsogikuMeshBuilder.new()
			sp.decorations.append(d)
		pack.species.append(sp)
	var cfg := GrassBladesConfig.new()
	cfg.packs.assign([pack])
	cfg.slots_path = ""
	cfg.disabled_packs = GrassBladesConfig.discovered_set_paths()
	return cfg


func test_the_grass_reloads() -> void:
	var keep := GrassBladesConfig.current()
	GrassBladesConfig.use(_config(["r_lawn", "r_meadow"]))
	var b := GrassBlades.new()
	assert_true(b.types.names().has("r_lawn"), "built from the config's catalog")
	var before := b.colour_texture()
	GrassBladesConfig.use(_config(["r_reed"], {"r_reed": 2}))
	b.reload_species()
	assert_true(b.types.names().has("r_reed") and not b.types.names().has("r_lawn"), "the new set's rows")
	assert_eq(b.decorations.kinds.kinds.size(), 2, "its flowers")
	assert_true(b.colour_texture() != before, "and its colours")
	b.free()
	GrassBladesConfig.use(keep)


func test_the_panel_reloads() -> void:
	var keep := GrassBladesConfig.current()
	GrassBladesConfig.use(_config(["r_lawn", "r_meadow"]))
	var p := GrassPaintProvider.new(GrassTypes.new())
	p.library_select(p.types.names().find("r_meadow"))
	var fired := [0]
	p.library_changed.connect(func() -> void: fired[0] += 1)
	GrassBladesConfig.use(_config(["r_reed", "r_meadow"]))
	p.reload_species()
	var names: Array = p.library()["items"].map(func(it): return String(it["name"]).to_lower())
	assert_true(names.has("r reed") and not names.has("r lawn"), "the library lists the new set (%s)" % [names])
	assert_eq(fired[0], 1, "the bar is told")
	assert_eq(p.types.row(p.library_selected())["name"], "r_meadow", "a species still active stays selected")
	GrassBladesConfig.use(keep)
