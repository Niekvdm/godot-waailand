# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name GrassTerrainGrowth
extends RefCounted
## What grows on which terrain texture, and how densely. The growth table (GrassBladesConfig.growth_path)
## maps Terrain3D texture slot NAMES to either an allowance 0..1 (a number: grows `default_species`) or
## {density, species: {type name: weight}, bands: [{above_m, species}]}. The blade and decoration compute
## read the control map, so repainting the terrain moves the grass (its density AND its species) with no
## reseed. Keyed by name, so a slot re-numbered in the assets keeps
## its rule; table_for() and mix_bytes() resolve names to ids through the terrain's own assets.

## GrassTerrainGrowth.new() reads the table the project's GrassBladesConfig names; "" is the defaults.
const FROM_CONFIG := "<config>"
const SLOTS := 32               # Terrain3D texture ids (5 bits in the control word)
const MIX_PAIRS := 6            # species per mix (and per band)
const MIX_VEC4 := 7             # per texture id: 3 vec4 mix, 3 vec4 band mix, 1 vec4 (above_m, has_band, 0, 0)
const WATER_KINDS := 16         # water kinds with an entry (grass_place_common.glsli WATER_KINDS)
const WATER_VEC4 := 4           # per water kind: 3 vec4 floating mix, then (density, 0, 0, 0)
## What a ground with no species grows: the resolved default mix of the config's packs. A growth table's own
## default_species, and a map's ground rules, come first.
static func pack_default_mix() -> Dictionary:
	return GrassSpeciesCatalog.from_config().default_mix.duplicate()

var by_name := {}               # lower-case slot name -> allowance
var species_by_name := {}       # lower-case slot name -> {type name: weight}, normalised
var band_by_name := {}          # lower-case slot name -> {above_m, species}
var display_names := {}         # lower-case slot name -> the name as the table writes it
var default_species := {}       # {type name: weight}, normalised: what a slot with no species grows
## The water section: what floats on each kind of water (its sources' `water_kind`; the sea is GrassWater.SEA_KIND).
var water_by_name := {}         # lower-case water kind -> {"density": 0..1, "species": {type name: weight}}
var water_names := PackedStringArray()   # the kinds as the table writes them, in its order: their index
var fallback := 1.0             # a slot the table does not name
var errors: PackedStringArray = []
## Ground rules: slots whose own grass is off (only painted species and forced spots grow there). table_for writes their allowance negated.
var painted_only := {}          # lower-case slot name -> true
var painted_only_rest := false  # every name no rule lists (Everything else off, or the map's master switch)


func _init(path: String = FROM_CONFIG) -> void:
	if path == FROM_CONFIG:
		path = catalog_path()
	if path.is_empty():
		default_species = pack_default_mix()
		return
	if not FileAccess.file_exists(path):
		errors.append("%s does not exist" % path)
	else:
		_load_text(FileAccess.get_file_as_string(path))
	for e in errors:
		push_error("[GrassTerrainGrowth] %s: %s" % [path, e])


## The growth table of the project's GrassBladesConfig ("" without one).
static func catalog_path() -> String:
	return GrassBladesConfig.current().growth_path


## A table from JSON text, errors collected in `errors` (not pushed), for tests and tools.
static func from_json_text(text: String) -> GrassTerrainGrowth:
	var g := GrassTerrainGrowth.new("")
	g._load_text(text)
	return g


func _load_text(text: String) -> void:
	by_name.clear()
	species_by_name.clear()
	band_by_name.clear()
	display_names.clear()
	water_by_name.clear()
	water_names.clear()
	default_species = pack_default_mix()
	errors.clear()
	var doc = JSON.parse_string(text)
	if typeof(doc) != TYPE_DICTIONARY or typeof(doc.get("slots")) != TYPE_DICTIONARY:
		errors.append("not a growth table (want {\"default\": x, \"slots\": {name: 0..1 or {density, species}}})")
		return
	var known := _known_types()
	fallback = clampf(float(doc.get("default", 1.0)), 0.0, 1.0)
	if doc.has("default_species"):
		var ds := _mix(doc["default_species"], "default_species", known)
		if not ds.is_empty():
			default_species = ds
	for k in doc["slots"]:
		var key := String(k).to_lower()
		display_names[key] = String(k)
		var v = doc["slots"][k]
		var dens = v
		if typeof(v) == TYPE_DICTIONARY:
			dens = v.get("density")
			if v.has("species"):
				var m := _mix(v["species"], "%s species" % k, known)
				if not m.is_empty():
					species_by_name[key] = m
			if v.has("bands"):
				var b := _band(v["bands"], k, known)
				if not b.is_empty():
					band_by_name[key] = b
		if typeof(dens) != TYPE_FLOAT and typeof(dens) != TYPE_INT:
			errors.append("%s: no numeric density" % k)
			continue
		if float(dens) < 0.0 or float(dens) > 1.0:
			errors.append("%s: %s is outside 0..1" % [k, dens])
		by_name[key] = clampf(float(dens), 0.0, 1.0)
	var water = doc.get("water", {})
	if typeof(water) != TYPE_DICTIONARY:
		errors.append("water: want {kind: {density, species}}")
	else:
		for k in water:
			_add_water(String(k), water[k], known)


