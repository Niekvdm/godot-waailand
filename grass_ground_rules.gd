# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name GrassGroundRules
extends RefCounted
## A map's ground rules: rules of one or more surfaces (Terrain3D texture
## names), each the full growth rule (its own grass on or off, density, species mix, an elevation band), then
## Everything else (every surface no rule names), the map's master switch, per-species season settings and the map's
## date. One JSON file per map, <GrassBladesConfig.grounds_dir>/<map>.json. Pure data and operations:
## GrassTerrainGrowth.from_rules and GrassSeasonPlan.from_rules read it; the Ground rules dialog edits it.

const FORMAT := 1
const MODES := ["calendar", "bloom", "stage", "date"]
const MIX_MAX := 6
## Rule colours, in order: a new rule takes the next.
const PALETTE := ["#8bc34a", "#d4b36a", "#2e7d32", "#e91e63", "#607d8b", "#ffc107", "#00bcd4", "#9c27b0",
	"#ff7043", "#795548", "#3f51b5", "#cddc39"]

var default_grass := true            # the master switch: false = every rule, Everything else too, painted only
var rules: Array = []                # {name, colour, surfaces: Array[String], default_grass, density, species, band}
var everything_else := {"default_grass": true, "density": 1.0, "species": {}}
var seasons := {}                    # species name -> {"mode": bloom | stage | date, "stage": 0..1, "day": 0..364}
var map_date := -1.0                 # < 0: the clock (the game's day, the editor's preview date)
var errors: PackedStringArray = []


## The rules in `path`; null when there is no such file (the map uses the shared growth table).
static func load_file(path: String) -> GrassGroundRules:
	if path == "" or not FileAccess.file_exists(path):
		return null
	var r := from_text(FileAccess.get_file_as_string(path))
	for e in r.errors:
		push_error("[GrassGroundRules] %s: %s" % [path, e])
	return r


## Rules from JSON text; what is wrong is dropped and listed in `errors` (not pushed).
static func from_text(text: String) -> GrassGroundRules:
	var r := GrassGroundRules.new()
	var doc = JSON.parse_string(text)
	if typeof(doc) != TYPE_DICTIONARY:
		r.errors.append("not a rules file (want {\"format\": 1, \"rules\": [...], ...})")
		return r
	r._read(doc)
	return r


func _read(doc: Dictionary) -> void:
	if typeof(doc.get("format")) not in [TYPE_INT, TYPE_FLOAT] or int(doc["format"]) != FORMAT:
		errors.append("format %s, want %d" % [doc.get("format"), FORMAT])
		return
	var known := _known_species()
	default_grass = bool(doc.get("default_grass", true))
	var claimed := {}
	var list = doc.get("rules", [])
	for o in (list if typeof(list) == TYPE_ARRAY else []):
		if typeof(o) != TYPE_DICTIONARY:
			errors.append("a rule is not an object")
			continue
		var nm := String(o.get("name", "Rule %d" % (rules.size() + 1)))
		var surf: Array = []
		for s in o.get("surfaces", []):
			var key := String(s).to_lower()
			if claimed.has(key):
				errors.append("%s: %s is already in %s" % [nm, s, claimed[key]])
				continue
			claimed[key] = nm
			surf.append(String(s))
		rules.append({"name": nm, "colour": String(o.get("colour", PALETTE[rules.size() % PALETTE.size()])),
			"surfaces": surf, "default_grass": bool(o.get("default_grass", true)),
			"density": _density(o.get("density", 1.0), nm), "species": _species(o.get("species", {}), nm, known),
			"band": _band(o.get("band", {}), nm, known)})
	var ee = doc.get("everything_else", {})
	if typeof(ee) != TYPE_DICTIONARY:
		ee = {}
	everything_else = {"default_grass": bool(ee.get("default_grass", true)),
		"density": _density(ee.get("density", 1.0), "everything else"),
		"species": _species(ee.get("species", {}), "everything else", known)}
	var ss = doc.get("seasons", {})
	for sp in (ss if typeof(ss) == TYPE_DICTIONARY else {}):
		var s = ss[sp]
		if not known.has(String(sp)):
			errors.append("seasons: no grass type named %s" % sp)
		elif typeof(s) != TYPE_DICTIONARY or not MODES.has(String(s.get("mode", ""))):
			errors.append("seasons: %s's mode is not one of %s" % [sp, MODES])
		else:
			var m := String(s["mode"])
			set_season(String(sp), m, float(s.get("stage", 0.5)) if m == "stage" else float(s.get("day", 0.0)))
	var md = doc.get("map_date")
	map_date = clampf(float(md), 0.0, 364.0) if typeof(md) in [TYPE_INT, TYPE_FLOAT] else -1.0


