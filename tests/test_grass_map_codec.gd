# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
class_name TestGrassMapCodec
extends GrassSuite
## The grass map's texel: R = density multiplier x 128,
## G = species override + 1 (0: the ground decides), B = height scale, A = 255.


static func run() -> Dictionary:
	return await GrassSuite.run_suite(TestGrassMapCodec.new(), "grass_map_codec")


func test_the_neutral_texel() -> void:
	var c := GrassMapCodec.encode(1.0, -1, 0.5)
	assert_eq([c.r8, c.g8, c.b8, c.a8], [128, 0, 128, 255], "x1, the ground decides, authored height")
	assert_near(GrassMapCodec.density_mult(c), 1.0, 1e-6, "decodes x1")
	assert_eq(GrassMapCodec.override_type(c), -1, "no override")


func test_overrides_and_multipliers() -> void:
	var c := GrassMapCodec.encode(2.0, 3, 0.5)
	assert_eq(c.r8, 255, "x2 clamps to 255")
	assert_near(GrassMapCodec.density_mult(c), 255.0 / 128.0, 1e-6, "255 decodes to x1.99")
	assert_eq(c.g8, 4, "type 3 is G 4")
	assert_eq(GrassMapCodec.override_type(c), 3, "and decodes to 3")
	var z := GrassMapCodec.encode(0.0, 0, 0.25)
	assert_eq([z.r8, z.g8, z.b8], [0, 1, 64], "none; type 0 (pasture) forced is G 1, not 0")
	assert_eq(GrassMapCodec.override_type(z), 0, "type 0 round trips")
	assert_near(GrassMapCodec.density_mult(GrassMapCodec.encode(0.25, -1, 0.5)), 0.25, 1e-6, "x0.25 round trips")
	assert_eq(GrassMapCodec.override_type(GrassMapCodec.encode(1.0, 31, 0.5)), 31, "the last of 32 slots")


## A: 255 the ground's rules, below 128 forced.
func test_the_force_flag() -> void:
	assert_true(not GrassMapCodec.forced(GrassMapCodec.encode(1.0, -1, 0.5)), "the neutral texel follows the rules")
	var f := GrassMapCodec.encode(1.0, 3, 0.5, true)
	assert_eq([f.a8, GrassMapCodec.forced(f), GrassMapCodec.override_type(f)], [0, true, 3], "forced: A 0, the rest as ever")
