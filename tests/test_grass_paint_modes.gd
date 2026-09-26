# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
class_name TestGrassPaintModes
extends GrassSuite
## What each Grass tool writes (GrassPaintTool through GrassBrush on GrassMaps): Remove is its own marker (G 255) that
## painting overwrites, and painting heals a density of 0; Force plants the chosen species or only flags the ground, its
## flag a bit that leaves the color alone; Color writes a palette entry into the force byte's low bits; Path wears the
## grass and grows it back; Reset can reset the species alone; a region fill keeps the bits it does not own.

var types := GrassTypes.new()


static func run() -> Dictionary:
	return await GrassSuite.run_suite(TestGrassPaintModes.new(), "grass_paint_modes")


func _setup() -> GrassBrush:
	var t := TestGrassBrush.FakeTerrain.new()
	var maps := GrassMaps.new()
	maps.keep_images = true
	maps.bind(t)
	var b := GrassBrush.new()
	b.maps = maps
	b.data = t.data
	return b


func _paint(b: GrassBrush, tool: GrassPaintTool, fill := false) -> void:
	var op := tool.brush_data(types)
	if fill:
		op["fill_region"] = true
	b.begin()
	b.dab(Vector3(20.0, 0.0, 20.0), TestGrassBrush._brush(4.0, 1.0), op)


func _texel(b: GrassBrush) -> Color:
	return b.maps.pixel(Vector3(20.0, 0.0, 20.0))


func _put(b: GrassBrush, c: Color) -> void:
	var img := b.maps.image(Vector2i(0, 0))
	img.set_pixel(20, 20, c)


func test_codec() -> void:
	assert_true(GrassMapCodec.removed(Color8(128, 255, 128, 255)), "G 255: removed")
	assert_eq(GrassMapCodec.override_type(Color8(128, 255, 128, 255)), -1, "a removed texel names no species")
	assert_eq([GrassMapCodec.color_index(Color8(128, 0, 128, 255)), GrassMapCodec.color_index(Color8(128, 0, 128, 0))],
		[-1, -1], "the old bytes (255 and 0) read as Auto")
	var c := Color8(128, 0, 128, 3)
	assert_true(GrassMapCodec.forced(c) and GrassMapCodec.color_index(c) == 2, "forced with palette entry 2")
	assert_true(not GrassMapCodec.forced(Color8(128, 0, 128, 128 + 3)), "the top bit is the ground's rules")


func test_remove_then_paint() -> void:
	var b := _setup()
	var t := GrassPaintTool.new()
	t.mode = GrassPaintTool.Mode.REMOVE
	_paint(b, t)
	var c := _texel(b)
	assert_true(GrassMapCodec.removed(c) and c.r8 == 128, "Remove writes the marker, density untouched")
	t.mode = GrassPaintTool.Mode.SPECIES
	t.species = 4
	_paint(b, t)
	assert_eq(_texel(b).g8, 5, "Paint over a removed spot: the species grows again")
	_put(b, Color8(0, 0, 128, 255))
	_paint(b, t)
	assert_true(_texel(b).g8 == 5 and _texel(b).r8 == 128, "an old removal (density 0) heals when painted")
	_put(b, Color8(200, 0, 128, 255))
	_paint(b, t)
	assert_eq(_texel(b).r8, 200, "a painted density stays")


func test_force_and_color_bits() -> void:
	var b := _setup()
	var t := GrassPaintTool.new()
	t.mode = GrassPaintTool.Mode.COLOR
	t.color = 5
	_paint(b, t)
	assert_eq(_texel(b).a8, 128 + 6, "Color: entry 5 in the low bits, the ground's rules kept")
	t.mode = GrassPaintTool.Mode.FORCE
	t.species = 3
	t.force_species = true
	_paint(b, t)
	var c := _texel(b)
	assert_true(c.g8 == 4 and GrassMapCodec.forced(c) and GrassMapCodec.color_index(c) == 5,
		"Force the chosen species: its species, the flag, the color kept")
	t.mode = GrassPaintTool.Mode.UNFORCE
	_paint(b, t)
	assert_true(not GrassMapCodec.forced(_texel(b)) and GrassMapCodec.color_index(_texel(b)) == 5,
		"Ctrl: the ground's rules, the color kept")
	_put(b, Color8(128, 0, 128, 255))
	t.mode = GrassPaintTool.Mode.FORCE
	t.force_species = false
	_paint(b, t)
	assert_true(_texel(b).g8 == 0 and GrassMapCodec.forced(_texel(b)), "Force the ground's own mix: the flag alone")
	t.mode = GrassPaintTool.Mode.COLOR_AUTO
	_paint(b, t)
	assert_true(GrassMapCodec.color_index(_texel(b)) == -1 and GrassMapCodec.forced(_texel(b)),
		"Ctrl on Color: Auto, still forced")


func test_path_and_reset() -> void:
	var b := _setup()
	var t := GrassPaintTool.new()
	t.mode = GrassPaintTool.Mode.PATH
	t.wear = 1
	_paint(b, t)
	assert_eq([_texel(b).r8, _texel(b).b8], [GrassPaintTool.WEAR[1][0], GrassPaintTool.WEAR[1][1]],
		"Path (Worn): thinner and shorter")
	t.mode = GrassPaintTool.Mode.PATH_BACK
	_paint(b, t)
	assert_eq([_texel(b).r8, _texel(b).b8], [128, 128], "Ctrl: grown back to x1")
	_put(b, Color8(90, 7, 200, 3))
	t.mode = GrassPaintTool.Mode.ERASE
	_paint(b, t)
	assert_eq([_texel(b).r8, _texel(b).g8, _texel(b).b8, _texel(b).a8], [90, 0, 200, 3],
		"Reset, species only: the ground's species back, the rest kept")
	t.mode = GrassPaintTool.Mode.RESET
	_paint(b, t)
	assert_eq([_texel(b).r8, _texel(b).g8, _texel(b).b8, _texel(b).a8], [128, 0, 128, 255], "Reset: everything")


func test_a_fill_keeps_other_bits() -> void:
	var b := _setup()
	_put(b, Color8(128, 0, 128, 0))
	var t := GrassPaintTool.new()
	t.mode = GrassPaintTool.Mode.COLOR
	t.color = 1
	_paint(b, t, true)
	assert_true(GrassMapCodec.forced(_texel(b)) and GrassMapCodec.color_index(_texel(b)) == 1,
		"a region fill writes the color bits and keeps the force bit")
