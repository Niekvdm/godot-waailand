# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
class_name TestGrassSpeciesCatalog
extends GrassSuite
## The species catalog: packs to one list, unique ids, the slot table, the
## fallback and the default mix (the pack's, overridden by the config), the documents GrassTypes and DecoKinds parse,
## the cap.


static func run() -> Dictionary:
	return await GrassSuite.run_suite(TestGrassSpeciesCatalog.new(), "grass_species_catalog")


static func _sp(p_id: String) -> GrassSpecies:
	var s := GrassSpecies.new()
	s.id = StringName(p_id)
	return s


static func _pack(p_name: String, ids: Array, fallback := &"", mix := {}) -> GrassSpeciesPack:
	var p := GrassSpeciesPack.new()
	p.name = p_name
	for i in ids:
		p.species.append(_sp(i))
	p.fallback_species = fallback
	p.default_mix = mix
	return p


func test_packs_slots_and_ids() -> void:
	var a := _pack("A", ["lawn", "meadow"], &"meadow", {"lawn": 1.0, "meadow": 3.0})
	var b := _pack("B", ["reed", "lawn"])
	var c := GrassSpeciesCatalog.build([a, b], {"reed": 5}, &"", {})
	assert_eq(c.species.map(func(s): return String(s.id)), ["lawn", "meadow", "reed"], "pack order, species order")
	assert_true(c.errors.size() == 1 and c.errors[0].contains("A") and c.errors[0].contains("B"),
		"a duplicate id: one error naming both packs (%s)" % [c.errors])
	assert_eq([c.slot_of(&"lawn"), c.slot_of(&"meadow"), c.slot_of(&"reed")], [0, 1, 5], "the table's slots, new ones lowest free")
	assert_true(c.grew, "the table grew")
	assert_eq([c.fallback, c.fallback_slot()], [&"meadow", 1], "the pack's fallback")
	assert_eq(c.default_mix, {"meadow": 0.75, "lawn": 0.25}, "its default mix, normalised")
	assert_eq(c.default_mix.keys(), ["meadow", "lawn"], "heaviest first: the pick order survives a resource file's sorted keys")


func test_overrides_and_defaults() -> void:
	var a := _pack("A", ["lawn", "meadow"], &"meadow", {"meadow": 1.0})
	var c := GrassSpeciesCatalog.build([a], {}, &"lawn", {"lawn": 1.0, "gone": 1.0})
	assert_eq([c.fallback, c.default_mix], [&"lawn", {"lawn": 1.0}], "the config overrides; an unknown id is dropped")
	assert_true(c.errors.size() == 1 and c.errors[0].contains("gone"), "with an error (%s)" % [c.errors])
	var bare := GrassSpeciesCatalog.build([_pack("B", ["x", "y"])], {})
	assert_eq([bare.fallback, bare.default_mix], [&"x", {"x": 1.0}], "none set: the first species, alone")


func test_the_documents() -> void:
	var s := _sp("meadow")
	var d := GrassDecoration.new()
	d.name = &"daisy"
	d.mesh_builder = IsogikuMeshBuilder.new()
	s.decorations.append(d)
	var kept := GrassDecoration.new()
	kept.name = &"old"
	kept.salt = 132
	kept.mesh_builder = SpikeMeshBuilder.new()
	s.decorations.append(kept)
	var p := GrassSpeciesPack.new()
	p.species.append(s)
	var c := GrassSpeciesCatalog.build([p], {"meadow": 4})
	var t := GrassTypes.from_catalog(c)
	assert_true(t.row(4)["name"] == "meadow" and t.fallback_slot == 4, "the rows on their slots; the fallback slot")
	var k := DecoKinds.from_catalog(c, t)
	assert_eq(k.kinds.map(func(x): return [x["name"], x["host"]]), [["daisy", 4], ["old", 4]], "the kinds, hosted by slot")
	assert_eq([k.kinds[0]["salt"], k.kinds[1]["salt"]], [float(100 + 16 * (String("daisy").hash() & 0xFFFF)), 132.0],
		"a new decoration's salt from its name; a converted one keeps its own")


