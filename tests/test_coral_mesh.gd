# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
class_name TestCoralMesh
extends GrassSuite
## The coral meshes: unit size (the colony's scale is its size in
## metres), a coarse LOW of their own, tops up and domes out (the winding rule: (a, b, c) faces
## (c - a).cross(b - a)), the pale growth edge and tips in the CENTRE part.


static func run() -> Dictionary:
	return await GrassSuite.run_suite(TestCoralMesh.new(), "coral_mesh")


## [a, b, c, unit normal by the winding rule, part] per non-degenerate triangle (a LOW-only triangle's
## HIGH half is a point, and is skipped).
static func _tris(m: ArrayMesh) -> Array:
	var arr := m.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var out := []
	for t in range(0, ix.size(), 3):
		var a := v[ix[t]]
		var b := v[ix[t + 1]]
		var c := v[ix[t + 2]]
		var n := (c - a).cross(b - a)
		if n.length_squared() < 1e-14:
			continue
		out.append([a, b, c, n.normalized(), uv[ix[t]].x])
	return out


static func _box(tris: Array) -> AABB:
	var bx := AABB(tris[0][0], Vector3.ZERO)
	for e in tris:
		for i in 3:
			bx = bx.expand(e[i])
	return bx


static func _count(tris: Array, part: float) -> int:
	var n := 0
	for e in tris:
		n += 1 if absf(float(e[4]) - part) < 0.01 else 0
	return n


func test_each_coral_has_a_high_and_a_coarser_low() -> void:
	for nm in ["table", "branching", "boulder"]:
		var ms := CoralMesh.build(nm)
		assert_eq(ms.size(), 2, "%s: a HIGH and a LOW mesh" % nm)
		if ms.size() != 2:
			continue
		var nh := _tris(ms[0]).size()
		var nl := _tris(ms[1]).size()
		assert_true(nl > 0 and nl * 3 < nh, "%s: LOW %d triangles against HIGH %d" % [nm, nl, nh])


func test_the_table_is_a_plate_on_a_stalk() -> void:
	var t := _tris(CoralMesh.build("table")[0])
	var bx := _box(t)
	assert_near(bx.size.x, 1.0, 0.12, "about 1 m across (%.2f)" % bx.size.x)
	assert_near(bx.end.y, 0.36, 0.02, "its rim 0.36 m up (%.2f)" % bx.end.y)
	var up := 0
	for e in t:
		if absf(float(e[4]) - DecoMeshBuilder.FLOWER) < 0.01 and (e[3] as Vector3).y > 0.9:
			up += 1
	assert_eq(up, _count(t, DecoMeshBuilder.FLOWER), "every plate triangle faces up")
	assert_true(_count(t, DecoMeshBuilder.CENTRE) > 0, "a pale growth band at the rim")
	assert_true(_count(t, DecoMeshBuilder.STEM) > 0, "a stalk")


func test_the_branching_colony_has_pale_tips() -> void:
	var t := _tris(CoralMesh.build("branching")[0])
	var bx := _box(t)
	assert_true(bx.end.y > 0.6 and bx.end.y < 1.0, "0.6-1.0 m tall (%.2f)" % bx.end.y)
	assert_true(_count(t, DecoMeshBuilder.CENTRE) > 0, "pale tips")
	assert_true(_count(t, DecoMeshBuilder.FLOWER) > _count(t, DecoMeshBuilder.CENTRE), "mostly body")
	var low_tip := 0
	for e in t:
		if absf(float(e[4]) - DecoMeshBuilder.CENTRE) < 0.01 and minf(e[0].y, minf(e[1].y, e[2].y)) < 0.3:
			low_tip += 1
	assert_eq(low_tip, 0, "the tips are high up, not at the base")


func test_the_boulder_is_a_dome_facing_out() -> void:
	var t := _tris(CoralMesh.build("boulder")[0])
	var bx := _box(t)
	assert_true(bx.position.y > -1e-4, "it sits on the rock (%.3f)" % bx.position.y)
	assert_near(bx.end.y, 0.55, 0.03, "0.55 m tall (%.2f)" % bx.end.y)
	assert_near(bx.size.x, 1.0, 0.15, "about 1 m across (%.2f)" % bx.size.x)
	var out := 0
	for e in t:
		var ctr: Vector3 = (e[0] + e[1] + e[2]) / 3.0
		if (e[3] as Vector3).dot(ctr) > 0.0:
			out += 1
	assert_eq(out, t.size(), "every triangle faces out")
