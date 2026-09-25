# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
class_name TestGrassGroupStamper
extends GrassSuite
## The ready-made feeder: every Node3D in a group within max_height of the
## ground pushes the grass, from where it was to where it is (a trail, not dots); one above it does not; crush lays the
## grass along the way it moves.


class _Flat extends GrassGroupStamper:
	func _ground_y(_p: Vector3) -> float:
		return 0.0


static func run() -> Dictionary:
	return await GrassSuite.run_suite(TestGrassGroupStamper.new(), "grass_group_stamper")


func test_walkers_push_the_grass() -> void:
	var b := GrassBlades.new()
	var tree := Engine.get_main_loop() as SceneTree
	var root := Node.new()
	tree.root.add_child(root)
	await tree.process_frame               # the batch runs suites from _initialize: the root takes children on a frame
	var s := _Flat.new()
	s.blades = b
	s.group = &"test_grass_walkers"
	root.add_child(s)
	s.set_process(false)                   # fed by hand below, one frame at a time
	var walker := Node3D.new()
	walker.add_to_group(&"test_grass_walkers")
	root.add_child(walker)
	walker.global_position = Vector3(1.0, 0.2, 1.0)
	var flier := Node3D.new()
	flier.add_to_group(&"test_grass_walkers")
	root.add_child(flier)
	flier.global_position = Vector3(3.0, 2.0, 3.0)
	s._feed(0.016)
	var st: Array = b.interaction._stamps
	assert_eq(st.size(), 1, "the walker pushes; the one 2 m up does not")
	assert_true(st[0][0] == Vector3(1.0, 0.2, 1.0) and st[0][3] == GrassInteractionField.KIND_PUSH
		and is_equal_approx(st[0][2], 0.4), "a push where it stands, its radius")
	b.interaction.payload()
	walker.global_position = Vector3(2.0, 0.2, 1.0)
	s._feed(0.016)
	st = b.interaction._stamps
	assert_true(st[0][0] == Vector3(1.0, 0.2, 1.0) and st[0][1] == Vector3(2.0, 0.2, 1.0), "a trail from where it was")
	b.interaction.payload()
	s.crush = true
	walker.global_position = Vector3(3.0, 0.2, 1.0)
	s._feed(0.016)
	st = b.interaction._stamps
	assert_true(st[0][3] == GrassInteractionField.KIND_CRUSH and st[0][5] == Vector2(1.0, 0.0),
		"crush: laid along the way it moves")
	root.queue_free()
	b.free()
