# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name GrassMapCodec
extends RefCounted
## The per-region grass map's texel (GrassMaps' RGBA8 images): the PAINT layer over the ground table:
##   R  density multiplier: 128 = as the ground says, 0 = none, 255 = x1.99 (R / 128)
##   G  species override: 0 = the ground decides; k + 1 = force grass type k (GrassTypes slot); 255 = removed: nothing
##      grows (the painted density and height kept, so painting again brings the grass back as it was)
##   B  height scale: 128 = the type's authored height (the compute doubles B / 255)
##   A  bit 7 the force flag (set = the ground's rules; clear = forced: grows on any ground); bits 0..6 the flower
##      color: 0 and 127 = Auto (the field's own stripes), 1..126 = palette entry + 1. The old bytes 255 and 0 read as
##      the ground's rules / forced, both Auto.
## grass_place_common.glsli place_at() and grass_far.gdshaderinc decode it; the brush, the tests and any
## seeding tool encode it here.

const UNIT := 128.0          # R for x1
const RULES_A := 255         # A: the ground's rules
const FORCED_A := 0          # A: forced
const REMOVED_G := 255       # G: nothing grows
const FORCE_BIT := 0x80      # A's bit 7: the ground's rules when set
const COLOR_MASK := 0x7F     # A's bits 0..6: the flower color
const COLOR_AUTO := 0        # A's low bits for Auto (127, the old byte's, reads as Auto too)


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


## The forced type, or -1 where the ground decides (or nothing grows: removed).
static func override_type(c: Color) -> int:
	return c.g8 - 1 if c.g8 != REMOVED_G else -1


## Removed: nothing grows here, the ground's own grass included.
static func removed(c: Color) -> bool:
	return c.g8 == REMOVED_G


## The painted flower color's palette entry, or -1 for Auto.
static func color_index(c: Color) -> int:
	var v := c.a8 & COLOR_MASK
	return v - 1 if v > 0 and v < COLOR_MASK else -1


## A forced texel grows on any ground (the ground's allowance counts as 1).
static func forced(c: Color) -> bool:
	return c.a8 < 128