## Each species' layer by name (GrassTypes.LAYER_*): the names a mix may use, and where.
static func _known_types() -> Dictionary:
	var known := {}
	for r in GrassTypes.new().rows:
		if not r.is_empty():
			known[String(r["name"])] = int(r.get("layer", GrassTypes.LAYER_GROUND))
	return known


## A water kind's entry: its density and its floating mix (surface species; none: it floats nothing).
func _add_water(kind: String, v, known: Dictionary) -> void:
	if typeof(v) != TYPE_DICTIONARY or typeof(v.get("density")) not in [TYPE_FLOAT, TYPE_INT]:
		errors.append("water %s: want {density 0..1, species {name: weight}}" % kind)
		return
	if water_by_name.has(kind.to_lower()):
		errors.append("water %s: named twice" % kind)
		return
	if water_names.size() == WATER_KINDS:
		errors.append("water %s: more than %d water kinds" % [kind, WATER_KINDS])
		return
	var m := {}
	if typeof(v.get("species")) == TYPE_DICTIONARY and not (v["species"] as Dictionary).is_empty():
		m = _mix(v["species"], "water %s species" % kind, known, GrassTypes.LAYER_SURFACE)
	water_by_name[kind.to_lower()] = {"density": clampf(float(v["density"]), 0.0, 1.0), "species": m}
	water_names.append(kind)


## A water kind's entry by name (any case); {density 0, species {}} for one the table lacks.
func water_mix(kind: String) -> Dictionary:
	return water_by_name.get(kind.to_lower(), {"density": 0.0, "species": {}})


## Lower-case kind -> its index (GrassWater.pack).
func water_index() -> Dictionary:
	var out := {}
	for i in water_names.size():
		out[water_names[i].to_lower()] = i
	return out


## The compute's water table (grass_place_common.glsli WATER_BASE): per water kind, 3 vec4 of (type, cumulative
## weight) pairs, then (density, 0, 0, 0); WATER_KINDS kinds, the unused with no pair and density 0.
func water_bytes(types: GrassTypes) -> PackedByteArray:
	var slot_of := {}
	for i in GrassTypes.SLOTS:
		var nm := str(types.rows[i].get("name", ""))
		if nm != "":
			slot_of[nm] = i
	var f := PackedFloat32Array()
	for i in WATER_KINDS:
		var e := water_mix(water_names[i]) if i < water_names.size() else {"density": 0.0, "species": {}}
		f.append_array(_pairs(e["species"], slot_of))
		f.append_array([float(e["density"]), 0.0, 0.0, 0.0])
	return f.to_byte_array()


## A growth table from a map's ground rules: each rule's surfaces get its density, its mix (normalised here;
## {} = Everything else's) and its band; Everything else is the fallback and the default species; a rule whose
## own grass is off (every rule, with the map's master switch off) is painted only.
static func from_rules(r: GrassGroundRules) -> GrassTerrainGrowth:
	var g := GrassTerrainGrowth.new("")
	var known := _known_types()
	g.fallback = clampf(float(r.everything_else.get("density", 1.0)), 0.0, 1.0)
	var es: Dictionary = r.everything_else.get("species", {})
	if not es.is_empty():
		var ds := g._mix(es, "everything else", known)
		if not ds.is_empty():
			g.default_species = ds
	g.painted_only_rest = not (r.default_grass and bool(r.everything_else.get("default_grass", true)))
	for rule in r.rules:
		var nm := String(rule.get("name", ""))
		if bool(rule.get("water", false)):
			g._add_water(nm, {"density": float(rule.get("density", 1.0)), "species": rule.get("species", {})}, known)
			continue
		var sp: Dictionary = rule.get("species", {})
		var m := {} if sp.is_empty() else g._mix(sp, "%s species" % nm, known)
		var bd: Dictionary = rule.get("band", {})
		var b := {} if bd.is_empty() else g._band([bd], nm, known)
		var off := not (r.default_grass and bool(rule.get("default_grass", true)))
		for s in rule.get("surfaces", []):
			var key := String(s).to_lower()
			g.display_names[key] = String(s)
			g.by_name[key] = clampf(float(rule.get("density", 1.0)), 0.0, 1.0)
			if not m.is_empty():
				g.species_by_name[key] = m
			if not b.is_empty():
				g.band_by_name[key] = b
			if off:
				g.painted_only[key] = true
	return g


