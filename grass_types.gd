# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name GrassTypes
extends RefCounted
## Per-type grass parameters, indexed by the grass map's G byte: a PERMANENT slot ID. Built from the config's species packs (GrassSpeciesCatalog). SLOTS types x 4 vec4
## go to the compute pass (to_bytes), the blade shader (apply_to) and the far field (far_table);
## the fifth row, bed stripes, is stripe_table():
##   a = (height m x season_h, height_jitter 0..1, width m, clump_cell m); season_h is GrassSeason's
##       height factor from the row's height_season (day, factor) knots, 1 without them
##   b = (pull 0..1, facing_mix 0..1, density 0..1, colour layer = 2 x slot)
##   c = (tilt rad, bend, taper_pow, profile: 0 tapered blade .. 1 leaf)
##   d = (midrib 0..1, wind_response x, specular, accent 0..1)
##   e = (bed_m, path_m, stripe_angle_deg, 0): bed_m > 0 grows in beds: bed_m of growth, path_m
##       bare, repeating along world z rotated by stripe_angle_deg (a flower field: 1.2 / 0.6 / 0)
## Colours: a row's leaf_linear, LINEAR [base_a, base_b, tip_a, tip_b (, accent_tip_a, accent_tip_b)],
## becomes sRGB rows (GrassColour builds the layers from those). `accent` is set by date (GrassSeason),
## 0 until then.
## An empty slot draws the verge row (slot 1), so a stray index still draws plausible grass.

const SLOTS := 32
const VEC4 := 4
## Depth below the sea (min, max, feather) of a type without `depth_m`: land: at least 0.3 m above
## the sea, thinning over the 0.3 m before it. The lower end sits
## 10 km down so its feather is 1 at every real depth.
const LAND_DEPTH := Vector3(-10000.0, -0.3, 0.3)
## GrassTypes.new() reads the catalog the project's GrassBladesConfig names; "" is an empty catalog.
const FROM_CONFIG := "<config>"
const NUMERIC := ["height", "height_jitter", "width", "clump_cell", "pull", "facing_mix", "density",
	"tilt", "bend", "taper_pow", "profile", "midrib", "wind_response", "specular", "floor", "tip_pow"]

var rows: Array[Dictionary] = []
var errors: PackedStringArray = []
## The species a stray index draws, and the kernels' fallback (the pack's fallback species; 1, the verge, from a JSON
## catalog).
var fallback_slot := 1


## The project's species (GrassBladesConfig.resolved_packs, through GrassSpeciesCatalog), or a JSON catalog file at
## `path` (tests, tools); "" is an empty catalog.
func _init(path: String = FROM_CONFIG) -> void:
	_clear()
	if path == FROM_CONFIG:
		var c := GrassSpeciesCatalog.from_config()
		_load_doc(c.types_doc())
		fallback_slot = c.fallback_slot()
	elif not path.is_empty():
		if not FileAccess.file_exists(path):
			errors.append("%s does not exist" % path)
		else:
			_load_text(FileAccess.get_file_as_string(path))
	for e in errors:
		push_error("[GrassTypes] %s" % e)


## The tables of a species catalog: its rows on their slots, its fallback.
## Errors in `errors`, not pushed.
static func from_catalog(c: GrassSpeciesCatalog) -> GrassTypes:
	var t := GrassTypes.new("")
	t._load_doc(c.types_doc())
	t.fallback_slot = c.fallback_slot()
	return t


## A catalog from JSON text, errors collected in `errors` (not pushed), for tests and tools.
static func from_json_text(text: String) -> GrassTypes:
	var t := GrassTypes.new("")
	t._load_text(text)
	return t


func _clear() -> void:
	rows.clear()
	for i in SLOTS:
		rows.append({})
	errors.clear()


func _load_text(text: String) -> void:
	var doc = JSON.parse_string(text)
	if typeof(doc) != TYPE_DICTIONARY or typeof(doc.get("types")) != TYPE_ARRAY:
		errors.append("not a type catalog (want {\"types\": [...]})")
		return
	_load_doc(doc)


