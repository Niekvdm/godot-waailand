# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
extends SceneTree
## Runs every test_*.gd beside this script and exits with the number of failing suites:
##     godot --headless --path <project> --script res://addons/<addon>/tests/run_all.gd
## Each suite has a static run() (it may await) returning {name, passed, failed, details}. The project needs the
## addon and Terrain3D installed; a project whose autoloads need a flag to stay out of the way passes it after --.


func _initialize() -> void:
	var dir: String = (get_script() as Script).resource_path.get_base_dir()
	var names := Array(DirAccess.get_files_at(dir)).filter(
		func(f: String) -> bool: return f.begins_with("test_") and f.ends_with(".gd"))
	names.sort()
	var fails := 0
	var passed_total := 0
	for f in names:
		var s = load(dir.path_join(f))       # untyped: run() is the suite's own static method
		if s == null or not (s is Script) or not s.can_instantiate():
			print("FAIL %s: does not compile" % f)
			fails += 1
			continue
		var r = await s.run()
		var passed := int(r.get("passed", 0)) if r is Dictionary else 0
		var failed := int(r.get("failed", 1)) if r is Dictionary else 1
		passed_total += passed
		var ok := failed == 0 and passed > 0
		print("%s %s: %d pass, %d fail" % ["PASS" if ok else "FAIL", f.get_basename(), passed, failed])
		if not ok:
			fails += 1
			if r is Dictionary:
				for line in r.get("details", []):
					print("    ", line)
	print("%d suite(s), %d assertion(s) passed, %d suite(s) failed" % [names.size(), passed_total, fails])
	quit(mini(fails, 255))
