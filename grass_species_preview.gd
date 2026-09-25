# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name GrassSpeciesPreview
extends RefCounted
## The species picker's pictures and facts (the Grass tile's palette in the Terrain3D Extended overlay): per species a
## tile image and a card image, rendered OFFLINE with the real shaders (GrassPictureRenderer, the picture tool) into
## its pack's pictures folder, plus the facts the hover card lists. recipe() is the one description of how a species
## is shown: the renderer draws it, and its stamp (with the species' row and the kinds it hosts) says when a picture no
## longer matches the data. The folder carries a .gdignore: the editor never imports the PNGs, they load as images.

## Bump when the renderer draws differently for the same recipe (pose, light, crop): every picture is stale.
const RENDER_VERSION := 1
const TILE := "%s.png"
const CARD := "%s_card.png"
const STAMPS := "stamps.json"
const PICTURES := "pictures"


## A pack's pictures folder: <its folder>/pictures ("" for a pack that is not a file).
static func pack_pictures_dir(p_pack: GrassSpeciesPack) -> String:
	if p_pack == null or not p_pack.resource_path.begins_with("res://") or p_pack.resource_path.contains("::"):
		return ""
	return p_pack.resource_path.get_base_dir().path_join(PICTURES)


## The pictures folder of the pack in use that holds species `id` (the first, as GrassSpeciesCatalog.build keeps
## the first); "" when none.
static func pictures_dir(p_id: String) -> String:
	for pack in GrassBladesConfig.current().resolved_packs():
		if pack != null and pack.species.any(func(s): return s != null and String(s.id) == p_id):
			return pack_pictures_dir(pack)
	return ""


## How the species is shown: `ground` (a growth-table slot name, as the table writes it, where it grows most:
## the slot's allowance x the species' share of its mix; "" when none grows it), `sea_depth` (m below the sea
## its patch stands at: its depth range's middle; NAN on land), `day` (the species' picture_day, else its first
## decoration kind's mid-bloom, else GrassEditorPreview's default date) and `frame_h` (m: its tallest part, blade or
## flower, for the camera).
static func recipe(types: GrassTypes, kinds: DecoKinds, growth: GrassTerrainGrowth, slot: int) -> Dictionary:
	var row := types.row(slot)
	var nm := String(row.get("name", ""))
	var best := ""
	var best_w := 0.0
	for key in growth.species_by_name:
		var w := float((growth.species_by_name[key] as Dictionary).get(nm, 0.0)) * growth.allowance(String(key))
		if w > best_w or (w == best_w and w > 0.0 and String(key) < best):
			best = String(key)
			best_w = w
	var depth: Vector3 = row.get("depth", Vector3(-1.0, -1.0, 0.0))
	var bd := bloom_day(kinds, slot)
	var day := float(row["picture_day"]) if row.has("picture_day") \
		else (bd if bd >= 0.0 else GrassEditorPreview.DEFAULT_DAY)
	var frame_h := float(row.get("height", 0.0))
	for i in kinds.kinds.size():
		var k: Dictionary = kinds.kinds[i]
		if int(k["host"]) != slot:
			continue
		var mesh_h := (kinds.mesh(i)[0] as Mesh).get_aabb().end.y * (k["scale"] as Vector2).y
		if k["height_rel"]:
			mesh_h *= float(row.get("height", 0.0))
		frame_h = maxf(frame_h, mesh_h)
	return {"ground": growth.display_names.get(best, best) if best != "" else "",
		"sea_depth": 0.5 * (depth.x + depth.y) if depth.x >= 0.0 else NAN, "day": day, "frame_h": frame_h}


## What a picture was made from: the render version, the species' row and the kinds it hosts (their slot left out, so
## a pack's pictures stay current in any project) and its recipe.
static func stamp(types: GrassTypes, kinds: DecoKinds, growth: GrassTerrainGrowth, slot: int) -> String:
	var row := types.row(slot).duplicate()
	row.erase("slot")
	var parts := [RENDER_VERSION, str(row), str(recipe(types, kinds, growth, slot))]
	for k in kinds.kinds:
		if int(k["host"]) == slot:
			var kk: Dictionary = k.duplicate()
			kk.erase("host")
			if kk["mesh"] is Object:
				kk["mesh"] = _object_key(kk["mesh"])
			parts.append(str(kk))
	return str(parts).md5_text()


