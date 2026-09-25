# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name BladeMesh
extends RefCounted
## Blade strips: `pairs` left/right vertex pairs up the blade plus a tip. Vertices carry
## only UV = (side, t); the shader builds the shape. Positions are placeholders
## (side - 0.5, t, 0) for tools and tests. HIGH = 7 pairs (15 verts), LOW = 3 pairs (7).
## Levels are rescaled by GAMMA (< 1 packs vertices toward the tip, where the curve bends).

const HIGH_PAIRS := 7
const LOW_PAIRS := 3
const GAMMA := 0.85


static func levels(pairs: int, gamma: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for k in pairs:
		out.append(pow(float(k) / pairs, gamma))
	return out


static func build(pairs: int, gamma: float) -> ArrayMesh:
	var lv := levels(pairs, gamma)
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var tangents := PackedFloat32Array()
	for k in pairs:
		for side in [0.0, 1.0]:
			verts.append(Vector3(side - 0.5, lv[k], 0.0))
			uvs.append(Vector2(side, lv[k]))
	verts.append(Vector3(0.0, 1.0, 0.0))
	uvs.append(Vector2(0.5, 1.0))
	for i in verts.size():
		normals.append(Vector3(0, 0, -1))
		tangents.append_array([0.0, 1.0, 0.0, 1.0])
	var idx := PackedInt32Array()
	for k in pairs - 1:
		var l0 := k * 2
		var r0 := l0 + 1
		var l1 := l0 + 2
		var r1 := l0 + 3
		idx.append_array([l0, r0, l1, r0, r1, l1])
	var tip := pairs * 2
	idx.append_array([(pairs - 1) * 2, (pairs - 1) * 2 + 1, tip])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_TANGENT] = tangents
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m