## The rows of a catalog document ({"types": [row, ...]}: parsed JSON, or GrassSpeciesCatalog.types_doc()).
func _load_doc(doc: Dictionary) -> void:
	for t in doc["types"]:
		var r := _parse_row(t)
		if r.is_empty():
			continue
		var s: int = r["slot"]
		if not rows[s].is_empty():
			errors.append("slot %d used twice (%s, %s)" % [s, rows[s]["name"], r["name"]])
			continue
		rows[s] = r


func _parse_row(t) -> Dictionary:
	if typeof(t) != TYPE_DICTIONARY:
		errors.append("a type entry is not an object")
		return {}
	var nm := str(t.get("name", "?"))
	if not (t.get("slot") is float or t.get("slot") is int):
		errors.append("%s: no slot" % nm)
		return {}
	var slot := int(t["slot"])
	if slot < 0 or slot >= SLOTS:
		errors.append("%s: slot %d outside 0..%d" % [nm, slot, SLOTS - 1])
		return {}
	var r := {"slot": slot, "name": nm, "accent": 0.0}
	for k in NUMERIC:
		if not (t.get(k) is float or t.get(k) is int):
			errors.append("%s: missing or non-numeric %s" % [nm, k])
			return {}
		r[k] = float(t[k])
	# A host_only type is picked by the species mix but draws no blade (blade_place.glsl: dens *= the
	# type's density): it hosts decorations (corals) where it wins.
	if t.get("host_only", false):
		if r["density"] != 0.0:
			errors.append("%s: a host_only row draws no blade, so its density must be 0" % nm)
			return {}
		r["host_only"] = true
	var leaf = t.get("leaf_linear")
	if typeof(leaf) != TYPE_ARRAY or (leaf.size() != 4 and leaf.size() != 6):
		errors.append("%s: leaf_linear needs 4 or 6 [r, g, b] entries" % nm)
		return {}
	var c: Array[Color] = []
	for v in leaf:
		if typeof(v) != TYPE_ARRAY or v.size() != 3:
			errors.append("%s: a leaf_linear entry is not [r, g, b]" % nm)
			return {}
		c.append(Color(float(v[0]), float(v[1]), float(v[2])).linear_to_srgb())
	r["base_a"] = c[0]
	r["base_b"] = c[1]
	r["tip_a"] = c[2]
	r["tip_b"] = c[3]
	if c.size() == 6:
		r["accent_tip_a"] = c[4]
		r["accent_tip_b"] = c[5]
	if t.has("accent_peak"):
		r["accent_peak"] = float(t["accent_peak"])
		r["accent_width"] = float(t.get("accent_width", 30.0))
	# How far the blade colour moves toward the terrain texture under it (0 = own colour).
	r["ground_colour"] = clampf(float(t.get("ground_colour", 0.0)), 0.0, 1.0)
	r["depth"] = LAND_DEPTH
	if t.has("depth_m"):
		var dm = t.get("depth_m")
		if typeof(dm) != TYPE_ARRAY or dm.size() != 2 or not (dm[0] is float or dm[0] is int) \
				or not (dm[1] is float or dm[1] is int) or float(dm[0]) >= float(dm[1]):
			errors.append("%s: depth_m wants [min, max] metres below the sea, min < max" % nm)
			return {}
		r["depth"] = Vector3(float(dm[0]), float(dm[1]), float(t.get("depth_feather_m", 1.0)))
	if t.has("height_season"):
		var knots := _parse_season(t.get("height_season"))
		if knots.is_empty():
			errors.append("%s: height_season wants [[day 0..364, factor > 0], ...] with ascending days" % nm)
			return {}
		r["height_season"] = knots
	if t.get("invented", false):
		r["invented"] = true
	if t.has("picture_day"):
		r["picture_day"] = clampf(float(t["picture_day"]), 0.0, 364.0)
	r["bed_m"] = float(t.get("bed_m", 0.0))
	r["path_m"] = float(t.get("path_m", 0.0))
	r["stripe_angle_deg"] = float(t.get("stripe_angle_deg", 0.0))
	return r


