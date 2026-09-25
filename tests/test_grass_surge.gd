# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
class_name TestGrassSurge
extends GrassSuite
## The surge: the swell's orbital velocity at the bottom (linear
## wave theory) and the bend it gives a plant: the maths grass_blade.gdshader mirrors.


static func run() -> Dictionary:
	return await GrassSuite.run_suite(TestGrassSurge.new(), "grass_surge")


func test_bottom_velocity() -> void:
	var u5 := GrassSurge.bottom_velocity(1.2, 0.602, 0.037, 5.0)
	assert_near(u5, 1.2 * 0.602 / (2.0 * sinh(0.037 * 5.0)), 1e-5, "H omega / (2 sinh(k h)) at 5 m")
	assert_true(u5 > GrassSurge.bottom_velocity(1.2, 0.602, 0.037, 15.0), "weaker deeper")
	assert_near(GrassSurge.bottom_velocity(0.0, 0.602, 0.037, 5.0), 0.0, 1e-9, "no swell, no surge")
	assert_near(GrassSurge.bottom_velocity(1.2, 0.602, 0.037, 0.1), GrassSurge.bottom_velocity(1.2, 0.602, 0.037, 0.5),
		1e-9, "depth clamped at 0.5 m (no infinity at the waterline)")


func test_bend() -> void:
	assert_near(GrassSurge.bend(0.3), 0.5, 1e-6, "0.3 m/s over the 0.6 m/s reference")
	assert_near(GrassSurge.bend(5.0), 1.2, 1e-6, "clamped at 1.2 rad")
	assert_near(GrassSurge.bend(0.0), 0.0, 1e-9, "still water")
