# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name LycorisMesh
extends RefCounted
## Higanbana (Lycoris radiata): a bare scape and an umbel of `flowers` flowers radiating at the
## top, each with six narrow recurved tepals and three long upcurved stamens: the red
## firework. LOW keeps one tepal per flower, four times as wide; stamens and the other tepals
## collapse to the throat.


static func build(scape_h: float, flowers: int, tepal_len: float, stamen_len: float) -> Array:
	var b := DecoMeshBuilder.new()
	b.plant_h = scape_h + stamen_len * 0.6
	var scape := PackedVector3Array([Vector3.ZERO, Vector3(0, scape_h * 0.5, 0), Vector3(0, scape_h, 0)])
	var sw := PackedFloat32Array([0.003, 0.0028, 0.0025])
	b.stem(scape, Vector3.RIGHT, sw)
	var top := Vector3(0, scape_h, 0)
	for i in flowers:
		var a := TAU * i / flowers
		var out := Vector3(cos(a), 0.35, sin(a)).normalized()
		var throat := top + out * 0.03
		var ped := PackedVector3Array([top, throat])
		var pw := PackedFloat32Array([0.0015, 0.0015])
		b.stem(ped, Vector3.UP.cross(out).normalized(), pw)
		var u := out.cross(Vector3.UP).normalized()
		var v := out.cross(u).normalized()
		for j in 6:
			var phi := TAU * j / 6.0 + a
			var radial := u * cos(phi) + v * sin(phi)
			var pts := PackedVector3Array([throat,
				throat + out * tepal_len * 0.5 + radial * tepal_len * 0.25,
				throat + out * tepal_len * 0.6 + radial * tepal_len * 0.55 + Vector3.UP * tepal_len * 0.2])
			var w := PackedFloat32Array([0.0015, 0.004, 0.001])
			var across := out.cross(radial).normalized()
			if j == 0:
				b.strip(pts, across, w, pts, DecoMeshBuilder.scaled(w, 4.0), DecoMeshBuilder.FLOWER, true)
			else:
				b.strip(pts, across, w, DecoMeshBuilder.repeat(throat, 3), DecoMeshBuilder.zeros(3),
					DecoMeshBuilder.FLOWER, false)
		for s in 3:
			var phi := TAU * s / 3.0 + a + 0.5
			var radial := u * cos(phi) + v * sin(phi)
			var st := PackedVector3Array([throat,
				throat + out * stamen_len * 0.6 + Vector3.UP * stamen_len * 0.2,
				throat + out * stamen_len * 0.9 + Vector3.UP * stamen_len * 0.5 + radial * stamen_len * 0.1])
			var stw := PackedFloat32Array([0.0008, 0.0008, 0.0006])
			b.strip(st, out.cross(Vector3.UP).normalized(), stw, DecoMeshBuilder.repeat(throat, 3),
				DecoMeshBuilder.zeros(3), DecoMeshBuilder.FLOWER, false)
	return b.build()
