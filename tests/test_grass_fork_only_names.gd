# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
class_name TestGrassForkOnlyNames
extends GrassSuite
## The grass runs on upstream Terrain3D: no script of the addon names a
## fork-only Terrain3D constant, method or property as CODE: GrassTerrainCaps reads what it needs by name.

const ROOT := "res://addons/waailand"
## GrassTerrainCaps, and its test (fakes shaped like a streaming Terrain3D build, on purpose).
const ALLOWED := ["res://addons/waailand/grass_terrain_caps.gd", "res://addons/waailand/tests/test_grass_terrain_caps.gd",
	"res://addons/waailand/tests/test_grass_fork_only_names.gd"]
const PATTERNS := ["Terrain3DEditor\\.(SIDE_[A-Z_]+|EROSION)\\b",
	"\\.(get_side_map[a-z_]*|adopt_side_map|load_side_map|save_side_map|get_region_map_origin|deform_[a-z_]+)\\(",
	"\\.(side_maps_enabled|side_maps_folder|streaming_(?!on\\b)[a-z_]+)\\b"]   # not GrassTerrainCaps.streaming_on


static func run() -> Dictionary:
	return await GrassSuite.run_suite(TestGrassForkOnlyNames.new(), "grass_fork_only_names")


func test_no_fork_only_names() -> void:
	var hits := []
	var scripts := _scripts(ROOT)
	for path in scripts:
		if ALLOWED.has(path):
			continue
		var src := FileAccess.get_file_as_string(path)
		for p in PATTERNS:
			for m in RegEx.create_from_string(p).search_all(src):
				hits.append("%s: %s" % [path.trim_prefix(ROOT + "/"), m.get_string()])
	assert_eq(hits, [], "no fork-only Terrain3D name as code outside GrassTerrainCaps")
	assert_true(scripts.size() > 40, "the scan saw the addon's scripts (%d)" % scripts.size())


static func _scripts(p_dir: String) -> Array:
	var out := []
	var d := DirAccess.open(p_dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(p_dir.path_join(f))
	for sub in d.get_directories():
		out.append_array(_scripts(p_dir.path_join(sub)))
	return out
