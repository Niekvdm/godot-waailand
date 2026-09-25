# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name DecoMeshBuilder
extends RefCounted
## Builds a decoration's HIGH and LOW meshes together. Every HIGH vertex carries
## its LOW position (CUSTOM0.xyz) and LOW normal (CUSTOM1.xyz); a triangle marked `keep` also
## goes into the LOW mesh at its LOW positions, and every other triangle's LOW positions
## coincide (it collapses to a point), so HIGH drawn at morph 1 IS the LOW mesh: the blade
## morph's rule for arbitrary geometry. Wind weight (height / plant_h) is stored for both ends:
## CUSTOM0.w at the HIGH position, CUSTOM1.w at the LOW one, and the shader morphs it too.
## UV = (part, along the part 0..1). Winding: triangle (a, b, c) faces (c - a).cross(b - a).

const STEM := 0.0      # stem, leaves: the kind's stem colour
const FLOWER := 1.0    # petals, plume strands, spikes: the palette colour by phase
const CENTRE := 2.0    # anthers, throats: the kind's centre colour

var plant_h := 1.0
var _hv := PackedVector3Array()
var _hn := PackedVector3Array()
var _huv := PackedVector2Array()
var _hc0 := PackedFloat32Array()
var _hc1 := PackedFloat32Array()
var _lv := PackedVector3Array()
var _ln := PackedVector3Array()
var _luv := PackedVector2Array()
var _lc0 := PackedFloat32Array()
var _lc1 := PackedFloat32Array()


## One triangle: `hi` and `lo` are 3 positions each, `v` the along-part value per vertex.
func tri(hi: Array, lo: Array, part: float, v: Vector3, keep: bool) -> void:
	var nh := _normal(hi)
	var nl := _normal(lo) if keep else nh
	for i in 3:
		var p: Vector3 = hi[i]
		var q: Vector3 = lo[i]
		var wh := clampf(p.y / plant_h, 0.0, 1.0)
		var wl := clampf(q.y / plant_h, 0.0, 1.0)
		_hv.append(p)
		_hn.append(nh)
		_huv.append(Vector2(part, v[i]))
		_hc0.append_array([q.x, q.y, q.z, wh])
		_hc1.append_array([nl.x, nl.y, nl.z, wl])
		if keep:
			_lv.append(q)
			_ln.append(nl)
			_luv.append(Vector2(part, v[i]))
			_lc0.append_array([q.x, q.y, q.z, wl])
			_lc1.append_array([nl.x, nl.y, nl.z, wl])


## A strip along the centre line `pts` with half-widths `w` across `side`; LOW likewise.
## A strip that vanishes in LOW passes repeat(point, n) and zeros(n).
func strip(pts: PackedVector3Array, side: Vector3, w: PackedFloat32Array,
		lo_pts: PackedVector3Array, lo_w: PackedFloat32Array, part: float, keep: bool) -> void:
	var n := pts.size()
	for i in n - 1:
		var v0 := float(i) / (n - 1)
		var v1 := float(i + 1) / (n - 1)
		var a := pts[i] - side * w[i]
		var b := pts[i] + side * w[i]
		var c := pts[i + 1] + side * w[i + 1]
		var d := pts[i + 1] - side * w[i + 1]
		var la := lo_pts[i] - side * lo_w[i]
		var lb := lo_pts[i] + side * lo_w[i]
		var lc := lo_pts[i + 1] + side * lo_w[i + 1]
		var ld := lo_pts[i + 1] - side * lo_w[i + 1]
		tri([a, b, c], [la, lb, lc], part, Vector3(v0, v0, v1), keep)
		tri([a, c, d], [la, lc, ld], part, Vector3(v0, v1, v1), keep)


## A stem, stalk or pedicel: in LOW it collapses onto its base. Past d_switch a 2-3 mm stem is
## a fraction of a pixel, yet stems can be half of a plant's LOW triangles (and LOW decorations
## dominate the decorations' cost).
func stem(pts: PackedVector3Array, side: Vector3, w: PackedFloat32Array) -> void:
	strip(pts, side, w, repeat(pts[0], pts.size()), zeros(pts.size()), STEM, false)


func build() -> Array:
	return [_mesh(_hv, _hn, _huv, _hc0, _hc1), _mesh(_lv, _ln, _luv, _lc0, _lc1)]


static func scaled(w: PackedFloat32Array, k: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for x in w:
		out.append(x * k)
	return out


static func zeros(n: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	return out


static func repeat(p: Vector3, n: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in n:
		out.append(p)
	return out


static func _normal(p: Array) -> Vector3:
	var n: Vector3 = ((p[2] as Vector3) - p[0]).cross((p[1] as Vector3) - p[0])
	return n.normalized() if n.length_squared() > 1e-16 else Vector3.UP


## Indexed: identical vertices (every attribute equal) are shared. Flat-shaded triangles share
## only where they are coplanar (both halves of a flat quad), still ~1/3 fewer vertices than
## one vertex per triangle corner, and the vertex shader runs twice per vertex (motion vectors).
static func _mesh(v: PackedVector3Array, n: PackedVector3Array, uv: PackedVector2Array,
		c0: PackedFloat32Array, c1: PackedFloat32Array) -> ArrayMesh:
	var seen := {}
	var ov := PackedVector3Array()
	var on := PackedVector3Array()
	var ouv := PackedVector2Array()
	var oc0 := PackedFloat32Array()
	var oc1 := PackedFloat32Array()
	var idx := PackedInt32Array()
	for i in v.size():
		var key := [v[i], n[i], uv[i], c0.slice(i * 4, i * 4 + 4), c1.slice(i * 4, i * 4 + 4)]
		var k := str(key)
		if not seen.has(k):
			seen[k] = ov.size()
			ov.append(v[i])
			on.append(n[i])
			ouv.append(uv[i])
			oc0.append_array(c0.slice(i * 4, i * 4 + 4))
			oc1.append_array(c1.slice(i * 4, i * 4 + 4))
		idx.append(seen[k])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = ov
	arr[Mesh.ARRAY_NORMAL] = on
	arr[Mesh.ARRAY_TEX_UV] = ouv
	arr[Mesh.ARRAY_CUSTOM0] = oc0
	arr[Mesh.ARRAY_CUSTOM1] = oc1
	arr[Mesh.ARRAY_INDEX] = idx
	var fmt := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) \
		| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, fmt)
	return m