func test_the_cap() -> void:
	var ids := []
	for i in 33:
		ids.append("s%d" % i)
	var c := GrassSpeciesCatalog.build([_pack("Big", ids)], {})
	assert_true(c.species.size() == 32 and c.errors.size() == 1 and c.errors[0].contains("s32"),
		"33 species: 32 in use, one error naming the one left out (%s)" % [c.errors])


## The active set (build_active): the table's species found among the installed packs, on their slots, in the packs'
## order; the rest installed but not active; a table id no pack has is missing; nothing is assigned. The fallback: the
## table's (or the config's) when active, else the first pack's that is active, else the first active species; a pack's
## default mix keeps its active names.
func test_the_active_set() -> void:
	var a := _pack("A", ["lawn", "meadow"], &"meadow", {"lawn": 1.0, "meadow": 1.0})
	var b := _pack("B", ["reed", "fern"])
	var c := GrassSpeciesCatalog.build_active([a, b], {"reed": 7, "lawn": 2, "gone": 5})
	assert_eq(c.species.map(func(s): return String(s.id)), ["lawn", "reed"], "only the table's, in the packs' order")
	assert_eq([c.slot_of(&"lawn"), c.slot_of(&"reed"), c.slot_of(&"meadow")], [2, 7, -1],
		"on their slots; meadow is installed, not active")
	assert_true(not c.grew, "nothing assigned")
	assert_eq(Array(c.missing), ["gone"], "a species no pack has is missing")
	assert_true(c.errors.size() == 1 and c.errors[0].contains("gone") and c.errors[0].contains("5"),
		"with one error naming it and its slot (%s)" % [c.errors])
	assert_eq(c.fallback, &"lawn", "the pack's fallback is not active: the first active species")
	assert_eq(c.default_mix, {"lawn": 1.0}, "the pack's default mix, its active names")
	var d := GrassSpeciesCatalog.build_active([a, b], {"lawn": 0, "meadow": 1}, &"meadow")
	assert_eq([d.fallback, d.errors.size()], [&"meadow", 0], "the table's fallback")
	var e := GrassSpeciesCatalog.build_active([a, b], {"lawn": 0}, &"reed")
	assert_true(e.fallback == &"lawn" and e.errors.size() == 1 and e.errors[0].contains("reed"),
		"a fallback that is not active: an error, the first active species (%s)" % [e.errors])


## from_config: a table file is the active set; no file yet: the starter grass (written by the editor only); no
## slots_path (tools, tests): every pack's species on the lowest slots.
func test_from_config_reads_the_table() -> void:
	var keep := GrassBladesConfig.current()
	var cfg := GrassBladesConfig.new()
	cfg.packs.assign([_pack("A", ["lawn", "meadow"], &"meadow"), _pack("B", ["reed"])])
	cfg.disabled_packs = GrassBladesConfig.discovered_set_paths()
	var p := "user://test_species_catalog_slots.json"
	GrassSlotTable.save_file(p, {"reed": 4, "meadow": 0}, &"reed")
	cfg.slots_path = p
	GrassBladesConfig.use(cfg)
	var c := GrassSpeciesCatalog.from_config()
	assert_eq(c.species.map(func(s): return String(s.id)), ["meadow", "reed"], "the table's species")
	assert_eq([c.slot_of(&"reed"), c.fallback], [4, &"reed"], "its slots and its fallback")
	DirAccess.remove_absolute(p)
	var fresh := "user://test_species_catalog_none.json"
	cfg.slots_path = fresh
	var f := GrassSpeciesCatalog.from_config()
	assert_eq(f.species.map(func(s): return String(s.id)), ["lawn", "meadow", "tall_grass", "tufts", "daisies"],
		"no table yet: the starter grass")
	assert_true(not FileAccess.file_exists(fresh), "a game (not the editor) does not write it")
	cfg.slots_path = ""
	assert_eq(GrassSpeciesCatalog.from_config().species.size(), 3, "no slots_path: every pack's species")
	GrassBladesConfig.use(keep)


func test_no_active_species() -> void:
	var t := GrassTypes.from_catalog(GrassSpeciesCatalog.build_active([_pack("A", ["lawn"])], {}))
	assert_eq(float(t.row(0).get("density", -1.0)), 0.0, "an empty set: every slot reads a row that grows nothing")
	assert_eq(t.to_bytes().size(), GrassTypes.SLOTS * GrassTypes.VEC4 * 16, "and the tables still pack")
