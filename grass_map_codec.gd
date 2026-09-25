# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name GrassMapCodec
extends RefCounted
## The per-region grass map's texel (GrassMaps' RGBA8 images): the PAINT layer over the ground table:
##   R  density multiplier: 128 = as the ground says, 0 = none, 255 = x1.99 (R / 128)
##   G  species override: 0 = the ground decides; k + 1 = force grass type k (GrassTypes slot)
##   B  height scale: 128 = the type's authored height (the compute doubles B / 255)
##   A  the force flag: 255 = the ground's rules; below 128 = forced: grows on any ground
## grass_place_common.glsli place_at() and grass_far.gdshaderinc decode it; the brush, the tests and any
## seeding tool encode it here.

const UNIT := 128.0          # R for x1
const RULES_A := 255         # A: the ground's rules
const FORCED_A := 0          # A: forced


## The texel for a density multiplier (0..~2), a forced type (-1: the ground decides) and a height scale.
static func encode(density_mult: float, override_type: int, hscale: float, forced := false) -> Color:
	return Color8(r_byte(density_mult), g_byte(override_type), clampi(int(round(hscale * 255.0)), 0, 255),
		FORCED_A if forced else RULES_A)


static func r_byte(density_mult: float) -> int:
	return clampi(int(round(density_mult * UNIT)), 0, 255)


static func g_byte(override_type: int) -> int:
	return clampi(override_type + 1, 0, 255) if override_type >= 0 else 0


static func density_mult(c: Color) -> float:
	return float(c.r8) / UNIT


## The forced type, or -1 where the ground decides.
static func override_type(c: Color) -> int:
	return c.g8 - 1


## A forced texel grows on any ground (the ground's allowance counts as 1).
static func forced(c: Color) -> bool:
	return c.a8 < 128
