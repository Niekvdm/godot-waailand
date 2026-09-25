# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name DecoKinds
extends RefCounted
## The decoration kinds: host grass type, placement, LOD, bloom window, palette and mesh per kind. The kinds
## come from the species packs' GrassDecoration resources (GrassSpeciesCatalog); this class
## builds the meshes and packs the kinds for the compute. Colours are sRGB in the file and linear once they
## leave (colours()). Uploaded as KP_VEC4 vec4 per kind:
##   0 (host, mode, spacing m | plumes per clump, density)
##   1 (radius, d_full, k_edge, fade m)
##   2 (d_switch, scale min, scale max, season grow)
##   3 (height_rel, patch m, patch share, 0)
##   4 (cap HIGH, cap LOW, hash salt, 0)

## 32: the kind index is a push constant and each kind owns its
## dispatch and MultiMeshes (nothing is packed per instance); the cap sizes the params buffer and
## grass_handoff.gdshaderinc's hand_curve / hand_n / hand_pal.
const MAX_KINDS := 32
const KP_VEC4 := 5
const GRID := 0
const CLUMP := 1
const LEAF := Color(0.30, 0.42, 0.15)
const DRY := Color(0.40, 0.30, 0.18)
const FROM_CONFIG := "<config>"
## Every field a kind may set, with its default ("": required). A field not listed is an error.
const FIELDS := {"name": "", "host": "", "mode": "", "spacing": 1.0, "per_clump": 1, "density": 1.0,
	"radius": "", "d_full": "", "k_edge": "", "d_switch": "", "fade_frac": 0.15, "scale": "",
	"height_rel": false, "patch_m": 0.0, "patch_share": 1.0, "bloom": "", "palette": "",
	"cell": Vector2(1000.0, 1000.0), "stem": "", "centre": Color(0, 0, 0, 0), "casts": false,
	"cap": Vector2i(16384, 16384), "backlight": 0.5, "flutter": 0.0, "wind_response": 1.0,
	"hinge_response": 1.0, "invented": false, "handoff_vis": 1.0, "salt": -1, "mesh": ""}

var kinds: Array[Dictionary] = []
var errors: PackedStringArray = []
var _meshes := {}
var _coverage := {}


## The project's decorations (the config's species packs), or a JSON catalog at `path` (tests, tools); hosts are
## named by `types` (the project's when null). "": no kinds.
func _init(path: String = FROM_CONFIG, types: GrassTypes = null) -> void:
	if path == FROM_CONFIG:
		_load_doc(GrassSpeciesCatalog.from_config().kinds_doc(), types if types != null else GrassTypes.new())
	elif not path.is_empty():
		if not FileAccess.file_exists(path):
			errors.append("%s does not exist" % path)
		else:
			_load_text(FileAccess.get_file_as_string(path), types if types != null else GrassTypes.new())
	for e in errors:
		push_error("[DecoKinds] %s" % e)


## The kinds of a species catalog, hosted by `types`' slots. Errors in `errors`, not pushed.
static func from_catalog(c: GrassSpeciesCatalog, types: GrassTypes) -> DecoKinds:
	var d := DecoKinds.new("")
	d._load_doc(c.kinds_doc(), types)
	return d


## A catalog from JSON text, errors collected in `errors` (not pushed), for tests and tools.
static func from_json_text(text: String, types: GrassTypes) -> DecoKinds:
	var d := DecoKinds.new("")
	d._load_text(text, types)
	return d


func _load_text(text: String, types: GrassTypes) -> void:
	var doc = JSON.parse_string(text)
	if typeof(doc) != TYPE_DICTIONARY or typeof(doc.get("kinds")) != TYPE_ARRAY:
		kinds.clear()
		errors.append("not a decoration catalog (want {\"kinds\": [...]})")
		return
	_load_doc(doc, types)


## The kinds of a catalog document ({"kinds": [kind, ...]}: parsed JSON, or GrassSpeciesCatalog.kinds_doc()).
func _load_doc(doc: Dictionary, types: GrassTypes) -> void:
	kinds.clear()
	var names := types.names()
	for o in doc["kinds"]:
		var k := _parse_kind(o, names)
		if k.is_empty():
			continue
		if kinds.size() == MAX_KINDS:
			errors.append("more than %d kinds: %s and the rest are dropped" % [MAX_KINDS, k["name"]])
			break
		kinds.append(k)


