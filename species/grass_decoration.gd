# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name GrassDecoration
extends Resource
## One decoration kind: a flower, plume, spike or coral a species hosts. The
## species that lists it is its host. Its fields are DecoKinds.FIELDS; to_kind_json() gives the kind DecoKinds parses.

## The kind's name, unique among the project's decorations.
@export var name: StringName = &""
## "grid": on its own spacing; "clump": on the host's clumps.
@export_enum("grid", "clump") var mode := "grid"
## Metres between plants (grid).
@export var spacing := 1.0
## Plants per clump (clump).
@export var per_clump := 1
## The share of candidates that grow, 0..1.
@export var density := 1.0
## The draw radius (m).
@export var radius := 60.0
## Full density out to this distance (m).
@export var d_full := 20.0
## The share still drawn where the fade begins, 0..1.
@export var k_edge := 0.2
## The fade before the radius, as a share of the radius.
@export var fade_frac := 0.15
## Where HIGH gives way to LOW.
@export var d_switch := 20.0
## The instance scale range (min, max).
@export var scale := Vector2(0.8, 1.0)
## Scale relative to the host's blade height (a mesh built at unit height, like a plume).
@export var height_rel := false
## Patches of this size (m) grow or stay bare together; 0: no patches.
@export var patch_m := 0.0
## The share of patches that grow, 0..1.
@export var patch_share := 1.0
## The bloom: bud, bloom, bloom end, gone as (month, day). always_out: out every day (corals).
@export var bloom: PackedVector2Array = PackedVector2Array([Vector2(4, 1), Vector2(4, 15), Vector2(5, 15), Vector2(6, 1)])
## Out every day (corals): the bloom dates do not apply.
@export var always_out := false
## The palette: per entry three sRGB colours, bud, bloom and seed.
@export var palette: Array[PackedColorArray] = [PackedColorArray([Color(0.5, 0.55, 0.3), Color(0.95, 0.95, 0.9), Color(0.6, 0.5, 0.35)])]
## The world cell the placement hashes on.
@export var cell := Vector2(1000.0, 1000.0)
## The stem colour (sRGB).
@export var stem := Color(0.35, 0.4, 0.3)
## A centre colour for throats and anthers (sRGB; alpha 0: none).
@export var centre := Color(0, 0, 0, 0)
## Casts shadows.
@export var casts := false
## The instance caps, HIGH and LOW.
@export var cap := Vector2i(16384, 16384)
## How strongly its petals and plumes glow when the camera looks toward the sun.
@export var backlight := 0.5
## Extra fast flutter of a plume's head, 0..1.
@export var flutter := 0.0
## How strongly it answers the wind (1: as the wind says).
@export var wind_response := 1.0
## 0: rigid (corals); 1: the root hinge bends with wash and trails.
@export var hinge_response := 1.0
## Invented for the game (the hover card says so).
@export var invented := false
## How visible LOW stays at the handoff.
@export var handoff_vis := 1.0
## The placement hash's salt. -1: derived from the name (a new decoration); one converted from a JSON catalog keeps
## its catalog value, so no plant moves.
@export var salt := -1
## Its mesh: a built-in builder, a MeshMeshBuilder, or your own GrassDecorationMeshBuilder script.
@export var mesh_builder: GrassDecorationMeshBuilder


## The kind DecoKinds parses (the decorations.json shape): `host` is the species' id, `salt` the placement salt.
func to_kind_json(p_host: String, p_salt: int) -> Dictionary:
	var pal := []
	for e in palette:
		pal.append([_rgb(e[0]), _rgb(e[1]), _rgb(e[2])])
	var k := {"name": String(name), "host": p_host, "mode": mode, "spacing": spacing, "per_clump": per_clump,
		"density": density, "radius": radius, "d_full": d_full, "k_edge": k_edge, "d_switch": d_switch,
		"fade_frac": fade_frac, "scale": [scale.x, scale.y], "height_rel": height_rel, "patch_m": patch_m,
		"patch_share": patch_share, "palette": pal, "cell": [cell.x, cell.y], "stem": _rgb(stem),
		"centre": [centre.r, centre.g, centre.b, centre.a], "casts": casts, "cap": [cap.x, cap.y],
		"backlight": backlight, "flutter": flutter, "wind_response": wind_response, "hinge_response": hinge_response,
		"invented": invented, "handoff_vis": handoff_vis, "salt": p_salt}
	k["bloom"] = "always" if always_out else [[int(bloom[0].x), int(bloom[0].y)], [int(bloom[1].x), int(bloom[1].y)],
		[int(bloom[2].x), int(bloom[2].y)], [int(bloom[3].x), int(bloom[3].y)]]
	if mesh_builder != null:
		var r := mesh_builder.recipe()
		k["mesh"] = r if not r.is_empty() else mesh_builder
	return k


static func _rgb(c: Color) -> Array:
	return [c.r, c.g, c.b]
