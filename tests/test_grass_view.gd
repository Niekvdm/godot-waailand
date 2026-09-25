# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
class_name TestGrassView
extends GrassSuite
## The blades measure from the camera the renderer DRAWS (GrassBlades.view_of). With physics
## interpolation on, a camera moved in _physics_process is drawn from its interpolated transform
## (which get_frustum() is also built from), up to a tick behind
## global_transform. The params' eye must be the drawn one, and the frustum's sign-normalising
## "inside" point must sit inside the DRAWN frustum.


static func run() -> Dictionary:
	return await GrassSuite.run_suite(TestGrassView.new(), "grass_view")


func test_params_measure_from_the_drawn_camera() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var was := tree.physics_interpolation
	tree.physics_interpolation = true                   # the case this pins, whatever the project's setting
	var cam := Camera3D.new()
	tree.root.add_child(cam)
	var checked := 0
	var worst_lead := 0.0
	for i in 60:
		await tree.physics_frame
		cam.position += Vector3(0.9, 0.0, 0.3)          # ~57 m/s strafe at 60 Hz: a fast heli
		cam.rotation.y += deg_to_rad(2.0)
		await tree.process_frame
		var drawn := cam.get_camera_transform()
		var lead := drawn.origin.distance_to(cam.global_position)
		if lead < 0.05:
			continue                                    # this frame drew the tick itself
		worst_lead = maxf(worst_lead, lead)
		checked += 1
		var f := GrassBlades.camera_params(cam, 0.1)
		var eye := Vector3(f[0], f[1], f[2])
		assert_true(eye.distance_to(drawn.origin) < 1e-4,
			"the eye is the drawn camera (off by %.4f m; the physics transform leads by %.3f m)" % [eye.distance_to(drawn.origin), lead])
		# Every plane is oriented so a point just ahead of the DRAWN eye is inside.
		var ahead := drawn.origin - drawn.basis.z * 3.0
		var outside := 0
		for p in 6:
			var n := Vector3(f[4 + p * 4], f[5 + p * 4], f[6 + p * 4])
			if n.dot(ahead) + f[7 + p * 4] < 0.0:
				outside += 1
		assert_eq(outside, 0, "a point 3 m ahead of the drawn eye is inside every plane")
		if checked >= 5:
			break
	print("  view: %d interpolated frames checked, physics transform led by up to %.3f m" % [checked, worst_lead])
	assert_true(checked >= 3, "frames drew the camera between ticks (%d)" % checked)
	cam.queue_free()
	tree.physics_interpolation = was
