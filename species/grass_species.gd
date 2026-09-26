# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name GrassSpecies
extends Resource
## One grass species: its blade, colours, season, sea depth, beds and the
## decorations it hosts. to_row_json() gives the row GrassTypes parses. The defaults are a plain pasture grass, so a
## new species grows something sensible at once.

## Where a species grows: GROUND (the terrain's layer, under and through water too) or SURFACE (floating on water
## sources: water lilies, lotus pads, duckweed).
enum Layer { GROUND, SURFACE }

## The name the ground rules, the growth table and the painting use. Unique across the project's packs.
@export var id: StringName = &""
## The name people see (the library, the hover card).
@export var display_name := ""
## Invented for the game (the hover card says so).
@export var invented := false
## The day of the year its library picture is drawn on (0..364); -1: its first decoration's mid-bloom, else the
## preview's default date. For a species whose look is a season of its own (autumn colour, winter leaves).
@export_range(-1.0, 364.0) var picture_day := -1.0
## GROUND, or SURFACE: it floats on water sources (GrassBlades.set_water, the sea), in the surface layer.
@export var layer := Layer.GROUND

@export_group("Blade")
## Blade height (m).
@export var height := 0.15
## The height's random spread per blade, 0..1.
@export var height_jitter := 0.3
## Blade width (m).
@export var width := 0.012
## The clump cell (m): blades gather into Voronoi clumps about this size.
@export var clump_cell := 0.4
## How much blades lean toward their clump's centre, 0..1.
@export var pull := 0.15
## How much blades take their clump's facing instead of their own, 0..1.
@export var facing_mix := 0.35
## Blades per placement candidate, 0..1 (0 with host_only).
@export var density := 1.0
## How far the blade tilts from upright (rad).
@export var tilt := 0.5
## How much the blade bends along its length.
@export var bend := 0.3
## How fast the blade narrows toward its tip (the taper's exponent).
@export var taper_pow := 2.0
## The outline: 0 a tapered blade, 1 a leaf (narrow at both ends, widest mid-way).
@export var profile := 0.0
## How strongly a pale midrib shows down the centre, 0..1.
@export var midrib := 0.0
## How strongly the blade answers the wind (1: as the wind says).
@export var wind_response := 0.6
## The blade's specular (gloss).
@export var specular := 0.3
## The far carpet's fill for this species (the row key "floor").
@export var floor_fill := 0.8
## The tip colour's falloff exponent.
@export var tip_pow := 2.0
## How far the blade colour moves toward the ground texture under it (0: its own colour).
@export var ground_colour := 1.0

@export_group("Colour")
## The leaf colours are LINEAR, two bases and two tips blended per blade. The first base colour.
@export var base_a := Color(0.07, 0.16, 0.035)
## The second base colour (LINEAR).
@export var base_b := Color(0.08, 0.17, 0.04)
## The first tip colour (LINEAR).
@export var tip_a := Color(0.15, 0.23, 0.05)
## The second tip colour (LINEAR).
@export var tip_b := Color(0.19, 0.25, 0.06)
## Seasonal accent tips (LINEAR), shown around accent_peak over accent_width days.
@export var has_accent_tips := false
## The first accent tip colour (LINEAR).
@export var accent_tip_a := Color(0, 0, 0)
## The second accent tip colour (LINEAR).
@export var accent_tip_b := Color(0, 0, 0)
## The day of the year the accent peaks (0..364); -1: none.
@export var accent_peak := -1.0
## How many days the accent lasts around its peak.
@export var accent_width := 30.0

@export_group("Season and sea")
## Height through the year: (day 0..364, factor) knots, days ascending. Empty: the same all year.
@export var height_season := PackedVector2Array()
## Metres below the water surface it grows at (min, max): under the sea or any water source; (0, 0): a land species.
## A SURFACE species: the water's depth under it (min, max); (0, 0): any water 5 cm deep or more.
@export var depth_m := Vector2.ZERO
## Over how many metres it fades in and out at both ends of its depth range.
@export var depth_feather_m := 1.0
## A GROUND species without depth_m: the deepest water (m) it still grows in (rice 0.3, reed 0.5); 0: it stops at
## the waterline.
@export var wet_depth_m := 0.0

@export_group("Beds")
## Grows in beds: bed_m of growth (m), path_m bare, stripes at stripe_angle_deg (0: no beds).
@export var bed_m := 0.0
## The bare path between two beds (m).
@export var path_m := 0.0
## The beds' direction: degrees from world z.
@export var stripe_angle_deg := 0.0

@export_group("Hosting")
## Picked by the mix but draws no blade: it only hosts its decorations (the corals).
@export var host_only := false
## The decorations it hosts.
@export var decorations: Array[GrassDecoration] = []


## The row GrassTypes parses (the types.json shape), on `p_slot`.
func to_row_json(p_slot: int) -> Dictionary:
	var r := {"slot": p_slot, "name": String(id), "height": height, "height_jitter": height_jitter, "width": width,
		"clump_cell": clump_cell, "pull": pull, "facing_mix": facing_mix, "density": density, "tilt": tilt,
		"bend": bend, "taper_pow": taper_pow, "profile": profile, "midrib": midrib, "wind_response": wind_response,
		"specular": specular, "floor": floor_fill, "tip_pow": tip_pow, "ground_colour": ground_colour,
		"bed_m": bed_m, "path_m": path_m, "stripe_angle_deg": stripe_angle_deg}
	var leaf := [_rgb(base_a), _rgb(base_b), _rgb(tip_a), _rgb(tip_b)]
	if has_accent_tips:
		leaf.append_array([_rgb(accent_tip_a), _rgb(accent_tip_b)])
	r["leaf_linear"] = leaf
	if accent_peak >= 0.0:
		r["accent_peak"] = accent_peak
		r["accent_width"] = accent_width
	if depth_m != Vector2.ZERO:
		r["depth_m"] = [depth_m.x, depth_m.y]
		r["depth_feather_m"] = depth_feather_m
	if not height_season.is_empty():
		var knots := []
		for k in height_season:
			knots.append([k.x, k.y])
		r["height_season"] = knots
	if host_only:
		r["host_only"] = true
	if invented:
		r["invented"] = true
	if layer == Layer.SURFACE:
		r["layer"] = "surface"
	if wet_depth_m > 0.0:
		r["wet_depth_m"] = wet_depth_m
	if picture_day >= 0.0:
		r["picture_day"] = picture_day
	return r


static func _rgb(c: Color) -> Array:
	return [c.r, c.g, c.b]
