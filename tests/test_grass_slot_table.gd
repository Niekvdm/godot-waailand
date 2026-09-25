# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
class_name TestGrassSlotTable
extends GrassSuite
## The project's slot table: the lowest free slot, in order; never reused; a
## species comes back on its slot; the cap; the file round trip.


static func run() -> Dictionary:
	return await GrassSuite.run_suite(TestGrassSlotTable.new(), "grass_slot_table")


func test_assign() -> void:
	var a := GrassSlotTable.assign({}, ["a", "b", "c"], 32)
	assert_true(a["table"] == {"a": 0, "b": 1, "c": 2} and a["grew"], "an empty table: 0, 1, 2 in order")
	a = GrassSlotTable.assign({"a": 0, "c": 2}, ["a", "b", "c", "d"], 32)
	assert_eq(a["table"], {"a": 0, "c": 2, "b": 1, "d": 3}, "the lowest free slots; the known keep theirs")
	a = GrassSlotTable.assign({"a": 0, "b": 1}, ["b"], 32)
	assert_true(a["table"] == {"a": 0, "b": 1} and not a["grew"], "a species that left keeps its slot (never reused)")
	a = GrassSlotTable.assign(a["table"], ["a", "b", "e"], 32)
	assert_eq(a["table"], {"a": 0, "b": 1, "e": 2}, "and one that comes back has it again")
	a = GrassSlotTable.assign({}, ["a", "b", "c"], 2)
	assert_eq(a["left_out"], PackedStringArray(["c"]), "past the cap: left out")


func test_the_file() -> void:
	var p := OS.get_temp_dir().path_join("grass_slots_%d.json" % Time.get_ticks_usec())
	assert_eq(GrassSlotTable.load_file(p), {}, "no file: an empty table")
	assert_eq(GrassSlotTable.save_file(p, {"verge": 1, "pasture": 0}), OK, "saved")
	assert_eq(GrassSlotTable.load_file(p), {"pasture": 0, "verge": 1}, "loaded back (in slot order)")
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string("{nope")
	f.close()
	assert_eq(GrassSlotTable.load_file(p), {}, "a broken file: an empty table (and an error)")