## height_season's knots as Vector2(day, factor), or [] when malformed: pairs, days 0..364 ascending,
## factors > 0.
static func _parse_season(v) -> Array:
	if typeof(v) != TYPE_ARRAY or v.is_empty():
		return []
	var out := []
	for k in v:
		if typeof(k) != TYPE_ARRAY or k.size() != 2 or not (k[0] is float or k[0] is int) \
				or not (k[1] is float or k[1] is int):
			return []
		var kv := Vector2(float(k[0]), float(k[1]))
		if kv.x < 0.0 or kv.x >= GrassSeason.YEAR or kv.y <= 0.0 or (not out.is_empty() and kv.x <= out[-1].x):
			return []
		out.append(kv)
	return out


## How well a type grows `depth` m below the sea (negative: above it): 0 outside its range, 1 inside,
## fading over the last feather at each end. grass_place_common.glsli type_eligibility mirrors it.
static func eligibility(r: Dictionary, depth: float) -> float:
	var d: Vector3 = r.get("depth", LAND_DEPTH)
	if depth < d.x or depth > d.y:
		return 0.0
	return smoothstep(d.x, d.x + d.z, depth) * (1.0 - smoothstep(d.y - d.z, d.y, depth))


## The compute's depth rows (T.v[392 + slot]): (min, max, feather, 0); an empty slot is land.
func depth_table() -> Array:
	var out := []
	for i in SLOTS:
		var d: Vector3 = rows[i].get("depth", LAND_DEPTH)
		out.append(Vector4(d.x, d.y, d.z, 0.0))
	return out


func row(i: int) -> Dictionary:
	if i >= 0 and i < SLOTS and not rows[i].is_empty():
		return rows[i]
	return rows[fallback_slot]


func names() -> PackedStringArray:
	var out := PackedStringArray()
	for r in rows:
		out.append(r.get("name", ""))
	return out


func to_bytes() -> PackedByteArray:
	var f := PackedFloat32Array()
	for i in SLOTS:
		var r := row(i)
		var h: float = r["height"] * float(r.get("season_h", 1.0))     # the day's height (GrassSeason)
		f.append_array([h, r["height_jitter"], r["width"], r["clump_cell"],
			r["pull"], r["facing_mix"], r["density"], float(2 * i),
			r["tilt"], r["bend"], r["taper_pow"], r["profile"],
			r["midrib"], r["wind_response"], r["specular"], r["accent"]])
	return f.to_byte_array()


## The blade shader's per-type uniforms (vec4 type_shape[32], vec4 type_look[32]).
func apply_to(m: ShaderMaterial) -> void:
	var shape := []
	var look := []
	for i in SLOTS:
		var r := row(i)
		shape.append(Vector4(r["tilt"], r["bend"], r["taper_pow"], r["profile"]))
		look.append(Vector4(r["midrib"], r["wind_response"], r["specular"], r["accent"]))
	m.set_shader_parameter("type_shape", shape)
	m.set_shader_parameter("type_look", look)
	var ground := PackedFloat32Array()
	for i in SLOTS:
		ground.append(float(row(i).get("ground_colour", 0.0)))
	m.set_shader_parameter("type_ground", ground)
	var heights := PackedFloat32Array()
	for i in SLOTS:
		heights.append(float(row(i)["height"]))
	m.set_shader_parameter("type_height", heights)


## The far field's table (far_types[SLOTS]): (clump_cell, colour layer, accent, floor).
func far_table() -> Array:
	var out := []
	for i in SLOTS:
		var r := row(i)
		out.append(Vector4(r["clump_cell"], float(2 * i), r["accent"], r["floor"]))
	return out


## Row e per slot: (bed_m, path_m, stripe_angle_deg, 0). Empty slots have no beds.
func stripe_table() -> Array:
	var out := []
	for i in SLOTS:
		var r: Dictionary = rows[i]
		if r.is_empty():
			out.append(Vector4.ZERO)
		else:
			out.append(Vector4(r["bed_m"], r["path_m"], r["stripe_angle_deg"], 0.0))
	return out


## The compute's type buffer: the SLOTS x 4 vec4 of to_bytes() (T.v[0..127]), then row e (bed
## stripes) for the SLOTS slots at T.v[128 + slot].
func upload_bytes() -> PackedByteArray:
	var f := PackedFloat32Array()
	for v: Vector4 in stripe_table():
		f.append_array([v.x, v.y, v.z, v.w])
	var b := to_bytes()
	b.append_array(f.to_byte_array())
	return b
