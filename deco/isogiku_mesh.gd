# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name IsogikuMesh
extends RefCounted
## Chrysanthemum pacificum: a cluster of `heads` yellow BUTTONS on short stalks (the species is
## rayless: its heads are discs). A head is a low `sides`-gon dome. LOW keeps one triangle per
## head, grown to the disc's area (circumradius sqrt(2) x head_r for a hexagon); the rest
## collapse to the head's centre.


static func build(heads: int, stalk_h: float, spread: float, head_r: float, sides: int) -> Array:
	var b := DecoMeshBuilder.new()
	b.plant_h = stalk_h + head_r
	for i in heads:
		var ang := i * 2.39996
		var rr := spread * sqrt((i + 0.5) / heads)
		var hy := stalk_h * (0.85 + 0.15 * float((i * 7) % 5) / 4.0)
		var c := Vector3(cos(ang) * rr, hy, sin(ang) * rr)
		var foot := Vector3(c.x * 0.3, 0.0, c.z * 0.3)
		var stalk := PackedVector3Array([foot, (foot + c) * 0.5, c])
		var sw := PackedFloat32Array([0.0015, 0.0013, 0.0012])
		b.stem(stalk, Vector3.RIGHT, sw)
		var top := c + Vector3.UP * head_r * 0.35
		var lo_r := head_r * 1.414
		var lo_tri := []
		for m in 3:
			var a := TAU * m / 3.0 + ang
			lo_tri.append(c + Vector3(cos(a), 0.0, sin(a)) * lo_r)
		for s in sides:
			var a0 := TAU * s / sides
			var a1 := TAU * (s + 1) / sides
			var r0 := c + Vector3(cos(a0), 0.0, sin(a0)) * head_r
			var r1 := c + Vector3(cos(a1), 0.0, sin(a1)) * head_r
			var keep := s == 0
			var lo := [lo_tri[0], lo_tri[1], lo_tri[2]] if keep else [c, c, c]
			b.tri([top, r1, r0], lo, DecoMeshBuilder.FLOWER, Vector3(0.0, 1.0, 1.0), keep)
	return b.build()
