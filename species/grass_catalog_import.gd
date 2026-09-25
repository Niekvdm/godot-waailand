# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name GrassCatalogImport
extends RefCounted
## The JSON catalogs (types.json, decorations.json) as a species pack: every row a GrassSpecies, every kind a
## GrassDecoration listed by its host with its catalog salt (100 + 16 x its index),
## so nothing grows elsewhere. save_pack() writes the pack as resource files.

const BUILDERS := {"plume": ["strands", "head_len", "spread", "droop", "strand_w", "lo_every"],
	"freesia": ["stem_h", "arch_len", "flowers", "flower_r", "petals", "spikes"],
	"isogiku": ["heads", "stalk_h", "spread", "head_r", "sides"],
	"spike": ["stem_h", "spike_len", "spike_w", "facets"],
	"lycoris": ["scape_h", "flowers", "tepal_len", "stamen_len"],
	"lily": ["stem_h", "flowers", "tepal_len", "tepal_w", "nod"],
	"coral": ["form"]}


static func pack_from_json(p_types: String, p_decorations: String, p_name: String, p_mix: Dictionary,
		p_fallback: StringName) -> GrassSpeciesPack:
	var tdoc: Dictionary = JSON.parse_string(p_types)
	var ddoc: Dictionary = JSON.parse_string(p_decorations)
	var hosted := {}
	var kinds: Array = ddoc["kinds"]
	for i in kinds.size():
		var d := decoration_from_json(kinds[i])
		d.salt = 100 + 16 * i
		var host := String(kinds[i]["host"])
		if not hosted.has(host):
			hosted[host] = []
		hosted[host].append(d)
	var rows: Array = (tdoc["types"] as Array).duplicate()
	rows.sort_custom(func(a, b): return int(a["slot"]) < int(b["slot"]))
	var pack := GrassSpeciesPack.new()
	pack.name = p_name
	for r in rows:
		var sp := species_from_json(r)
		for d in hosted.get(String(r["name"]), []):
			sp.decorations.append(d)
		pack.species.append(sp)
	pack.fallback_species = p_fallback
	pack.default_mix = p_mix.duplicate()
	return pack


## The JSON catalog's slots: {name: slot}.
static func slots_from_json(p_types: String) -> Dictionary:
	var out := {}
	for r in (JSON.parse_string(p_types) as Dictionary)["types"]:
		out[String(r["name"])] = int(r["slot"])
	return out


static func species_from_json(r: Dictionary) -> GrassSpecies:
	var s := GrassSpecies.new()
	s.id = StringName(r["name"])
	s.resource_name = String(r["name"])
	for k in ["height", "height_jitter", "width", "clump_cell", "pull", "facing_mix", "density", "tilt", "bend",
			"taper_pow", "profile", "midrib", "wind_response", "specular", "tip_pow"]:
		s.set(k, float(r[k]))
	s.floor_fill = float(r["floor"])
	s.ground_colour = float(r.get("ground_colour", 0.0))
	var leaf: Array = r["leaf_linear"]
	s.base_a = _col(leaf[0])
	s.base_b = _col(leaf[1])
	s.tip_a = _col(leaf[2])
	s.tip_b = _col(leaf[3])
	if leaf.size() == 6:
		s.has_accent_tips = true
		s.accent_tip_a = _col(leaf[4])
		s.accent_tip_b = _col(leaf[5])
	if r.has("accent_peak"):
		s.accent_peak = float(r["accent_peak"])
		s.accent_width = float(r.get("accent_width", 30.0))
	if r.has("depth_m"):
		s.depth_m = Vector2(float(r["depth_m"][0]), float(r["depth_m"][1]))
		s.depth_feather_m = float(r.get("depth_feather_m", 1.0))
	if r.has("height_season"):
		var knots := PackedVector2Array()
		for k in r["height_season"]:
			knots.append(Vector2(float(k[0]), float(k[1])))
		s.height_season = knots
	s.host_only = bool(r.get("host_only", false))
	s.invented = bool(r.get("invented", false))
	s.bed_m = float(r.get("bed_m", 0.0))
	s.path_m = float(r.get("path_m", 0.0))
	s.stripe_angle_deg = float(r.get("stripe_angle_deg", 0.0))
	return s