## {type name: weight} normalised to sum 1, in the JSON's order; {} (and an error) when malformed or a species of the
## other layer (`layer`: GrassTypes.LAYER_GROUND for a ground's mix, LAYER_SURFACE for a water kind's).
func _mix(m, what: String, known: Dictionary, layer := GrassTypes.LAYER_GROUND) -> Dictionary:
	if typeof(m) != TYPE_DICTIONARY or m.is_empty():
		errors.append("%s: want {type name: weight}" % what)
		return {}
	if m.size() > MIX_PAIRS:
		errors.append("%s: %d species, at most %d" % [what, m.size(), MIX_PAIRS])
		return {}
	var total := 0.0
	for t in m:
		if not known.has(str(t)):
			errors.append("%s: no species named %s in the config's packs" % [what, t])
			return {}
		if int(known[str(t)]) != layer:
			errors.append(("%s: %s floats on water (a surface species): give it to a water kind" if layer
				== GrassTypes.LAYER_GROUND else "%s: %s is a ground species: it cannot float") % [what, t])
			return {}
		if (typeof(m[t]) != TYPE_FLOAT and typeof(m[t]) != TYPE_INT) or float(m[t]) <= 0.0:
			errors.append("%s: %s's weight is not a positive number" % [what, t])
			return {}
		total += float(m[t])
	var out := {}
	for t in m:
		out[str(t)] = float(m[t]) / total
	return out


func _band(bands, slot: String, known: Dictionary) -> Dictionary:
	if typeof(bands) != TYPE_ARRAY or bands.size() != 1 or typeof(bands[0]) != TYPE_DICTIONARY:
		errors.append("%s: bands must be ONE {above_m, species}" % slot)
		return {}
	var b: Dictionary = bands[0]
	if typeof(b.get("above_m")) != TYPE_FLOAT and typeof(b.get("above_m")) != TYPE_INT:
		errors.append("%s: the band has no numeric above_m" % slot)
		return {}
	var m := _mix(b.get("species"), "%s band" % slot, known)
	if m.is_empty():
		return {}
	return {"above_m": float(b["above_m"]), "species": m}


func allowance(slot_name: String) -> float:
	return float(by_name.get(slot_name.to_lower(), fallback))


## What grows on `slot_name` at `elevation_m`: {type name: weight}, normalised: the band's mix above
## its elevation, the slot's own mix, or `default_species`.
func mix_for(slot_name: String, elevation_m: float) -> Dictionary:
	var key := slot_name.to_lower()
	var b: Dictionary = band_by_name.get(key, {})
	if not b.is_empty() and elevation_m > float(b["above_m"]):
		return b["species"]
	return species_by_name.get(key, default_species)


## The allowance of every texture id (SLOTS floats) for a Terrain3DAssets: by its textures' names; an id with no
## texture, or a name the table does not list, gets the fallback. A painted-only slot's is NEGATED: the
## GPU reads max(a, 0) for its own grass (none) and |a| for a painted override or a forced corner.
func table_for(assets: Resource) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(SLOTS)
	out.fill(_signed(fallback, painted_only_rest))
	var names := _slot_names(assets)
	for id in names:
		var key := str(names[id]).to_lower()
		out[id] = _signed(allowance(names[id]), painted_only.has(key) or (painted_only_rest and not by_name.has(key)))
	return out


static func _signed(a: float, off: bool) -> float:
	return -a if off and a > 0.0 else a


## The compute's mix table (grass_place_common.glsli MIX_BASE): per texture id, MIX_VEC4 vec4:
## 3 x (type, cumulative weight, type, cumulative weight) for the mix, the same for the band's mix,
## then (band above m, has band, 0, 0). Unused pairs are (-1, 2): never picked. Ids with no texture
## grow `default_species`.
func mix_bytes(assets: Resource, types: GrassTypes) -> PackedByteArray:
	var slot_of := {}
	for i in GrassTypes.SLOTS:
		var nm := str(types.rows[i].get("name", ""))
		if nm != "":
			slot_of[nm] = i
	var names := _slot_names(assets)
	var f := PackedFloat32Array()
	for id in SLOTS:
		var key := str(names.get(id, "")).to_lower()
		var b: Dictionary = band_by_name.get(key, {})
		f.append_array(_pairs(species_by_name.get(key, default_species), slot_of))
		f.append_array(_pairs(b.get("species", {}), slot_of))
		f.append_array([float(b.get("above_m", 0.0)), 1.0 if not b.is_empty() else 0.0, 0.0, 0.0])
	return f.to_byte_array()


