# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
class_name TestGrassPictureTool
extends GrassSuite
## The picture tool from the inspector: its command line renders a pack's stale
## pictures in a separate, off-screen window; a pack that is not a file has no pictures folder, so all of its species
## are to be drawn.


static func run() -> Dictionary:
	return await GrassSuite.run_suite(TestGrassPictureTool.new(), "grass_picture_tool")


func test_the_command_line() -> void:
	var a := GrassPictureTool.args_for("res://packs/x/x.tres")
	assert_true(a.has(GrassPictureTool.SCENE) and a.has("--path"), "the tool's scene, in this project")
	var dd := a.find("--")
	assert_true(dd > a.find(GrassPictureTool.SCENE) and a.slice(dd) == PackedStringArray(["--", "--pack", "res://packs/x/x.tres", "--stale"]),
		"its own arguments after --: the pack, stale only")
	assert_true(a.has("--position"), "off screen")


func test_a_loose_pack_is_all_stale() -> void:
	var p := GrassSpeciesPack.new()
	var s := GrassSpecies.new()
	s.id = &"loose"
	p.species.append(s)
	assert_eq(GrassPictureTool.stale_of(p), PackedStringArray(["loose"]), "no folder: every species")
