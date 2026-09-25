# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
class_name TestGrassColourAt
extends GrassSuite
## GrassColour.at: a blade's colour at (u, v), its accent blended in, is
## what the colour array holds there (to its 8-bit rounding), with and without the accent.


static func run() -> Dictionary:
	var keep := GrassSuite.use_fixture_species()
	var r := await GrassSuite.run_suite(TestGrassColourAt.new(), "grass_colour_at")
	GrassBladesConfig.use(keep)
	return r


func test_at_matches_the_layers() -> void:
	var types := GrassTypes.new()
	var row := types.row(types.names().find("susuki"))
	var base := GrassColour.layer(row, false)
	var acc := GrassColour.layer(row, true)
	var worst := 0.0
	for p in [Vector2i(0, 0), Vector2i(7, 31), Vector2i(15, 63), Vector2i(3, 50)]:
		var u := float(p.x) / (GrassColour.W - 1)
		var v := float(p.y) / (GrassColour.H - 1)
		for pair in [[0.0, base], [1.0, acc]]:
			var want: Color = (pair[1] as Image).get_pixelv(p)
			var got := GrassColour.at(row, u, v, pair[0])
			worst = maxf(worst, maxf(absf(got.r - want.r), maxf(absf(got.g - want.g), absf(got.b - want.b))))
	assert_true(worst <= 1.0 / 255.0 + 1e-6, "at() is the array's colour within its rounding (%.5f)" % worst)
	var mid := GrassColour.at(row, 0.5, 0.5, 0.5)
	var lo := GrassColour.at(row, 0.5, 0.5, 0.0)
	var hi := GrassColour.at(row, 0.5, 0.5, 1.0)
	assert_true(mid.is_equal_approx(lo.lerp(hi, 0.5)), "the accent blends linearly between the layers")
