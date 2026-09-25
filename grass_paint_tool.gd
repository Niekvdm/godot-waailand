# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name GrassPaintTool
extends RefCounted
## The grass modes of the grass brush (GrassBrush): what each writes into the grass map (GrassMapCodec: R density
## x128, G species override + 1, B height scale, A the force flag). The species channel is an INDEX: only the SET and
## REPLACE modes write it. Pure: GrassPaintProvider is its UI in the Terrain3D Extended overlay.

enum Mode { SPECIES, ERASE, DENSITY_UP, DENSITY_DOWN, DENSITY_RESET, TALLER, SHORTER, HEIGHT_RESET, SMOOTH_DENSITY, SMOOTH_HEIGHT,
	REMOVE, RESTORE, FORCE, UNFORCE, REPLACE, RESET }

const CH_DENSITY := 0
const CH_SPECIES := 1
const CH_HEIGHT := 2
const CH_FORCE := 3
## A region without a grass map starts neutral: x1, the ground decides, the authored height.
const FILL := Color(128.0 / 255.0, 0.0, 128.0 / 255.0, 1.0)

var mode := Mode.SPECIES
var species := 0          # GrassTypes slot
var spray := false        # species / erase / remove / force: a feathered, probabilistic edge
var force := false        # Species: force growth in the same stroke
var replace_from := 0     # Replace: the slot it swaps from


## GrassBrush's op for the current mode (GrassBrush.dab).
func brush_data(types: GrassTypes) -> Dictionary:
	var set_mode := GrassBrush.Mode.SET_SPRAY if spray else GrassBrush.Mode.SET_HARD
	var ch := CH_SPECIES
	var m: int = set_mode
	var v := 0
	match mode:
		Mode.SPECIES:
			v = species + 1
		Mode.ERASE:
			v = 0
		Mode.DENSITY_UP, Mode.DENSITY_DOWN, Mode.DENSITY_RESET:
			ch = CH_DENSITY
			m = GrassBrush.Mode.LERP
			v = {Mode.DENSITY_UP: 255, Mode.DENSITY_DOWN: 0, Mode.DENSITY_RESET: 128}[mode]
		Mode.TALLER, Mode.SHORTER, Mode.HEIGHT_RESET:
			ch = CH_HEIGHT
			m = GrassBrush.Mode.LERP
			v = {Mode.TALLER: 255, Mode.SHORTER: 0, Mode.HEIGHT_RESET: 128}[mode]
		Mode.SMOOTH_DENSITY:
			ch = CH_DENSITY
			m = GrassBrush.Mode.SMOOTH
		Mode.SMOOTH_HEIGHT:
			ch = CH_HEIGHT
			m = GrassBrush.Mode.SMOOTH
		Mode.REMOVE, Mode.RESTORE:
			ch = CH_DENSITY
			v = 0 if mode == Mode.REMOVE else 128
		Mode.FORCE, Mode.UNFORCE:
			ch = CH_FORCE
			v = GrassMapCodec.FORCED_A if mode == Mode.FORCE else GrassMapCodec.RULES_A
		Mode.REPLACE:
			m = GrassBrush.Mode.REPLACE
			v = species + 1
		Mode.RESET:
			m = GrassBrush.Mode.SET_HARD
	var d := {"channel": ch, "mode": m, "value": v, "fill": Color8(128, 0, 128, 255),
		"label": label(types)}
	if mode == Mode.SPECIES and force:
		d["channels"] = PackedInt32Array([CH_SPECIES, CH_FORCE])
		d["values"] = PackedInt32Array([species + 1, GrassMapCodec.FORCED_A])
	elif mode == Mode.REPLACE:
		d["from"] = replace_from + 1
	elif mode == Mode.RESET:
		# the neutral texel, all four channels (`channel`/`value` alone: the density)
		d["channel"] = CH_DENSITY
		d["value"] = 128
		d["channels"] = PackedInt32Array([CH_DENSITY, CH_SPECIES, CH_HEIGHT, CH_FORCE])
		d["values"] = PackedInt32Array([128, 0, 128, GrassMapCodec.RULES_A])
	return d


## The stroke's name in the undo history and the streaming panel.
func label(types: GrassTypes) -> String:
	match mode:
		Mode.SPECIES:
			return "Grass: %s%s" % [_name(types, species), " (forced)" if force else ""]
		Mode.ERASE:
			return "Grass: erase species"
		Mode.DENSITY_UP:
			return "Grass: denser"
		Mode.DENSITY_DOWN:
			return "Grass: sparser"
		Mode.DENSITY_RESET:
			return "Grass: density x1"
		Mode.TALLER:
			return "Grass: taller"
		Mode.SHORTER:
			return "Grass: shorter"
		Mode.HEIGHT_RESET:
			return "Grass: height x1"
		Mode.SMOOTH_DENSITY:
			return "Grass: smooth density"
		Mode.SMOOTH_HEIGHT:
			return "Grass: smooth height"
		Mode.REMOVE:
			return "Grass: remove"
		Mode.RESTORE:
			return "Grass: density x1"
		Mode.FORCE:
			return "Grass: force growth"
		Mode.UNFORCE:
			return "Grass: the ground's rules"
		Mode.REPLACE:
			return "Grass: replace %s with %s" % [_name(types, replace_from), _name(types, species)]
		_:
			return "Grass: reset"


static func _name(types: GrassTypes, slot: int) -> String:
	var r: Dictionary = types.rows[slot] if slot >= 0 and slot < types.rows.size() else {}
	return r.get("name", "?")


## The brush decal: the species' swatch while painting one, a tint per kind of edit otherwise.
func decal_color(types: GrassTypes) -> Color:
	match mode:
		Mode.SPECIES:
			return swatch(types, species)
		Mode.ERASE:
			return Color(0.6, 0.6, 0.6)
		Mode.DENSITY_UP, Mode.TALLER:
			return Color(0.35, 0.85, 0.35)
		Mode.DENSITY_DOWN, Mode.SHORTER:
			return Color(0.6, 0.42, 0.25)
		Mode.REMOVE:
			return Color(0.85, 0.3, 0.25)
		Mode.FORCE:
			return Color(1.0, 0.6, 0.1)
		Mode.REPLACE:
			return swatch(types, species)
		Mode.RESET:
			return Color(0.9, 0.9, 0.9)
		_:
			return Color(0.8, 0.8, 0.95)


## A type's swatch (its sRGB tip colour); white for an empty slot.
static func swatch(types: GrassTypes, slot: int) -> Color:
	if slot < 0 or slot >= types.rows.size() or types.rows[slot].is_empty():
		return Color.WHITE
	return types.rows[slot].get("tip_a", Color.WHITE)


## Every type of the catalog in slot order: {slot, name, colour, sea}.
static func palette(types: GrassTypes) -> Array:
	var out := []
	for r in types.rows:
		if r.is_empty():
			continue
		out.append({"slot": int(r["slot"]), "name": String(r["name"]), "colour": r.get("tip_a", Color.WHITE),
			"sea": (r["depth"] as Vector3).x >= 0.0})
	return out


## A picked grass-map texel: a forced species becomes the brush's species. Returns what the texel says.
func apply_pick(c: Color) -> Dictionary:
	var t := GrassMapCodec.override_type(c)
	if t >= 0:
		species = t
	return {"species": t, "density": GrassMapCodec.density_mult(c), "height": 2.0 * float(c.b8) / 255.0}
