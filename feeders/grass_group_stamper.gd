# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
class_name GrassGroupStamper
extends GrassFeeder
## Every Node3D in a group pushes (or crushes) the grass around it while it
## is within max_height of the ground under it: players, NPCs, animals. It stamps from where the node was last frame to
## where it is, so a fast mover leaves a trail. Nodes farther from the camera than the stamps reach are skipped (the
## interaction field holds 32 stamps a frame, every feeder together). Place it under a GrassBlades with its exports
## set, one per group; the config's lists hold scripts with default exports, so a project that feeds through the
## config lists a small subclass that sets `group`.

## The group whose nodes stamp the grass.
@export var group: StringName = &""
## The stamp's radius (m) around each node.
@export var radius := 0.4
## Crush (flatten, laid along the way it moves) instead of push (bend away).
@export var crush := false
## How hard each stamp pushes or crushes, 0..1.
@export var strength := 0.6
## Higher above the ground than this (m) a node stamps nothing (a jump, a ladder, a vehicle roof).
@export var max_height := 0.5

var _last := {}                  # instance id -> Vector3, where each node stamped last frame


func _feed(_dt: float) -> void:
	if group == &"":
		return
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	var here := Vector2(cam.global_position.x, cam.global_position.z) if cam != null else Vector2.ZERO
	var reach := blades.interaction_reach()
	var seen := {}
	for n in get_tree().get_nodes_in_group(group):
		var q := n as Node3D
		if q == null:
			continue
		var p := q.global_position
		if cam != null and Vector2(p.x, p.z).distance_to(here) > reach:
			continue
		var g := _ground_y(p)
		if is_nan(g) or p.y - g > max_height:
			continue
		var id := q.get_instance_id()
		var from: Vector3 = _last.get(id, p)
		if crush:
			blades.add_crush(from, p, radius, strength, Vector2(p.x - from.x, p.z - from.z))
		else:
			blades.add_push(from, p, radius, strength)
		_last[id] = p
		seen[id] = true
	for id in _last.keys():
		if not seen.has(id):
			_last.erase(id)


## The ground's height under `p` (the blades' Terrain3D), or NAN where there is none.
func _ground_y(p: Vector3) -> float:
	var data: Object = blades.terrain.get("data") if blades.terrain != null else null
	return float(data.call("get_height", p)) if data != null else NAN
