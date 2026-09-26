# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
class_name TestGrassSpeciesReload
extends GrassSuite
## The active set changed (the Species dialog): the grass and the Grass panel take the new species at once. GrassBlades
## builds its type rows, flowers and colours again from the config's catalog, and reads its growth again (a name grows
## only while active); a GrassBlades built on an older set (a background scene tab) takes the new one when it is ready
## again; the panel's library follows, the bar is told, each layer's selection stays when its species is still active.


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


## A slot table of `table` among r_lawn and r_reed, and a growth table growing r_reed on X.
func _table_config(table: Dictionary, slots: String, growth: String) -> GrassBladesConfig:
	var cfg := _config(["r_lawn", "r_reed"])
	GrassSlotTable.save_file(slots, table)
	cfg.slots_path = slots
	cfg.growth_path = growth
	cfg.disabled_packs = cfg.disabled_packs + PackedStringArray([cfg.starter_pack_path()])
	return cfg


func test_the_growth_and_a_background_tab() -> void:
	var keep := GrassBladesConfig.current()
	var slots := "user://test_grass_species_reload_slots.json"
	var growth := "user://test_grass_species_reload_growth.json"
	var f := FileAccess.open(growth, FileAccess.WRITE)
	f.store_string(JSON.stringify({"slots": {"X": {"density": 1.0, "species": {"r_reed": 1.0}}}}))
	f.close()
	GrassBladesConfig.use(_table_config({"r_lawn": 0}, slots, growth))
	var b := GrassBlades.new()
	assert_eq(b.growth.mix_for("X", 0.0), {}, "r_reed installed, not active: X grows nothing")
	GrassBladesConfig.use(_table_config({"r_lawn": 0, "r_reed": 1}, slots, growth))
	b.reload_species()
	assert_eq(b.growth.mix_for("X", 0.0), {"r_reed": 1.0}, "made active: the growth grows it")
	GrassBladesConfig.use(_table_config({"r_reed": 1}, slots, growth))
	GrassSpeciesCatalog.generation += 1
	b._ready()                    # a background tab back in the tree (no terrain here: it stops after the species)
	assert_true(not b.types.names().has("r_lawn") and b.types.names().has("r_reed"), "an older set is taken again when ready")
	b.free()
	DirAccess.remove_absolute(slots)
	DirAccess.remove_absolute(growth)
	GrassBladesConfig.use(keep)
