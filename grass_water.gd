# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name GrassWater
extends RefCounted
## The water sources for the kernels (GrassBlades.set_water): the source's polygons within a WINDOW_M square around
## the camera (snapped to SNAP_M), binned into BIN_M cells, as GrassRoads bins the roads. Each polygon is a water
## surface: its outline, its height and its kind (a name in the growth table's water section). The kernels' water_top
## (grass_place_common.glsli) finds the highest surface over a point, the sea's included; top() is its CPU mirror.
## Live: a moved, drained or filled water body needs no bake.
##
## The source is duck-typed (the addon names no game class). It answers `is_empty() -> bool` and `snapshot(origin:
## Vector2, window: float, pad: float) -> {polys: Array[PackedVector2Array], heights: PackedFloat32Array, kinds:
## PackedStringArray}` (one height and kind per polygon), and may answer `revision() -> int`, which moves whenever
## its snapshot would change (without it GrassBlades snapshots again only when the window moves or set_water is
## called).
##
## Buffers (fixed capacity, written before the compute list):
##   ids    uint[]: BINS² + 1 prefix offsets, then polygon ids
##   shapes vec4[]: one per polygon (first vertex, vertex count, surface height, kind index; -1: a kind the table
##                  has no entry for), then the vertices, one vec4 (x, z, 0, 0) each

## The window around the camera the sources are snapshot in (m).
const WINDOW_M := 320.0
## A bin's side (m).
const BIN_M := 8.0
## Bins a window side.
const BINS := 40
## The window moves in steps this long (m).
const SNAP_M := 32.0
## Polygons the buffers hold (a window's); more and the water is dropped, with an error.
const MAX_POLYS := 1024
## Polygon vertices the buffers hold.
const MAX_VERTS := 16384
## Bin offsets and ids the buffers hold.
const MAX_IDS := 32768
## No water: the height top() and the kernels' water_top give where none is.
const NONE := -1e9
## The sea's kind (set_sea): the growth table's water entry for the sea goes by this name.
const SEA_KIND := "Zee"

## The water source (duck-typed, see the header); null: none.
var source = null


## The window's corner for a camera at `cam_xz`.
func window_for(cam_xz: Vector2) -> Vector2:
	var c := (cam_xz / SNAP_M).floor() * SNAP_M
	return c - Vector2.ONE * (WINDOW_M * 0.5)


## The source's revision; -1 without a source or one that has none.
func revision() -> int:
	return int(source.revision()) if source != null and source.has_method("revision") else -1


## The source's polygons around `origin`, binned. `kind_index`: lower-case kind name -> index
## (GrassTerrainGrowth.water_index).
func pack(origin: Vector2, kind_index: Dictionary) -> Dictionary:
	var bins: Array = []
	bins.resize(BINS * BINS)
	for i in bins.size():
		bins[i] = PackedInt32Array()
	var polys: Array = []
	var heights := PackedFloat32Array()
	var kinds := PackedStringArray()
	if source != null and not source.is_empty():
		var snap: Dictionary = source.snapshot(origin, WINDOW_M, 0.0)
		polys = snap.get("polys", [])
		heights = snap.get("heights", PackedFloat32Array())
		kinds = snap.get("kinds", PackedStringArray())
	var keep: Array[int] = []
	for i in mini(polys.size(), heights.size()):
		if (polys[i] as PackedVector2Array).size() >= 3:
			keep.append(i)
	var heads := PackedFloat32Array()
	var verts := PackedFloat32Array()
	var nv := 0
	for i in keep:
		var poly: PackedVector2Array = polys[i]
		var kind := String(kinds[i]) if i < kinds.size() else ""
		heads.append_array([float(keep.size() + nv), float(poly.size()), heights[i],
			float(int(kind_index.get(kind.to_lower(), -1)))])
		var box := Rect2(poly[0], Vector2.ZERO)
		for v in poly:
			verts.append_array([v.x, v.y, 0.0, 0.0])
			box = box.expand(v)
		_bin(bins, heads.size() / 4 - 1, origin, box)
		nv += poly.size()
	var idx := PackedInt32Array()
	idx.resize(BINS * BINS + 1)
	var ids := PackedInt32Array()
	for i in BINS * BINS:
		idx[i] = ids.size()
		ids.append_array(bins[i])
	idx[BINS * BINS] = ids.size()
	idx.append_array(ids)
	var count := keep.size()
	if count > MAX_POLYS or nv > MAX_VERTS or idx.size() > MAX_IDS:
		push_error("[GrassWater] %d polygons / %d vertices / %d ids overflow the buffers; water dropped"
			% [count, nv, idx.size()])
		idx = PackedInt32Array()
		idx.resize(BINS * BINS + 1)
		heads = PackedFloat32Array()
		verts = PackedFloat32Array()
		count = 0
	heads.append_array(verts)
	return {"idx": idx.to_byte_array(), "shapes": heads.to_byte_array(), "count": count, "idx_i": idx,
		"shapes_f": heads}


