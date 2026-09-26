# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
class_name TestGrassInactiveNames
extends GrassSuite
## Names of installed species that are not active (no slot): a growth table's mix skips them quietly and keeps the
## rest; a mix of none but them grows nothing (not the default mix); a map's ground rules keep them in the file (so a
## save does not lose them) and grow nothing of them; a name no pack installs is an error, as before.

const TABLE := {"slots": {
	"X": {"density": 1.0, "species": {"i_lawn": 0.5, "i_reed": 0.5}},
	"Y": {"density": 1.0, "species": {"i_reed": 1.0}},
	"Z": {"density": 1.0, "species": {"nope": 1.0}}}}

var _keep: GrassBladesConfig
var _path := "user://test_grass_inactive_names_slots.json"


static func run() -> Dictionary:
	var s := TestGrassInactiveNames.new()
	s._use()
	var r := await GrassSuite.run_suite(s, "grass_inactive_names")
	s._restore()
	return r


## i_lawn and i_meadow active, i_reed installed only.
func _use() -> void:
	_keep = GrassBladesConfig.current()
	var pack := GrassSpeciesPack.new()
	pack.name = "inactive fixture"
	for id in ["i_lawn", "i_meadow", "i_reed"]:
		var sp := GrassSpecies.new()
		sp.id = StringName(id)
		pack.species.append(sp)
	var cfg := GrassBladesConfig.new()
	cfg.packs.assign([pack])
	cfg.disabled_packs = GrassBladesConfig.discovered_set_paths() + PackedStringArray([cfg.starter_pack_path()])
	GrassSlotTable.save_file(_path, {"i_lawn": 0, "i_meadow": 1})
	cfg.slots_path = _path
	GrassBladesConfig.use(cfg)


func _restore() -> void:
	DirAccess.remove_absolute(_path)
	GrassBladesConfig.use(_keep)


func test_the_growth_table() -> void:
	var g := GrassTerrainGrowth.from_json_text(JSON.stringify(TABLE, "", false))
	assert_eq(g.errors.size(), 1, "one error: the name nothing installs (%s)" % [g.errors])
	assert_true(g.errors[0].contains("nope"), "that one")
	assert_eq(g.mix_for("X", 0.0), {"i_lawn": 1.0}, "the inactive name is skipped, the rest renormalised")
	assert_eq(g.mix_for("Y", 0.0), {}, "a mix of only inactive names grows nothing (not the default mix)")


func test_the_ground_rules() -> void:
	var r := GrassGroundRules.from_text(JSON.stringify({"format": GrassGroundRules.FORMAT, "rules": [
		{"name": "Meadow", "surfaces": ["X"], "density": 1.0, "species": {"i_lawn": 1.0, "i_reed": 1.0}}]}))
	assert_true(r.errors.is_empty(), "no errors for an inactive species (%s)" % [r.errors])
	assert_true(r.to_text().contains("i_reed"), "the rules keep it: a save does not lose it")
	var g := GrassTerrainGrowth.from_rules(r)
	assert_eq(g.mix_for("X", 0.0), {"i_lawn": 1.0}, "and grow nothing of it")
