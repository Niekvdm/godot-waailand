# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name GrassWaterGroup
extends GrassFeeder
## Every visible node in the group `group` ("waailand_water") is a water source (GrassBlades.set_water): a
## MeshInstance3D with a PlaneMesh or QuadMesh gives its rectangle (turned with the node), a Path3D the polygon of
## its curve's points (read as closed); the surface is the node's global height; the kind is its `water_kind`
## metadata (else "Water"). Hiding a node (a paddy drained after the harvest) takes its water away, and what floats
## on it. It looks at the group every frame and moves its revision when anything changed, so the blades snapshot
## again. List it in the config's editor_inputs and it serves the editor preview too.

## The group whose visible nodes are water, unless `group` names another.
const GROUP := &"waailand_water"
## The kind of a source without `water_kind` metadata.
const DEFAULT_KIND := "Water"
## At most this many points of a path's curve (the kernels walk every vertex of a polygon they test).
const MAX_PATH_POINTS := 64

## The group whose nodes are water.
@export var group: StringName = GROUP

var _sig := ""
var _rev := 0


func _feed(_dt: float) -> void:
	if blades != null and blades.water.source != self:
		blades.set_water(self)
	var s := _signature()
	if s != _sig:
		_sig = s
		_rev += 1


## Moves whenever a source appears, goes, moves, changes its size, height or kind (GrassWater's optional revision).
func revision() -> int:
	return _rev


## No visible source in the group.
func is_empty() -> bool:
	return _nodes().is_empty()


## The sources whose outline reaches the window (GrassWater's snapshot): outlines, heights, kinds.
func snapshot(origin: Vector2, window: float, pad: float) -> Dictionary:
	var polys: Array[PackedVector2Array] = []
	var heights := PackedFloat32Array()
	var kinds := PackedStringArray()
	var box := Rect2(origin - Vector2.ONE * pad, Vector2.ONE * (window + 2.0 * pad))
	for n in _nodes():
		var poly := outline(n)
		var r := Rect2(poly[0], Vector2.ZERO)
		for v in poly:
			r = r.expand(v)
		if not r.intersects(box, true):
			continue
		polys.append(poly)
		heights.append(n.global_position.y)
		kinds.append(String(n.get_meta(&"water_kind", DEFAULT_KIND)))
	return {"polys": polys, "heights": heights, "kinds": kinds}


## A node's outline in world x/z; empty when it is no source (another mesh, too few points, edge-on).
static func outline(n: Node3D) -> PackedVector2Array:
	var out := PackedVector2Array()
	if n is MeshInstance3D and (n as MeshInstance3D).mesh is PlaneMesh:     # a QuadMesh is a PlaneMesh
		var pm := (n as MeshInstance3D).mesh as PlaneMesh
		var h := pm.size * 0.5
		for c: Vector2 in [Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(h.x, h.y), Vector2(-h.x, h.y)]:
			var l := Vector3(c.x, 0.0, c.y)
			if pm.orientation == PlaneMesh.FACE_Z:
				l = Vector3(c.x, c.y, 0.0)
			elif pm.orientation == PlaneMesh.FACE_X:
				l = Vector3(0.0, c.y, c.x)
			var w := n.global_transform * (l + pm.center_offset)
			out.append(Vector2(w.x, w.z))
	elif n is Path3D and (n as Path3D).curve != null and (n as Path3D).curve.point_count >= 3:
		var c := (n as Path3D).curve
		var step := ceili(float(c.point_count) / MAX_PATH_POINTS)
		for i in range(0, c.point_count, step):
			var w := n.global_transform * c.get_point_position(i)
			out.append(Vector2(w.x, w.z))
	if out.size() < 3 or absf(_area(out)) < 1e-4:
		return PackedVector2Array()
	return out


static func _area(p: PackedVector2Array) -> float:
	var a := 0.0
	for i in p.size():
		a += p[i].cross(p[(i + 1) % p.size()])
	return 0.5 * a


func _nodes() -> Array[Node3D]:
	var out: Array[Node3D] = []
	if not is_inside_tree():
		return out
	for n in get_tree().get_nodes_in_group(group):
		var q := n as Node3D
		if q != null and q.is_visible_in_tree() and not outline(q).is_empty():
			out.append(q)
	return out


## What the snapshot depends on: every source's outline, height and kind.
func _signature() -> String:
	var parts := PackedStringArray()
	for n in _nodes():
		parts.append("%s|%s|%s" % [outline(n), n.global_position.y, n.get_meta(&"water_kind", DEFAULT_KIND)])
	return "\n".join(parts)
