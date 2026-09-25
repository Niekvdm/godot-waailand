# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
class_name TestBladeMesh
extends GrassSuite


static func run() -> Dictionary:
	return await GrassSuite.run_suite(TestBladeMesh.new(), "blade_mesh")
## The blade meshes. The WINDING test pins the normal convention the shader relies on:
## Godot's front face along N satisfies (v2 - v0).cross(v1 - v0).dot(N) > 0 (measured on
## shipping geometry). With placeholder vertices (side - 0.5, t, 0), where X is the side axis
## S, Y is up and Z is the facing F, every triangle must face -Z, because the
## shader writes N = cross(dB/dt, S) = -F.


func _tris(mesh: ArrayMesh) -> Array:
	var a := mesh.surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var out := []
	for i in range(0, idx.size(), 3):
		out.append([v[idx[i]], v[idx[i + 1]], v[idx[i + 2]]])
	return out


func test_vertex_and_triangle_counts() -> void:
	var hi := BladeMesh.build(BladeMesh.HIGH_PAIRS, BladeMesh.GAMMA)
	var lo := BladeMesh.build(BladeMesh.LOW_PAIRS, BladeMesh.GAMMA)
	assert_eq(hi.surface_get_array_len(0), 15, "HIGH has 15 vertices")
	assert_eq(lo.surface_get_array_len(0), 7, "LOW has 7 vertices")
	assert_eq(hi.surface_get_array_index_len(0), 39, "HIGH has 13 triangles")
	assert_eq(lo.surface_get_array_index_len(0), 15, "LOW has 5 triangles")


func test_levels() -> void:
	var lv := BladeMesh.levels(3, 0.85)
	assert_eq(lv.size(), 3, "three pairs")
	assert_near(lv[0], 0.0, 1e-7, "root level")
	assert_near(lv[1], pow(1.0 / 3.0, 0.85), 1e-6, "second level")
	assert_near(lv[2], pow(2.0 / 3.0, 0.85), 1e-6, "third level")


func test_every_triangle_faces_minus_z() -> void:
	for pairs in [BladeMesh.HIGH_PAIRS, BladeMesh.LOW_PAIRS]:
		var bad := 0
		for t in _tris(BladeMesh.build(pairs, BladeMesh.GAMMA)):
			var n: Vector3 = (t[2] - t[0]).cross(t[1] - t[0])
			if n.dot(Vector3(0, 0, -1)) <= 0.0:
				bad += 1
		assert_eq(bad, 0, "%d-pair mesh: triangles not front-facing along -Z" % pairs)


func test_uv_carries_side_and_t() -> void:
	var a := BladeMesh.build(BladeMesh.HIGH_PAIRS, BladeMesh.GAMMA).surface_get_arrays(0)
	var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
	assert_eq(uv[0], Vector2(0, 0), "left root")
	assert_eq(uv[1], Vector2(1, 0), "right root")
	assert_eq(uv[14], Vector2(0.5, 1), "tip")