func _density(v, what: String) -> float:
	if typeof(v) not in [TYPE_INT, TYPE_FLOAT]:
		errors.append("%s: the density is not a number" % what)
		return 1.0
	if float(v) < 0.0 or float(v) > 1.0:
		errors.append("%s: density %s is outside 0..1" % [what, v])
	return clampf(float(v), 0.0, 1.0)


## A mix as written ({species: weight}, the weights raw: GrassTerrainGrowth normalises them). Unknown species, weights
## that are not positive numbers and species past the sixth are dropped, each an error. {} = Everything else's mix.
func _species(m, what: String, known: Dictionary) -> Dictionary:
	var out := {}
	if typeof(m) != TYPE_DICTIONARY:
		errors.append("%s: the species are not {name: weight}" % what)
		return out
	for t in m:
		var w = m[t]
		if not known.has(String(t)):
			errors.append("%s: no species named %s in the config's packs" % [what, t])
		elif typeof(w) not in [TYPE_INT, TYPE_FLOAT] or float(w) <= 0.0:
			errors.append("%s: %s's weight is not a positive number" % [what, t])
		elif out.size() >= MIX_MAX:
			errors.append("%s: more than %d species, %s dropped" % [what, MIX_MAX, t])
		else:
			out[String(t)] = float(w)
	return out


func _band(b, what: String, known: Dictionary) -> Dictionary:
	if typeof(b) != TYPE_DICTIONARY or b.is_empty():
		return {}
	if typeof(b.get("above_m")) not in [TYPE_INT, TYPE_FLOAT]:
		errors.append("%s: the band has no numeric above_m" % what)
		return {}
	var sp := _species(b.get("species", {}), "%s band" % what, known)
	if sp.is_empty():
		errors.append("%s: the band has no species" % what)
		return {}
	return {"above_m": float(b["above_m"]), "species": sp}


static func _known_species() -> Dictionary:
	var known := {}
	for n in GrassTypes.new().names():
		if n != "":
			known[n] = true
	return known


## Rules from the shared growth table (its parsed JSON, the weights as written) for a map's surfaces: surfaces with
## the same allowance, species and band (written in the same order, which is their pick order) share a
## rule, named after the first ("Pasture +2" for three); a surface the table does not list stays in Everything else,
## which takes the table's default and default_species. GrassTerrainGrowth.from_rules then gives the table's own tables
## for these surfaces: the grass is unchanged.
static func from_growth_table(doc: Dictionary, surfaces: PackedStringArray) -> GrassGroundRules:
	var r := GrassGroundRules.new()
	var slots: Dictionary = doc.get("slots", {}) if typeof(doc.get("slots")) == TYPE_DICTIONARY else {}
	var by_key := {}
	for k in slots:
		by_key[String(k).to_lower()] = slots[k]
	var ds = doc.get("default_species", {})
	r.everything_else = {"default_grass": true, "density": clampf(float(doc.get("default", 1.0)), 0.0, 1.0),
		"species": (ds as Dictionary).duplicate(true) if typeof(ds) == TYPE_DICTIONARY else {}}
	var group := {}
	for s in surfaces:
		var v = by_key.get(s.to_lower())
		if v == null:
			continue
		var dens := float(v.get("density", 0.0)) if typeof(v) == TYPE_DICTIONARY else float(v)
		var sp: Dictionary = {}
		var band := {}
		if typeof(v) == TYPE_DICTIONARY:
			if typeof(v.get("species")) == TYPE_DICTIONARY:
				sp = (v["species"] as Dictionary).duplicate(true)
			var bands = v.get("bands")
			if typeof(bands) == TYPE_ARRAY and (bands as Array).size() == 1 and typeof(bands[0]) == TYPE_DICTIONARY:
				band = {"above_m": float(bands[0].get("above_m", 0.0)),
					"species": (bands[0].get("species", {}) as Dictionary).duplicate(true)}
		var sig := JSON.stringify([dens, sp, band], "", false)
		if group.has(sig):
			(r.rules[group[sig]]["surfaces"] as Array).append(s)
		else:
			group[sig] = r.rules.size()
			r.rules.append({"name": s, "colour": PALETTE[r.rules.size() % PALETTE.size()], "surfaces": [s],
				"default_grass": true, "density": clampf(dens, 0.0, 1.0), "species": sp, "band": band})
	for rule in r.rules:
		var n := (rule["surfaces"] as Array).size()
		if n > 1:
			rule["name"] = "%s +%d" % [rule["surfaces"][0], n - 1]
	return r


