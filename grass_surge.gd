# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name GrassSurge
extends RefCounted
## The surge that moves a plant under water (grass_blade.gdshader mirrors it). Linear wave theory: the swell's horizontal orbital velocity at the bottom, u_b = H omega /
## (2 sinh(k h)); the plant bends toward the flow in proportion, up to a clamp.

const U_REF := 0.6         # m/s of bottom flow for a 1 rad bend
const BEND_MAX := 1.2      # rad
const MIN_DEPTH := 0.5     # m: no infinity at the waterline


static func bottom_velocity(height: float, omega: float, k: float, depth: float) -> float:
	return height * omega / (2.0 * sinh(k * maxf(depth, MIN_DEPTH)))


static func bend(u_b: float) -> float:
	return clampf(u_b / U_REF, 0.0, BEND_MAX)
