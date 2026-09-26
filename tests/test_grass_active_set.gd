# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
class_name TestGrassActiveSet
extends GrassSuite
## The active species (GrassActiveSet), what the Species dialog edits: 32 slots of installed species, the flower kinds
## they bring (32), the fallback; placing, replacing, filling a pack all or nothing, emptying; the refusals say what is
## needed and what is free; a species no pack has any more is missing; the slot table round trip, fallback included.


static func run() -> Dictionary:
	return await GrassSuite.run_suite(TestGrassActiveSet.new(), "grass_active_set")


## A species with `kinds` decorations.
static func _sp(id: String, kinds := 0, extra := {}) -> GrassSpecies:
	var s := GrassSpecies.new()
	s.id = StringName(id)
	for i in kinds:
		var d := GrassDecoration.new()
		d.name = StringName("%s_%d" % [id, i])
		s.decorations.append(d)
	for k in extra:
		s.set(k, extra[k])
	return s


static func _installed() -> Array:
	var out := [_sp("lawn", 1), _sp("meadow", 2), _sp("reed", 0, {"wet_depth_m": 0.4}),
		_sp("weed", 0, {"depth_m": Vector2(0.3, 3.0)}), _sp("lily", 2, {"layer": GrassSpecies.Layer.SURFACE}),
		_sp("tulips", 11)]
	for i in 40:
		out.append(_sp("g%02d" % i))
	return out


func test_place_add_and_the_counts() -> void:
	var a := GrassActiveSet.new(_installed())
	assert_eq(a.used_slots(), 0, "nothing active: installed species take no slot")
	assert_eq(a.place(&"lawn", 3), "", "lawn into slot 3")
	assert_eq(a.slot_of(&"lawn"), 3, "there")
	assert_eq(a.place(&"meadow"), "", "meadow into the first free slot")
	assert_eq(a.slot_of(&"meadow"), 0, "slot 0")
	assert_eq([a.used_slots(), a.used_kinds()], [2, 3], "2 species, 3 flower kinds")
	assert_true(a.place(&"lawn", 5).contains("already active in slot 3"), "a species is active once")
	assert_true(a.place(&"reed", 3).contains("Slot 3 holds lawn"), "a taken slot is not overwritten by place")
	assert_true(a.place(&"nothere").contains("not installed"), "only installed species")
	a.place(&"reed")
	a.place(&"weed")
	a.place(&"lily")
	assert_eq(a.layer_counts(), {"ground": 3, "under": 1, "float": 1}, "wet ground counts as ground")
	assert_eq([GrassActiveSet.layer_of(a.species(&"reed")), GrassActiveSet.layer_of(a.species(&"weed")),
		GrassActiveSet.layer_of(a.species(&"lily")), GrassActiveSet.layer_of(a.species(&"lawn"))],
		["wet", "under", "float", "ground"], "each species' layer")


func test_the_budgets() -> void:
	var a := GrassActiveSet.new(_installed())
	for i in 32:
		a.place(StringName("g%02d" % i))
	assert_eq(a.used_slots(), 32, "all 32 slots")
	var no := a.place(&"g33")
	assert_true(no.contains("No free slot"), "the 33rd is refused: %s" % no)
	var d := GrassActiveSet.new(_installed() + [_sp("more", 20)])
	d.place(&"tulips")
	d.place(&"meadow")
	assert_eq(d.used_kinds(), 13, "13 kinds")
	var k := d.place(&"more")
	assert_true(k.contains("20 flower kinds") and k.contains("19 of 32 are free"),
		"past 32 kinds: refused, with what it brings and what is free (%s)" % k)
	assert_eq(d.slot_of(&"more"), -1, "and not placed")
	assert_eq(d.replace(d.slot_of(&"tulips"), &"more"), "", "in place of the tulips it fits (2 + 20)")


func test_replace_empty_and_fallback() -> void:
	var a := GrassActiveSet.new(_installed())
	a.place(&"lawn", 2)
	a.place(&"meadow", 3)
	assert_eq(a.set_fallback(&"lawn"), "", "an active species is the fallback")
	assert_true(a.set_fallback(&"reed").contains("not active"), "an inactive one cannot be")
	assert_eq(a.replace(2, &"reed"), "", "reed replaces lawn in slot 2")
	assert_eq([a.slot_of(&"reed"), a.slot_of(&"lawn")], [2, -1], "reed in, lawn out")
	assert_eq(a.fallback, &"", "the fallback went with it")
	assert_true(a.replace(5, &"weed").contains("empty"), "replace takes a filled slot")
	a.set_fallback(&"meadow")
	a.empty(3)
	assert_eq([a.slot_of(&"meadow"), a.fallback], [-1, &""], "emptied, and not the fallback any more")


func test_fill_all_or_nothing() -> void:
	var a := GrassActiveSet.new(_installed())
	for i in 29:
		a.place(StringName("g%02d" % i))
	var no := a.fill([&"lawn", &"meadow", &"reed", &"weed"], "Pond")
	assert_true(no.contains("Pond doesn't fit") and no.contains("4 slots") and no.contains("3 slots"),
		"four species into three free slots: refused, saying so (%s)" % no)
	assert_eq(a.slot_of(&"lawn"), -1, "and nothing placed")
	assert_eq(a.fill([&"lawn", &"meadow", &"g00"], "Pond"), "", "the inactive ones fit")
	assert_eq([a.slot_of(&"lawn"), a.slot_of(&"meadow"), a.used_slots()], [29, 30, 31], "in order, the active one skipped")


func test_missing_and_the_table() -> void:
	var a := GrassActiveSet.new(_installed(), {"lawn": 0, "gone": 4, "meadow": 7}, &"meadow")
	assert_true(a.is_missing(4) and not a.is_missing(0), "a species no pack has is missing")
	assert_eq(a.used_slots(), 3, "it still holds its slot")
	assert_eq(a.used_kinds(), 3, "and brings no kinds")
	assert_eq(a.to_table(), {"lawn": 0, "gone": 4, "meadow": 7}, "the table as it was")
	a.empty(4)
	assert_eq(a.to_table(), {"lawn": 0, "meadow": 7}, "emptied")
	var snap := a.snapshot()
	a.place(&"reed")
	a.restore(snap)
	assert_eq([a.slot_of(&"reed"), a.fallback], [-1, &"meadow"], "snapshot and restore (the dialog's undo)")
	var dir := "user://test_grass_active_set"
	DirAccess.make_dir_recursive_absolute(dir)
	var p := dir.path_join("slots.json")
	assert_eq(GrassSlotTable.save_file(p, a.to_table(), a.fallback), OK, "written")
	assert_eq([GrassSlotTable.load_file(p), GrassSlotTable.load_fallback(p)], [{"lawn": 0, "meadow": 7}, &"meadow"],
		"read back, the fallback too")
	assert_eq(GrassSlotTable.save_file(p, {"lawn": 0}), OK, "without a fallback")
	assert_eq(GrassSlotTable.load_fallback(p), &"", "none")
	DirAccess.remove_absolute(p)