## The Terrain3DAssets of the terrain a scene holds, FRESHLY loaded (the cached resource is shared with every terrain
## that used it). Hold it while reading its names: a freed temporary Terrain3DAssets blanks its textures' names.
static func scene_assets(scene_path: String) -> Resource:
	var ps := load(scene_path) as PackedScene
	if ps == null:
		return null
	var st := ps.get_state()
	for i in st.get_node_count():
		if st.get_node_type(i) != "Terrain3D":
			continue
		for p in st.get_node_property_count(i):
			if st.get_node_property_name(i, p) == "assets":
				var a: Resource = st.get_node_property_value(i, p)
				return ResourceLoader.load(a.resource_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	return null


## The texture names of a Terrain3DAssets, in id order.
static func surface_names(assets: Resource) -> PackedStringArray:
	var by_id := {}
	if assets != null:
		for ta in assets.call("get_texture_list"):
			if ta != null:
				by_id[int(ta.get("id"))] = str(ta.get("name"))
	var ids := by_id.keys()
	ids.sort()
	var out := PackedStringArray()
	for id in ids:
		out.append(by_id[id])
	return out


## The file's text: a fixed key order, one rule a line, tabs, so diffs stay readable. Keys are never sorted.
func to_text() -> String:
	var lines := PackedStringArray(["{", "\t\"format\": %d," % FORMAT,
		"\t\"default_grass\": %s," % JSON.stringify(default_grass), "\t\"rules\": ["])
	for i in rules.size():
		lines.append("\t\t%s%s" % [JSON.stringify(_ordered(rules[i]), "", false), "," if i < rules.size() - 1 else ""])
	lines.append("\t],")
	lines.append("\t\"everything_else\": %s," % JSON.stringify({"default_grass": everything_else["default_grass"],
		"density": everything_else["density"], "species": everything_else["species"]}, "", false))
	var names := seasons.keys()
	names.sort()
	var ss := {}
	for n in names:
		ss[n] = seasons[n]
	lines.append("\t\"seasons\": %s," % JSON.stringify(ss, "", false))
	lines.append("\t\"map_date\": %s" % ("null" if map_date < 0.0 else JSON.stringify(map_date)))
	lines.append("}")
	return "\n".join(lines) + "\n"


static func _ordered(r: Dictionary) -> Dictionary:
	var o := {"name": r["name"], "colour": r["colour"], "surfaces": r["surfaces"], "default_grass": r["default_grass"],
		"density": r["density"], "species": r["species"]}
	var b: Dictionary = r.get("band", {})
	if not b.is_empty() and not (b.get("species", {}) as Dictionary).is_empty():
		o["band"] = {"above_m": b["above_m"], "species": b["species"]}
	return o


func save_file(path: String) -> Error:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(to_text())
	f.close()
	return OK


# --- the operations (the dialog's; each is one undo step there) ---

## The rule a surface is in; -1 = Everything else.
func rule_of(surface: String) -> int:
	var key := surface.to_lower()
	for i in rules.size():
		for s in rules[i]["surfaces"]:
			if String(s).to_lower() == key:
				return i
	return -1


## What a surface grows by: its rule, or Everything else.
func settings_of(surface: String) -> Dictionary:
	var i := rule_of(surface)
	return rules[i] if i >= 0 else everything_else


## Moves a surface into rule `to` (-1: out of every rule, into Everything else).
func move_surface(surface: String, to: int) -> void:
	var from := rule_of(surface)
	if from == to:
		return
	if from >= 0:
		var arr: Array = rules[from]["surfaces"]
		for j in range(arr.size() - 1, -1, -1):
			if String(arr[j]).to_lower() == surface.to_lower():
				arr.remove_at(j)
	if to >= 0 and to < rules.size():
		(rules[to]["surfaces"] as Array).append(surface)


## A new, empty rule (its own grass on, x1, Everything else's mix) named `nm`; its index.
func add_rule(nm: String) -> int:
	rules.append({"name": nm, "colour": PALETTE[rules.size() % PALETTE.size()], "surfaces": [], "default_grass": true,
		"density": 1.0, "species": {}, "band": {}})
	return rules.size() - 1


## A rule of its own for `surface`, with the settings of the rule it was in (nothing grows differently until it is
## edited), named after it; its index.
func new_rule_from(surface: String) -> int:
	var src := settings_of(surface)
	var i := add_rule(surface)
	var r: Dictionary = rules[i]
	r["default_grass"] = bool(src.get("default_grass", true))
	r["density"] = float(src.get("density", 1.0))
	r["species"] = (src.get("species", {}) as Dictionary).duplicate(true)
	r["band"] = (src.get("band", {}) as Dictionary).duplicate(true)
	move_surface(surface, i)
	return i


## Removes rule i; its surfaces fall to Everything else.
func delete_rule(i: int) -> void:
	if i >= 0 and i < rules.size():
		rules.remove_at(i)


## A field of rule i (-1: Everything else): "name" and "colour" (rules only), "default_grass", "density" (0..1).
func set_field(i: int, key: String, value: Variant) -> void:
	var r: Dictionary = rules[i] if i >= 0 else everything_else
	match key:
		"density":
			r[key] = clampf(float(value), 0.0, 1.0)
		"default_grass":
			r[key] = bool(value)
		"name", "colour":
			if i >= 0:
				r[key] = String(value)
		_:
			push_error("[GrassGroundRules] no field %s" % key)


## A species' weight in rule i's mix (-1: Everything else's; `band`: the rule's band's). 0 removes it; a seventh is
## refused (false).
func set_weight(i: int, species: String, weight: float, band := false) -> bool:
	var r: Dictionary = rules[i] if i >= 0 else everything_else
	var m: Dictionary
	if band:
		if (r.get("band", {}) as Dictionary).is_empty():
			return false
		m = r["band"]["species"]
	else:
		m = r["species"]
	if weight <= 0.0:
		m.erase(species)
		return true
	if not m.has(species) and m.size() >= MIX_MAX:
		return false
	m[species] = weight
	return true


## Rule i's band above `above_m`: created with a copy of the rule's own mix (else Everything else's, else the
## defaults), or its height moved; a negative height removes it.
func set_band(i: int, above_m: float) -> void:
	var r: Dictionary = rules[i]
	if above_m < 0.0:
		r["band"] = {}
		return
	if (r.get("band", {}) as Dictionary).is_empty():
		var sp: Dictionary = r["species"]
		if sp.is_empty():
			sp = everything_else["species"]
		if sp.is_empty():
			sp = GrassTerrainGrowth.pack_default_mix()
		r["band"] = {"above_m": above_m, "species": sp.duplicate()}
	else:
		r["band"]["above_m"] = above_m


## A species' season: "calendar" (the default: removes the setting), "bloom", "stage" (`value`: 0..1) or "date"
## (`value`: the day of the year).
func set_season(species: String, mode: String, value := 0.0) -> void:
	match mode:
		"calendar":
			seasons.erase(species)
		"bloom":
			seasons[species] = {"mode": "bloom"}
		"stage":
			seasons[species] = {"mode": "stage", "stage": clampf(value, 0.0, 1.0)}
		"date":
			seasons[species] = {"mode": "date", "day": clampf(value, 0.0, 364.0)}


func season_of(species: String) -> Dictionary:
	return seasons.get(species, {"mode": "calendar"})


## The map's date; a negative day follows the clock.
func set_map_date(day: float) -> void:
	map_date = -1.0 if day < 0.0 else clampf(day, 0.0, 364.0)


## The map's surfaces that are in no rule (Everything else's).
func unassigned(map_surfaces: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for s in map_surfaces:
		if rule_of(s) < 0:
			out.append(s)
	return out


## The rules' surfaces this map does not have (a texture renamed or removed).
func missing(map_surfaces: PackedStringArray) -> PackedStringArray:
	var have := {}
	for s in map_surfaces:
		have[s.to_lower()] = true
	var out := PackedStringArray()
	for r in rules:
		for s in r["surfaces"]:
			if not have.has(String(s).to_lower()):
				out.append(String(s))
	return out


## Every species this map can grow: each rule's mix and band, and Everything else's (the defaults when it names none).
func species_used() -> PackedStringArray:
	var seen := {}
	var mixes: Array = [everything_else["species"] if not (everything_else["species"] as Dictionary).is_empty()
		else GrassTerrainGrowth.pack_default_mix()]
	for r in rules:
		mixes.append(r["species"])
		mixes.append((r.get("band", {}) as Dictionary).get("species", {}))
	for m in mixes:
		for sp in m:
			seen[String(sp)] = true
	return PackedStringArray(seen.keys())


## A deep copy of the state: the dialog's undo steps.
func snapshot() -> Dictionary:
	return {"default_grass": default_grass, "rules": rules.duplicate(true),
		"everything_else": everything_else.duplicate(true), "seasons": seasons.duplicate(true), "map_date": map_date}


func restore(s: Dictionary) -> void:
	default_grass = bool(s["default_grass"])
	rules = (s["rules"] as Array).duplicate(true)
	everything_else = (s["everything_else"] as Dictionary).duplicate(true)
	seasons = (s["seasons"] as Dictionary).duplicate(true)
	map_date = float(s["map_date"])
