# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name GrassRoads
extends RefCounted
## The road footprint for the blade and decoration kernels: the footprint's shapes within a
## WINDOW_M square around the camera (snapped to SNAP_M), binned into BIN_M cells. The kernels run a GLSL
## mirror of the footprint's classify rule over their bin's shapes: road surface grows nothing, the verge band
## turns grass into the verge type. Live: a moved road needs no bake.
##
## The footprint is duck-typed (the addon names no game class); a game hands its own through
## GrassBlades.set_road_footprint. It answers `is_empty() -> bool` and
## `snapshot(origin: Vector2, window: float, pad: float) -> {segs: PackedFloat32Array, polys: Array}`:
## segments SEG_STRIDE floats each (ax, az, bx, bz, half width, flags), polygons as PackedVector2Array rings.
##
## Buffers (fixed capacity, written before the compute list):
##   ids    uint[]: BINS² + 1 prefix offsets, then shape ids
##   shapes vec4[]: 2 per shape: segment (ax, az, bx, bz), (hw, flags, 0, 0);
##                  polygon (first vertex, vertex count, 0, 0), (0, 0, 1, 0);
##                  then polygon vertices, one vec4 (x, z, 0, 0) each

const WINDOW_M := 320.0
const BIN_M := 8.0
const BINS := 40
const SNAP_M := 32.0
const MAX_SHAPES := 8192
const MAX_IDS := 65536
const MARGIN_M := 0.3
const VERGE_M := Vector2(1.5, 3.0)
const REACH_PAD := 4.0      # verge reach + margin, so a bin lists the shapes whose verge touches it
const SEG_STRIDE := 6          # floats per footprint segment in a snapshot's segs

var footprint = null          # duck-typed, see the header


func window_for(cam_xz: Vector2) -> Vector2:
	var c := (cam_xz / SNAP_M).floor() * SNAP_M
	return c - Vector2.ONE * (WINDOW_M * 0.5)


func pack(origin: Vector2) -> Dictionary:
	var shapes := PackedFloat32Array()
	var bins: Array = []
	bins.resize(BINS * BINS)
	for i in bins.size():
		bins[i] = PackedInt32Array()
	var count := 0
	if footprint != null and not footprint.is_empty():
		var snap: Dictionary = footprint.snapshot(origin, WINDOW_M, REACH_PAD)
		var segs: PackedFloat32Array = snap.get("segs", PackedFloat32Array())
		var polys: Array = snap.get("polys", [])
		var verts := PackedFloat32Array()
		var n_shapes := segs.size() / SEG_STRIDE + polys.size()
		var s := 0
		while s < segs.size():
			var a := Vector2(segs[s], segs[s + 1])
			var b := Vector2(segs[s + 2], segs[s + 3])
			var hw := segs[s + 4]
			shapes.append_array([a.x, a.y, b.x, b.y, hw, segs[s + 5], 0.0, 0.0])
			_bin(bins, count, origin, Rect2(a, Vector2.ZERO).expand(b).grow(hw + REACH_PAD))
			count += 1
			s += SEG_STRIDE
		for poly: PackedVector2Array in polys:
			var first := n_shapes * 2 + verts.size() / 4
			shapes.append_array([float(first), float(poly.size()), 0.0, 0.0, 0.0, 0.0, 1.0, 0.0])
			var box := Rect2(poly[0], Vector2.ZERO)
			for v in poly:
				verts.append_array([v.x, v.y, 0.0, 0.0])
				box = box.expand(v)
			_bin(bins, count, origin, box.grow(REACH_PAD))
			count += 1
		shapes.append_array(verts)
	var idx := PackedInt32Array()
	idx.resize(BINS * BINS + 1)
	var ids := PackedInt32Array()
	for i in BINS * BINS:
		idx[i] = ids.size()
		ids.append_array(bins[i])
	idx[BINS * BINS] = ids.size()
	idx.append_array(ids)
	if count > MAX_SHAPES or idx.size() > MAX_IDS or shapes.size() / 4 > MAX_SHAPES * 3:
		push_error("[GrassRoads] %d shapes / %d ids overflow the buffers; roads dropped" % [count, idx.size()])
		idx = PackedInt32Array()
		idx.resize(BINS * BINS + 1)
		shapes = PackedFloat32Array()
		count = 0
	return {"idx": idx.to_byte_array(), "shapes": shapes.to_byte_array(), "count": count, "idx_i": idx, "shapes_f": shapes}


## The kernels' road_class (grass_place_common.glsli) over a pack() result: 0 open, 1 verge, 2 road. GrassQuery calls it
## with the pack the blades last sent the GPU, so both judge the same shapes in the same window.
static func classify(pk: Dictionary, origin: Vector2, p: Vector2, margin: float, verge_reach: float) -> int:
	if pk.is_empty() or int(pk.get("count", 0)) <= 0:
		return 0
	var b := Vector2i(floori((p.x - origin.x) / BIN_M), floori((p.y - origin.y) / BIN_M))
	if b.x < 0 or b.y < 0 or b.x >= BINS or b.y >= BINS:
		return 0
	var idx: PackedInt32Array = pk["idx_i"] if pk.has("idx_i") else (pk["idx"] as PackedByteArray).to_int32_array()
	var sh: PackedFloat32Array = pk["shapes_f"] if pk.has("shapes_f") else (pk["shapes"] as PackedByteArray).to_float32_array()
	var bi := b.y * BINS + b.x
	var base := BINS * BINS + 1
	var res := 0
	for k in range(idx[bi], idx[bi + 1]):
		var o := idx[base + k] * 8
		if sh[o + 6] < 0.5:
			var a := Vector2(sh[o], sh[o + 1])
			var ab := Vector2(sh[o + 2], sh[o + 3]) - a
			var ap := p - a
			var l2 := ab.length_squared()
			var t := ap.dot(ab) / l2 if l2 > 1e-6 else 0.0
			var fl := int(sh[o + 5] + 0.5)
			if (t < 0.0 and fl & 2) or (t > 1.0 and fl & 4):
				continue
			t = clampf(t, 0.0, 1.0)
			var d2 := (ap - ab * t).length_squared()
			var edge := sh[o + 4] + margin
			if d2 < edge * edge:
				return 2
			var far_e := edge + verge_reach
			if fl & 1 and d2 < far_e * far_e:
				res = 1
		else:
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
				return 2
	return res


static func _bin(bins: Array, id: int, origin: Vector2, box: Rect2) -> void:
	var b0 := ((box.position - origin) / BIN_M).floor()
	var b1 := ((box.end - origin) / BIN_M).floor()
	for by in range(maxi(int(b0.y), 0), mini(int(b1.y), BINS - 1) + 1):
		for bx in range(maxi(int(b0.x), 0), mini(int(b1.x), BINS - 1) + 1):
			# A packed array read from an untyped Array is a COPY: write it back.
			var l: PackedInt32Array = bins[by * BINS + bx]
			l.append(id)
			bins[by * BINS + bx] = l