static func decoration_from_json(k: Dictionary) -> GrassDecoration:
	var d := GrassDecoration.new()
	d.name = StringName(k["name"])
	d.resource_name = String(k["name"])
	for f in ["spacing", "density", "radius", "d_full", "k_edge", "d_switch", "fade_frac", "patch_m", "patch_share",
			"backlight", "flutter", "wind_response", "hinge_response", "handoff_vis"]:
		if k.has(f):
			d.set(f, float(k[f]))
	d.mode = String(k["mode"])
	d.per_clump = int(k.get("per_clump", 1))
	d.scale = Vector2(float(k["scale"][0]), float(k["scale"][1]))
	for f in ["height_rel", "casts", "invented"]:
		d.set(f, bool(k.get(f, false)))
	if k.has("cell"):
		d.cell = Vector2(float(k["cell"][0]), float(k["cell"][1]))
	if k.has("cap"):
		d.cap = Vector2i(int(k["cap"][0]), int(k["cap"][1]))
	d.stem = _col(k["stem"])
	if k.has("centre"):
		d.centre = Color(float(k["centre"][0]), float(k["centre"][1]), float(k["centre"][2]), float(k["centre"][3]))
	if k["bloom"] is String:
		d.always_out = true
	else:
		var b := PackedVector2Array()
		for e in k["bloom"]:
			b.append(Vector2(float(e[0]), float(e[1])))
		d.bloom = b
	var pal: Array[PackedColorArray] = []
	for e in k["palette"]:
		pal.append(PackedColorArray(DecoKinds._palette_entry(e)))
	d.palette = pal
	d.mesh_builder = builder_from_recipe(k["mesh"])
	return d


static func builder_from_recipe(m: Dictionary) -> GrassDecorationMeshBuilder:
	var nm := String(m["builder"])
	var b: GrassDecorationMeshBuilder
	match nm:
		"plume": b = PlumeMeshBuilder.new()
		"freesia": b = FreesiaMeshBuilder.new()
		"isogiku": b = IsogikuMeshBuilder.new()
		"spike": b = SpikeMeshBuilder.new()
		"lycoris": b = LycorisMeshBuilder.new()
		"lily": b = LilyMeshBuilder.new()
		"coral": b = CoralMeshBuilder.new()
		_:
			push_error("GrassCatalogImport: no mesh builder '%s'" % nm)
			return null
	var args: Array = m["args"]
	var fields: Array = BUILDERS[nm]
	for i in mini(args.size(), fields.size()):
		var cur = b.get(fields[i])
		b.set(fields[i], int(args[i]) if cur is int else (String(args[i]) if cur is String else float(args[i])))
	return b


## Writes the pack: each decoration to <dir>/decorations/<name>.tres, each species to <dir>/<id>.tres, the pack to
## <dir>/<file>.tres, each referring to the others by path.
static func save_pack(p_pack: GrassSpeciesPack, p_dir: String, p_file: String) -> Error:
	DirAccess.make_dir_recursive_absolute(p_dir.path_join("decorations"))
	for sp in p_pack.species:
		for d in sp.decorations:
			var e := _save_as_file(d, p_dir.path_join("decorations").path_join(String(d.name) + ".tres"))
			if e != OK:
				return e
		var e2 := _save_as_file(sp, p_dir.path_join(String(sp.id) + ".tres"))
		if e2 != OK:
			return e2
	return _save_as_file(p_pack, p_dir.path_join(p_file + ".tres"))


## Saves `r` and makes that file its home, so a resource saved later refers to it by path instead of embedding a copy
## (ResourceSaver's FLAG_CHANGE_PATH does not: the pack would embed everything).
static func _save_as_file(r: Resource, p_path: String) -> Error:
	var e := ResourceSaver.save(r, p_path)
	if e == OK:
		r.take_over_path(p_path)
	return e


static func _col(v: Array) -> Color:
	return Color(float(v[0]), float(v[1]), float(v[2]))
