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
