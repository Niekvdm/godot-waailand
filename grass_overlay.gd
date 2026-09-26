# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name GrassOverlay
extends RefCounted
## The paint overlay (the view strip's layers button; the editor preview only): what the grass maps hold, drawn on the
## terrain by grass_far.gdshaderinc (grass_overlay_apply) while the grass is hidden, so it needs the far field in the
## terrain shader. Each terrain vertex's texel fills the ground around it (the nearest one, no blending):
##   What's painted  a painted species in its slot's tint, removed in red (hatched); forced adds orange stripes, a
##                   painted flower color white dots
##   Density, Height blue where thinner or shorter, warm where thicker or taller, stronger the further from x1; x1 is
##                   clear; removed ground is hatched dark (nothing grows there, whatever the numbers)
## This is its CPU side: the modes, the colors the shader is sent, what a texel shows (the shader's rule, mirrored for
## the legend and the tests) and the legend.

enum Mode { OFF, PAINTED, DENSITY, HEIGHT }

const MODE_NAMES := ["Off", "What's painted", "Density", "Height"]
const REMOVED := Color(0.86, 0.12, 0.1)
const FORCED := Color(1.0, 0.55, 0.05)
const LESS := Color(0.2, 0.45, 1.0)        # thinner, shorter
const MORE := Color(1.0, 0.3, 0.2)         # thicker, taller
const ALPHA := 0.75                        # a species' tint and removed's red over the ground
const ALPHA_HEAT := Vector2(0.3, 0.85)     # the heat maps' strength: just off x1 .. x0 or x2
const MARK_FORCED := 1
const MARK_COLOR := 2
const MARK_REMOVED := 4                    # the heat modes' hatching
const HUE_SPAN := Vector2(0.15, 0.9)       # the species' hues: clear of removed's red and forced's orange


## A slot's tint: the golden angle around the hues in HUE_SPAN, so neighbouring slots differ most.
static func species_color(p_slot: int) -> Color:
	var h := HUE_SPAN.x + fposmod(float(p_slot) * 0.618034, 1.0) * (HUE_SPAN.y - HUE_SPAN.x)
	return Color.from_hsv(h, 0.6, 0.95)


## grass_overlay_hue: every slot's tint, linear (the terrain's ALBEDO is).
static func hues_linear() -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in GrassTypes.SLOTS:
		var c := species_color(i).srgb_to_linear()
		out.append(Vector3(c.r, c.g, c.b))
	return out


## grass_overlay_key: removed, forced, less, more, linear.
static func key_linear() -> PackedVector3Array:
	var out := PackedVector3Array()
	for k in [REMOVED, FORCED, LESS, MORE]:
		var c: Color = (k as Color).srgb_to_linear()
		out.append(Vector3(c.r, c.g, c.b))
	return out


## What a texel (GrassMapCodec) fills its ground with in `p_mode`: the color, and its strength in a (0: clear). The
## shader's rule; the patterns on top are marks().
static func fill(p_mode: Mode, c: Color) -> Color:
	match p_mode:
		Mode.PAINTED:
			if GrassMapCodec.removed(c):
				return Color(REMOVED, ALPHA)
			if c.g8 > 0:
				return Color(species_color(c.g8 - 1), ALPHA)
		Mode.DENSITY, Mode.HEIGHT:
			var v := c.r8 if p_mode == Mode.DENSITY else c.b8
			if v != 128:
				var d := float(v - 128) / 128.0
				return Color(LESS if d < 0.0 else MORE, lerpf(ALPHA_HEAT.x, ALPHA_HEAT.y, minf(absf(d), 1.0)))
	return Color(0.0, 0.0, 0.0, 0.0)


## The patterns over a texel's fill in `p_mode`: MARK_FORCED (orange stripes) and MARK_COLOR (white dots) in What's
## painted, MARK_REMOVED (dark hatching) in the heat modes.
static func marks(c: Color, p_mode := Mode.PAINTED) -> int:
	if p_mode != Mode.PAINTED:
		return MARK_REMOVED if GrassMapCodec.removed(c) else 0
	var m := 0
	if GrassMapCodec.forced(c):
		m |= MARK_FORCED
	if GrassMapCodec.color_index(c) >= 0:
		m |= MARK_COLOR
	return m


## The key for `p_mode`: [color, label] pairs (What's painted: the marks, then each species in use with its tint).
static func legend(p_mode: Mode, p_types: GrassTypes) -> Array:
	match p_mode:
		Mode.PAINTED:
			var out := [[REMOVED, "Removed"], [FORCED, "Forced (stripes)"], [Color.WHITE, "A painted flower color (dots)"]]
			var names := p_types.names()
			for i in names.size():
				if names[i] != "":
					out.append([species_color(i), names[i]])
			return out
		Mode.DENSITY:
			return [[LESS, "Thinner"], [MORE, "Thicker"]]
		Mode.HEIGHT:
			return [[LESS, "Shorter"], [MORE, "Taller"]]
	return []