## A builder object as text that is the same in every run: its script and its values, a resource by its path (an
## object prints with its id, which is new each run).
static func _object_key(o: Object) -> String:
	var parts := [(o.get_script() as Script).resource_path if o.get_script() != null else o.get_class()]
	for p in o.get_property_list():
		if int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var v = o.get(p["name"])
			parts.append("%s=%s" % [p["name"], (v as Resource).resource_path if v is Resource else str(v)])
	return str(parts)


static func stamps(in_dir: String) -> Dictionary:
	var p := in_dir.path_join(STAMPS)
	if not FileAccess.file_exists(p):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(p))
	return d if d is Dictionary else {}


## The palette species whose pictures are missing or no longer match their data (re-render them). `in_dir`: one folder
## for all (tests, the tool); "" each species' own pack's.
static func stale(types: GrassTypes, kinds: DecoKinds, growth: GrassTerrainGrowth, in_dir := "") -> PackedStringArray:
	var folders := {}
	var out := PackedStringArray()
	for e in GrassPaintTool.palette(types):
		var nm := String(e["name"])
		var d := in_dir if in_dir != "" else pictures_dir(nm)
		if not folders.has(d):
			folders[d] = stamps(d) if d != "" else {}
		var ok := d != "" and FileAccess.file_exists(d.path_join(TILE % nm)) \
			and FileAccess.file_exists(d.path_join(CARD % nm)) \
			and String((folders[d] as Dictionary).get(nm, "")) == stamp(types, kinds, growth, int(e["slot"]))
		if not ok:
			out.append(nm)
	return out


## A picture as a texture (null when there is none): loaded as an image, never imported.
static func texture(path: String) -> Texture2D:
	if path == "" or not FileAccess.file_exists(path):
		return null
	var img := Image.load_from_file(path)
	return ImageTexture.create_from_image(img) if img != null and not img.is_empty() else null


static func tile_texture(nm: String) -> Texture2D:
	var d := pictures_dir(nm)
	return texture(d.path_join(TILE % nm)) if d != "" else null


static func card_texture(nm: String) -> Texture2D:
	var d := pictures_dir(nm)
	return texture(d.path_join(CARD % nm)) if d != "" else null


## A species' flowering date: its first flower's mid-bloom; the default date when that flower blooms all year; -1 for
## a species without flowers. Reads no meshes (the Grass panel's "In bloom" asks on every rebuild).
static func bloom_day(kinds: DecoKinds, slot: int) -> float:
	for k in kinds.kinds:
		if int(k["host"]) != slot:
			continue
		var keys: Vector4 = k["bloom"]
		if keys.x < 0.0:
			return GrassEditorPreview.DEFAULT_DAY
		return fposmod(keys.y + fposmod(keys.z - keys.y, GrassSeason.YEAR) * 0.5, GrassSeason.YEAR)
	return -1.0


## What the hover card says: name, height (m), sea depth range (Vector2, or null on land), its flowers
## [{name, bloom}] (bloom as "10 Mar - 20 Apr" or "all year"), the ground that grows it [{ground, share,
## above_m}] (share of that ground's mix, most first; above_m: only above that elevation, else -1) and whether
## it is invented.
static func facts(types: GrassTypes, kinds: DecoKinds, growth: GrassTerrainGrowth, slot: int) -> Dictionary:
	var row := types.row(slot)
	var nm := String(row.get("name", ""))
	var depth: Vector3 = row.get("depth", Vector3(-1.0, -1.0, 0.0))
	var flowers := []
	for k in kinds.kinds:
		if int(k["host"]) != slot:
			continue
		var keys: Vector4 = k["bloom"]
		flowers.append({"name": String(k["name"]), "bloom": "all year" if keys.x < 0.0
			else "%s - %s" % [GrassSeason.label(keys.y), GrassSeason.label(keys.z)]})
	var grows := []
	for key in growth.species_by_name:
		var w := float((growth.species_by_name[key] as Dictionary).get(nm, 0.0))
		if w > 0.0:
			grows.append({"ground": growth.display_names.get(key, key), "share": w, "above_m": -1.0})
	for key in growth.band_by_name:
		var b: Dictionary = growth.band_by_name[key]
		var w := float((b["species"] as Dictionary).get(nm, 0.0))
		if w > 0.0:
			grows.append({"ground": growth.display_names.get(key, key), "share": w, "above_m": float(b["above_m"])})
	grows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["share"] > b["share"])
	return {"name": nm, "height": float(row.get("height", 0.0)),
		"depth": Vector2(depth.x, depth.y) if depth.x >= 0.0 else null, "flowers": flowers, "grows_on": grows,
		"invented": bool(row.get("invented", false)), "host_only": bool(row.get("host_only", false))}
