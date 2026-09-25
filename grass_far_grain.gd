# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name GrassFarGrain
extends RefCounted
## The far field's carpet grain: per grass type, the blade carpet photographed from
## above, stored as its luminance over the BARE ground's (so its brightness comes with its grain),
## tileable, with the std of every mip level (the shader gives back the contrast a mip averages away).
## Baked offline, by rendering the blades. This class only loads and saves
## the bake and says whether it is current: the stats carry a hash of the type catalog, and a
## stale or missing bake loads as {} (the far field then runs without grain rather than wrong).

const TILE_M := 16.0          # the tile's size on the ground
const PX := 512               # its texels
const CAM_H := 80.0           # the photographing camera's height: the carpet as built at that distance
const LODS := 9               # std per mip level 0..8
const TYPES := 32             # GrassTypes.SLOTS


## The bake's directory: the project's GrassBladesConfig.far_grain_dir.
static func dir() -> String:
	return GrassBladesConfig.current().far_grain_dir


## A hash of the species rows the grain was baked for (the config's packs as GrassTypes rows): a bake with another hash
## is stale.
static func types_hash(types: GrassTypes = null) -> String:
	var t := types if types != null else GrassTypes.new()
	return JSON.stringify(t.rows, "", true).sha256_text()


## The bake's texture array (FORMAT_L8, one layer per baked type, mipmapped) and stats → `at` (default dir()).
static func save(tex: Texture2DArray, mean: PackedFloat32Array, std: PackedFloat32Array,
		at: String = "") -> Error:
	if at.is_empty():
		at = dir()
	DirAccess.make_dir_recursive_absolute(at)
	var err := ResourceSaver.save(tex, at + "/far_grain.res", ResourceSaver.FLAG_COMPRESS)
	if err != OK:
		return err
	var f := FileAccess.open(at + "/far_grain.json", FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(stats_dict(mean, std), "\t"))
	f.close()
	return OK


static func stats_dict(mean: PackedFloat32Array, std: PackedFloat32Array) -> Dictionary:
	return {"tile_m": TILE_M, "px": PX, "cam_h": CAM_H, "types_hash": types_hash(),
		"mean": Array(mean), "std": Array(std)}


## {tex: Texture2DArray, mean: PackedFloat32Array[32], std: PackedFloat32Array[288], tile_m}, or {}
## when the bake is missing, malformed, or baked for other species (`current` false: warned, not used).
static func load_baked(at: String = "") -> Dictionary:
	if at.is_empty():
		at = dir()
	var sp := at + "/far_grain.json"
	var tp := at + "/far_grain.res"
	if not FileAccess.file_exists(sp) or not ResourceLoader.exists(tp):
		return {}
	var doc = JSON.parse_string(FileAccess.get_file_as_string(sp))
	var stats := parse_stats(doc)
	if stats.is_empty():
		push_warning("GrassFarGrain: %s is malformed; the far field runs without grain" % sp)
		return {}
	if not is_current(stats):
		push_warning("GrassFarGrain: the grain bake was made for other species; bake it again. "
			+ "The far field runs without grain until then.")
		return {}
	var tex := load(tp) as Texture2DArray
	if tex == null:
		return {}
	stats["tex"] = tex
	return stats


## The stats from their JSON, padded to 32 types (mean 1: bare ground, std 0), or {} if malformed.
static func parse_stats(doc) -> Dictionary:
	if typeof(doc) != TYPE_DICTIONARY or typeof(doc.get("mean")) != TYPE_ARRAY or typeof(doc.get("std")) != TYPE_ARRAY:
		return {}
	var mean := PackedFloat32Array()
	mean.resize(TYPES)
	mean.fill(1.0)
	var std := PackedFloat32Array()
	std.resize(TYPES * LODS)
	var m: Array = doc["mean"]
	var s: Array = doc["std"]
	for i in mini(m.size(), TYPES):
		mean[i] = float(m[i])
	for i in mini(s.size(), TYPES * LODS):
		std[i] = float(s[i])
	return {"mean": mean, "std": std, "tile_m": float(doc.get("tile_m", TILE_M)),
		"types_hash": str(doc.get("types_hash", ""))}


static func is_current(stats: Dictionary) -> bool:
	return str(stats.get("types_hash", "")) == types_hash()


## One type's tile from its capture: luminance over the bare ground's, made tileable by a
## variance-preserving blend with its half-shifted copy (the capture is not periodic), clamped 0..2 and
## stored halved in an L8 image with mipmaps. Returns {img, mean, std[LODS]}: std per mip level as
## box averages, as the mips are.
static func tile_from_capture(img: Image, n: int, ground: float) -> Dictionary:
	var lum := PackedFloat32Array()
	lum.resize(n * n)
	var mean := 0.0
	for y in n:
		for x in n:
			var l := img.get_pixel(x, y).srgb_to_linear().get_luminance() / maxf(ground, 1e-5)
			lum[y * n + x] = l
			mean += l
	mean /= n * n
	var g := PackedFloat32Array()
	g.resize(n * n)
	var h := n / 2
	for y in n:
		for x in n:
			var u := (x + 0.5) / n
			var v := (y + 0.5) / n
			var wa := minf(minf(u, 1.0 - u), minf(v, 1.0 - v))
			var wb := minf(absf(u - 0.5), absf(v - 0.5))
			var a := lum[y * n + x] - mean
			var bb := lum[((y + h) % n) * n + (x + h) % n] - mean
			g[y * n + x] = clampf(mean + (wa * a + wb * bb) / sqrt(wa * wa + wb * wb + 1e-6), 0.0, 2.0)
	var bytes := PackedByteArray()
	bytes.resize(n * n)
	for i in n * n:
		bytes[i] = clampi(int(round(g[i] * 0.5 * 255.0)), 0, 255)
	var out := Image.create_from_data(n, n, false, Image.FORMAT_L8, bytes)
	out.generate_mipmaps()
	return {"img": out, "mean": mean, "std": mip_stds(g, n)}


static func mip_stds(g: PackedFloat32Array, n: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var cur := g
	var cn := n
	for l in LODS:
		var m := 0.0
		for i in cur.size():
			m += cur[i]
		m /= cur.size()
		var vsum := 0.0
		for i in cur.size():
			vsum += (cur[i] - m) * (cur[i] - m)
		out.append(sqrt(vsum / cur.size()))
		if cn <= 1:
			continue
		var nn := cn / 2
		var nxt := PackedFloat32Array()
		nxt.resize(nn * nn)
		for y in nn:
			for x in nn:
				nxt[y * nn + x] = 0.25 * (cur[(2 * y) * cn + 2 * x] + cur[(2 * y) * cn + 2 * x + 1]
					+ cur[(2 * y + 1) * cn + 2 * x] + cur[(2 * y + 1) * cn + 2 * x + 1])
		cur = nxt
		cn = nn
	return out