func _parse_kind(o, names: PackedStringArray) -> Dictionary:
	if typeof(o) != TYPE_DICTIONARY:
		errors.append("a kind is not an object")
		return {}
	var nm := String(o.get("name", "?"))
	for key in o:
		if not String(key).begins_with("_") and not FIELDS.has(key):
			errors.append("%s: unknown field '%s'" % [nm, key])
			return {}
	var k := {}
	for key in FIELDS:
		var dflt = FIELDS[key]
		if not o.has(key):
			if typeof(dflt) == TYPE_STRING:
				errors.append("%s: '%s' is required" % [nm, key])
				return {}
			k[key] = dflt
			continue
		var v = o[key]
		match key:
			"name":
				k[key] = String(v)
			"host":
				k[key] = names.find(String(v))
				if k[key] < 0:
					errors.append("%s: no grass type '%s'" % [nm, v])
					return {}
			"mode":
				if v != "grid" and v != "clump":
					errors.append("%s: mode '%s' (grid or clump)" % [nm, v])
					return {}
				k[key] = GRID if v == "grid" else CLUMP
			"per_clump":
				k[key] = int(v)
			"scale", "cell":
				k[key] = Vector2(v[0], v[1])
			"cap":
				k[key] = Vector2i(int(v[0]), int(v[1]))
			"bloom":
				k[key] = GrassSeason.ALWAYS if v is String and v == "always" else _days(v)
			"palette":
				var pal := []
				for e in v:
					pal.append(_palette_entry(e))
				k[key] = pal
			"stem":
				k[key] = Color(v[0], v[1], v[2])
			"centre":
				k[key] = Color(v[0], v[1], v[2], v[3])
			"height_rel", "casts", "invented":
				k[key] = bool(v)
			"mesh":
				k[key] = v
			_:
				k[key] = float(v)
	return k


## [[month, day] x4] (bud, bloom, bloom end, gone) as days of the year.
static func _days(v: Array) -> Vector4:
	return Vector4(GrassSeason.day_of_year(int(v[0][0]), int(v[0][1])), GrassSeason.day_of_year(int(v[1][0]), int(v[1][1])),
		GrassSeason.day_of_year(int(v[2][0]), int(v[2][1])), GrassSeason.day_of_year(int(v[3][0]), int(v[3][1])))


## A palette entry: [bud, bloom, seed] sRGB, or {"flower": c} (buds mostly leaf, seed dry) or {"colony": c}
## (the same every day).
static func _palette_entry(e) -> Array:
	if e is Dictionary and e.has("flower"):
		var c := _rgb(e["flower"])
		return [c.lerp(LEAF, 0.6), c, c.lerp(DRY, 0.6)]
	if e is Dictionary and e.has("colony"):
		var c := _rgb(e["colony"])
		return [c, c, c]
	return [_rgb(e[0]), _rgb(e[1]), _rgb(e[2])]


static func _rgb(v: Array) -> Color:
	return Color(v[0], v[1], v[2])


func index_of(nm: String) -> int:
	for i in kinds.size():
		if kinds[i]["name"] == nm:
			return i
	return -1


func mesh(i: int) -> Array:
	var m = kinds[i]["mesh"]
	if m is GrassDecorationMeshBuilder:
		var okey := "obj:%d" % (m as Object).get_instance_id()
		if not _meshes.has(okey):
			var built: Array = (m as GrassDecorationMeshBuilder).build()
			if built.is_empty():
				push_error("DecoKinds: %s's mesh builder built no mesh" % kinds[i]["name"])
			_meshes[okey] = built
		return _meshes[okey]
	var key := JSON.stringify(m)
	if not _meshes.has(key):
		_meshes[key] = _build_mesh(m)
	return _meshes[key]


## A mesh recipe {builder, args}: the builder's arguments in its signature's order.
static func _build_mesh(m: Dictionary) -> Array:
	var a: Array = m.get("args", [])
	match String(m.get("builder", "")):
		"plume": return PlumeMesh.build(int(a[0]), a[1], a[2], a[3], a[4], int(a[5]))
		"freesia": return FreesiaMesh.build(a[0], a[1], int(a[2]), a[3], int(a[4]), int(a[5]) if a.size() > 5 else 2)
		"isogiku": return IsogikuMesh.build(int(a[0]), a[1], a[2], a[3], int(a[4]))
		"spike": return SpikeMesh.build(a[0], a[1], a[2], int(a[3]))
		"lycoris": return LycorisMesh.build(a[0], int(a[1]), a[2], a[3])
		"lily": return LilyMesh.build(a[0], int(a[1]), a[2], a[3], a[4])
		"coral": return CoralMesh.build(String(a[0]))
	push_error("DecoKinds: no mesh builder '%s'" % m.get("builder", ""))
	return []


