# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
class_name GrassSuite
extends RefCounted
## Base for the grass suites: assert_true / assert_eq / assert_near, and test_* methods that run in
## declaration order and may await.
## A suite adds:
##     static func run() -> Dictionary:
##         return await GrassSuite.run_suite(TestX.new(), "x")

const FIXTURES := "res://addons/waailand/tests/fixtures"

var current := ""
var pass_count := 0
var fail_count := 0
var details: Array[String] = []


func assert_true(ok: bool, what: String) -> void:
	if ok:
		pass_count += 1
		details.append("✓ %s: %s" % [current, what])
	else:
		fail_count += 1
		details.append("✗ %s: %s" % [current, what])


func assert_eq(a, b, what: String) -> void:
	assert_true(a == b, "%s (got %s, want %s)" % [what, str(a), str(b)])


func assert_near(a: float, b: float, tol: float, what: String) -> void:
	assert_true(absf(a - b) <= tol, "%s (got %.6f, want %.6f +- %.6f)" % [what, a, b, tol])


## The addon's test species in use until the returned config is given back to GrassBladesConfig.use(): one pack built
## from the catalog fixtures (tests/fixtures: twenty species and sixteen decorations, as JSON), on their own slots,
## verge the fallback, verge 0.6 and pasture 0.4 the default mix, no growth table, and none of the project's pack
## addons. For suites that test the addon on real species and must pass in any project, whatever its packs.
static func use_fixture_species() -> GrassBladesConfig:
	var keep := GrassBladesConfig.current()
	var cfg := GrassBladesConfig.new()
	var pack := GrassCatalogImport.pack_from_json(FileAccess.get_file_as_string(FIXTURES.path_join("types.json")),
		FileAccess.get_file_as_string(FIXTURES.path_join("decorations.json")), "Fixtures", {"verge": 0.6, "pasture": 0.4},
		&"verge")
	var packs: Array[GrassSpeciesPack] = [pack]
	cfg.packs = packs
	cfg.slots_path = ""
	cfg.disabled_packs = GrassBladesConfig.discovered_set_paths()   # the project's pack addons stay out of the fixtures
	GrassBladesConfig.use(cfg)
	return keep


static func run_suite(suite: GrassSuite, suite_name: String) -> Dictionary:
	for m in suite.get_method_list():
		var mn: String = m["name"]
		if mn.begins_with("test_"):
			suite.current = mn
			await suite.call(mn)
	return {"name": suite_name, "passed": suite.pass_count, "failed": suite.fail_count,
			"details": suite.details}


## A flat FORMAT_RF height image.
static func flat_heights(size: int, h: float) -> Image:
	var f := PackedFloat32Array()
	f.resize(size * size)
	f.fill(h)
	return Image.create_from_data(size, size, false, Image.FORMAT_RF, f.to_byte_array())
