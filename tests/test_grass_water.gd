# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
class_name TestGrassWater
extends GrassSuite
## Water sources: GrassWater bins a source's polygons per window and top() finds the highest surface over a point (the
## sea's too); GrassWaterGroup turns the group's visible planes and paths into polygons, with their heights and kinds,
## and moves its revision when one changes.


## A source of fixed polygons (the other water suites use it too).
class _Ponds:
	var polys: Array = []
	var heights := PackedFloat32Array()
	var kinds := PackedStringArray()

	func is_empty() -> bool:
		return polys.is_empty()

	func snapshot(_origin: Vector2, _window: float, _pad: float) -> Dictionary:
		return {"polys": polys, "heights": heights, "kinds": kinds}


static func run() -> Dictionary:
	return await GrassSuite.run_suite(TestGrassWater.new(), "grass_water")


static func _square(c: Vector2, half: float) -> PackedVector2Array:
	return PackedVector2Array([c + Vector2(-half, -half), c + Vector2(half, -half), c + Vector2(half, half),
		c + Vector2(-half, half)])


## [pack, origin] of a source around the origin, kinds Vijver 0 and Sloot 1.
static func _pack(src) -> Array:
	var w := GrassWater.new()
	w.source = src
	var o := w.window_for(Vector2.ZERO)
	return [w.pack(o, {"vijver": 0, "sloot": 1}), o]


func test_the_highest_surface_wins() -> void:
	var s := _Ponds.new()
	s.polys = [_square(Vector2(0, 0), 10.0), _square(Vector2(5, 0), 3.0)]
	s.heights = PackedFloat32Array([1.0, 2.0])
	s.kinds = PackedStringArray(["Vijver", "Sloot"])
	var pk_o := _pack(s)
	var pk: Dictionary = pk_o[0]
	var o: Vector2 = pk_o[1]
	assert_eq(int(pk["count"]), 2, "two polygons")
	var no_sea := Vector3(0.0, -1.0, 0.0)
	assert_eq(GrassWater.top(pk, o, Vector2(-5, 0), no_sea), Vector4(1.0, 0.0, 0.0, 0.0), "the pond alone")
	assert_eq(GrassWater.top(pk, o, Vector2(5, 0), no_sea), Vector4(2.0, 1.0, 0.0, 0.0), "the higher one wins")
	assert_eq(GrassWater.top(pk, o, Vector2(30, 0), no_sea).x, GrassWater.NONE, "outside: none")
	var sea := Vector3(1.5, 3.0, 1.0)
	assert_eq(GrassWater.top(pk, o, Vector2(-5, 0), sea), Vector4(1.5, 3.0, GrassTypes.SEA_SHORE_M, 1.0),
		"a sea above the pond wins, with its shore")
	assert_eq(GrassWater.top(pk, o, Vector2(5, 0), sea).x, 2.0, "a pond above the sea wins")
	assert_eq(GrassWater.top(pk, o, Vector2(30, 0), sea).x, 1.5, "the sea everywhere else")


func test_kinds_and_limits() -> void:
	var s := _Ponds.new()
	s.polys = [_square(Vector2.ZERO, 2.0), PackedVector2Array([Vector2.ZERO, Vector2.ONE]),
		_square(Vector2(1000, 0), 2.0)]
	s.heights = PackedFloat32Array([0.5, 0.5, 0.5])
	s.kinds = PackedStringArray(["Tanbo", "Vijver", "Vijver"])
	var pk_o := _pack(s)
	var pk: Dictionary = pk_o[0]
	assert_eq(int(pk["count"]), 2, "a two-point outline is no water; one far outside still counts but bins nowhere")
	assert_eq(GrassWater.top(pk, pk_o[1], Vector2.ZERO, Vector3(0, -1, 0)).y, -1.0, "a kind the table lacks is -1")
	var empty := _pack(_Ponds.new())
	assert_eq(int(empty[0]["count"]), 0, "an empty source")
	assert_eq(GrassWater.top(empty[0], empty[1], Vector2.ZERO, Vector3(0, -1, 0)).x, GrassWater.NONE, "no water")


func test_the_group() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var host := Node3D.new()
	tree.root.add_child(host)
	await tree.process_frame               # the batch runs suites from _initialize: the root takes children on a frame
	var g := GrassWaterGroup.new()
	host.add_child(g)
	var pond := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(4.0, 2.0)
	pond.mesh = pm
	pond.position = Vector3(10.0, 1.9, 0.0)
	pond.rotation.y = PI * 0.5
	pond.set_meta(&"water_kind", "Vijver")
	pond.add_to_group(GrassWaterGroup.GROUP)
	host.add_child(pond)
	var path := Path3D.new()
	path.curve = Curve3D.new()
	for p in [Vector3(0, 0, 0), Vector3(3, 0, 0), Vector3(3, 0, 3), Vector3(0, 0, 3)]:
		path.curve.add_point(p)
	path.position = Vector3(-20.0, 0.5, 0.0)
	path.add_to_group(GrassWaterGroup.GROUP)
	host.add_child(path)
	var snap := g.snapshot(Vector2(-160, -160), 320.0, 0.0)
	assert_eq((snap["polys"] as Array).size(), 2, "two sources")
	var i := (snap["kinds"] as PackedStringArray).find("Vijver")
	var ring: PackedVector2Array = snap["polys"][i]
	var box := Rect2(ring[0], Vector2.ZERO)
	for v in ring:
		box = box.expand(v)
	assert_near(box.size.x, 2.0, 1e-3, "turned a quarter: 2 m along x")
	assert_near(box.size.y, 4.0, 1e-3, "and 4 m along z")
	assert_near(snap["heights"][i], 1.9, 1e-6, "the surface is the node's height")
	assert_true((snap["kinds"] as PackedStringArray).has(GrassWaterGroup.DEFAULT_KIND), "no metadata: Water")
	g._feed(0.0)
	var r0 := g.revision()
	g._feed(0.0)
	assert_eq(g.revision(), r0, "nothing changed: the same revision")
	pond.visible = false
	g._feed(0.0)
	assert_true(g.revision() != r0, "hidden: a new revision")
	assert_eq((g.snapshot(Vector2(-160, -160), 320.0, 0.0)["polys"] as Array).size(), 1, "and its water is gone")
	var edge_on := MeshInstance3D.new()
	var em := PlaneMesh.new()
	em.orientation = PlaneMesh.FACE_Z
	edge_on.mesh = em
	host.add_child(edge_on)
	assert_true(GrassWaterGroup.outline(edge_on).is_empty(), "a plane standing on its edge is no water")
	host.queue_free()