## Today's palette in LINEAR colour: bud -> bloom over phase 0..1, bloom -> seed over 1..2.
func colours(i: int, phase: float) -> Array:
	var out := []
	for e in kinds[i]["palette"]:
		var c: Color = (e[0] as Color).lerp(e[1], clampf(phase, 0.0, 1.0)) if phase < 1.0 \
			else (e[1] as Color).lerp(e[2], clampf(phase - 1.0, 0.0, 1.0))
		out.append(c.srgb_to_linear())
	return out


## state[i] = GrassSeason.bloom(...) for kind i (Vector2 grow, phase).
func params_bytes(types: GrassTypes, state: Array) -> PackedByteArray:
	var f := PackedFloat32Array()
	for i in MAX_KINDS:
		if i >= kinds.size():
			var z := PackedFloat32Array()
			z.resize(KP_VEC4 * 4)
			f.append_array(z)
			continue
		var k := kinds[i]
		var st: Vector2 = state[i]
		var grid: bool = k["mode"] == GRID
		f.append_array([float(k["host"]), float(k["mode"]), k["spacing"] if grid else float(k["per_clump"]), k["density"],
			k["radius"], k["d_full"], k["k_edge"], k["radius"] * k["fade_frac"],
			k["d_switch"], (k["scale"] as Vector2).x, (k["scale"] as Vector2).y, st.x,
			1.0 if k["height_rel"] else 0.0, k["patch_m"], k["patch_share"], 0.0,
			float((k["cap"] as Vector2i).x), float((k["cap"] as Vector2i).y),
			float(placement_salt(i)), 0.0])
	return f.to_byte_array()


## The placement hash's salt: the kind's own, or 100 + 16 x its index when it has none (a catalog read from JSON).
func placement_salt(i: int) -> int:
	var s := int(kinds[i]["salt"])
	return s if s >= 0 else 100 + 16 * i


## The palette hash's salt (which colour each patch of its flowers takes, in the decorations and the blades' colour
## handoff): (placement salt - 100) / 16, which is the kind's index in the catalog its salt came from, so a pack that
## lists its kinds in another order keeps every bed's colours. A placement salt below 100 is used as it is.
func palette_salt(i: int) -> int:
	var p := placement_salt(i)
	return (p - 100) / 16 if p >= 100 else p


## Plants per m2 at full placement density: GRID density / spacing^2 x patch share; CLUMP
## plumes per clump x density / the host's clump cell^2.
func plants_per_m2(i: int, types: GrassTypes) -> float:
	var k := kinds[i]
	if k["mode"] == GRID:
		return k["density"] / (k["spacing"] * k["spacing"]) * k["patch_share"]
	var cs: float = types.row(k["host"])["clump_cell"]
	return float(k["per_clump"]) * k["density"] / (cs * cs)


## The share of ground a kind's flowers cover at full density and full bloom, seen from 30
## degrees: FLOWER triangles' area projected on the view, averaged over eight yaws
## (plants face every way), times plants per m2 and the mean scale squared, over the ground's
## projected area (sin 30 = 0.5 per m2). Overlap is ignored, so it is capped at 1.
func coverage(i: int, types: GrassTypes) -> float:
	var key := "%d" % i
	if _coverage.has(key):
		return _coverage[key]
	var k := kinds[i]
	var arr := (mesh(i)[0] as ArrayMesh).surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var a := 0.0
	for y in 8:
		var yaw := TAU * y / 8.0
		var view := Vector3(cos(yaw) * 0.8660254, -0.5, sin(yaw) * 0.8660254)
		for t in range(0, ix.size(), 3):
			var i0 := ix[t]
			if absf(uv[i0].x - DecoMeshBuilder.FLOWER) > 0.01:
				continue
			a += 0.5 * absf((v[ix[t + 2]] - v[i0]).cross(v[ix[t + 1]] - v[i0]).dot(view))
	a /= 8.0
	var s: float = ((k["scale"] as Vector2).x + (k["scale"] as Vector2).y) * 0.5
	if k["height_rel"]:
		s *= float(types.row(k["host"])["height"])
	var f := minf(1.0, a * s * s * plants_per_m2(i, types) / 0.5)
	_coverage[key] = f
	return f