## The kernels' water_top (grass_place_common.glsli) over a pack() result: Vector4(the highest surface over `p`, its
## kind index, its shore m, 1 when it is the sea); height NONE where there is no water. `sea`: (level, kind index,
## 1 on / 0 off), as GrassBlades sends it.
static func top(pk: Dictionary, origin: Vector2, p: Vector2, sea: Vector3) -> Vector4:
	var best := Vector4(sea.x, sea.y, GrassTypes.SEA_SHORE_M, 1.0) if sea.z > 0.5 else Vector4(NONE, -1.0, 0.0, 0.0)
	if pk.is_empty() or int(pk.get("count", 0)) <= 0:
		return best
	var b := Vector2i(floori((p.x - origin.x) / BIN_M), floori((p.y - origin.y) / BIN_M))
	if b.x < 0 or b.y < 0 or b.x >= BINS or b.y >= BINS:
		return best
	var idx: PackedInt32Array = pk["idx_i"] if pk.has("idx_i") else (pk["idx"] as PackedByteArray).to_int32_array()
	var sh: PackedFloat32Array = pk["shapes_f"] if pk.has("shapes_f") \
		else (pk["shapes"] as PackedByteArray).to_float32_array()
	var bi := b.y * BINS + b.x
	var base := BINS * BINS + 1
	for k in range(idx[bi], idx[bi + 1]):
		var o := idx[base + k] * 4
		if sh[o + 2] <= best.x:
			continue
		var v0 := int(sh[o] + 0.5)
		var n := int(sh[o + 1] + 0.5)
		var inside := false
		var j := n - 1
		for i in n:
			var vi := Vector2(sh[(v0 + i) * 4], sh[(v0 + i) * 4 + 1])
			var vj := Vector2(sh[(v0 + j) * 4], sh[(v0 + j) * 4 + 1])
			if (vi.y > p.y) != (vj.y > p.y) and p.x < (vj.x - vi.x) * (p.y - vi.y) / (vj.y - vi.y) + vi.x:
				inside = not inside
			j = i
		if inside:
			best = Vector4(sh[o + 2], sh[o + 3], 0.0, 0.0)
	return best


static func _bin(bins: Array, id: int, origin: Vector2, box: Rect2) -> void:
	var b0 := ((box.position - origin) / BIN_M).floor()
	var b1 := ((box.end - origin) / BIN_M).floor()
	for by in range(maxi(int(b0.y), 0), mini(int(b1.y), BINS - 1) + 1):
		for bx in range(maxi(int(b0.x), 0), mini(int(b1.x), BINS - 1) + 1):
			# A packed array read from an untyped Array is a COPY: write it back.
			var l: PackedInt32Array = bins[by * BINS + bx]
			l.append(id)
			bins[by * BINS + bx] = l