static func _pairs(mix: Dictionary, slot_of: Dictionary) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var total := 0.0
	for t in mix:
		if slot_of.has(t):
			total += float(mix[t])
	var cum := 0.0
	for t in mix:
		if slot_of.has(t):
			cum += float(mix[t])
			out.append_array([float(slot_of[t]), cum / total])
	if out.size() > 0:
		out[out.size() - 1] = 1.0      # the last pair takes everything left: no gap from rounding
	while out.size() < MIX_PAIRS * 2:
		out.append_array([-1.0, 2.0])
	return out


## Each texture id's mix at sea level (bands left out: the far field is coarse) as {type slot: area
## weight}, resolved by name while the assets still list their textures (GrassBlades.refresh_growth
## runs before Terrain3D empties the list), for far_slot_params.
func slot_mixes(assets: Resource, types: GrassTypes) -> Array:
	var slot_of := {}
	for i in GrassTypes.SLOTS:
		var nm := str(types.rows[i].get("name", ""))
		if nm != "":
			slot_of[nm] = i
	var names := _slot_names(assets)
	var out := []
	for id in SLOTS:
		var mix: Dictionary = species_by_name.get(str(names.get(id, "")).to_lower(), default_species)
		var m := {}
		for t in mix:
			if slot_of.has(t):
				m[slot_of[t]] = float(mix[t])
		out.append(m)
	return out


## A mix {type slot: area weight} at `depth` m below the sea:
## "shares" = each eligible type's share of the BLADES (weight x eligibility x the type's density,
## normalised: what a readback counts), "best" = the best eligibility (place_at's density multiplier).
static func shares_at(mix: Dictionary, types: GrassTypes, depth: float) -> Dictionary:
	var w := {}
	var tot := 0.0
	var best := 0.0
	for t in mix:
		var r := types.row(int(t))
		var e := GrassTypes.eligibility(r, depth)
		best = maxf(best, e)
		if e > 0.0:
			w[int(t)] = float(mix[t]) * e * float(r["density"])
			tot += w[int(t)]
	var shares := {}
	for t in w:
		shares[t] = w[t] / tot
	return {"shares": shares, "best": best}


## The far field's per-slot table (grass_far.gdshaderinc far_slot): per texture id (grain mean, lod-0 grain
## std, blade height, dominant type): its mix's
## area-weighted means of the types' GrassFarGrain stats and GrassTypes heights; the dominant type's grain
## layer is the one sampled. Without a grain bake the mean is 1 (bare ground) and the std 0.
static func far_slot_params(mixes: Array, types: GrassTypes, grain: Dictionary) -> PackedVector4Array:
	var out := PackedVector4Array()
	var mean: PackedFloat32Array = grain.get("mean", PackedFloat32Array())
	var std: PackedFloat32Array = grain.get("std", PackedFloat32Array())
	for id in SLOTS:
		var mix: Dictionary = mixes[id] if id < mixes.size() else {}
		var v := Vector4.ZERO
		var tot := 0.0
		var best := -1.0
		var dom := types.fallback_slot
		for t in mix:
			var ti := int(t)
			# The far field is land only: a sea type adds nothing.
			var w := float(mix[t]) * GrassTypes.eligibility(types.row(ti), -100.0)   # 100 m above the sea
			if w <= 0.0:
				continue
			v.x += w * (mean[ti] if ti < mean.size() else 1.0)
			v.y += w * (std[ti * GrassFarGrain.LODS] if ti * GrassFarGrain.LODS < std.size() else 0.0)
			v.z += w * float(types.row(ti).get("height", 0.0))
			tot += w
			if w > best:
				best = w
				dom = ti
		if tot > 0.0:
			v.x /= tot
			v.y /= tot
			v.z /= tot
		else:
			v = Vector4(1.0, 0.0, 0.0, 0.0)
		v.w = float(dom)
		out.append(v)
	return out


## id -> slot name for a Terrain3DAssets ({} for none).
static func _slot_names(assets: Resource) -> Dictionary:
	var out := {}
	if assets == null:
		return out
	for ta in assets.call("get_texture_list"):
		if ta != null:
			var id := int(ta.get("id"))
			if id >= 0 and id < SLOTS:
				out[id] = str(ta.get("name"))
	return out


## The names of `assets`' textures this table does not list (they get the fallback).
func unlisted(assets: Resource) -> PackedStringArray:
	var out := PackedStringArray()
	if assets == null:
		return out
	for ta in assets.call("get_texture_list"):
		if ta != null and not by_name.has(str(ta.get("name")).to_lower()):
			out.append(str(ta.get("name")))
	return out
