# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name LilyMesh
extends RefCounted
## A lily: a stem to stem_h with three narrow leaves and `flowers` six-tepal trumpets at the
## top. nod 0 faces up, ~0.85 faces out sideways. A tepal is a strip
## from the throat, flaring and curling back. LOW keeps two opposite tepals per flower, twice as
## wide; the rest collapse to the throat. The leaves collapse onto the stem in LOW (unseen past
## d_switch; keeping them would make LOW cost more than half of HIGH).


static func build(stem_h: float, flowers: int, tepal_len: float, tepal_w: float, nod: float) -> Array:
	var b := DecoMeshBuilder.new()
	b.plant_h = stem_h + tepal_len * (1.0 - nod) + 0.02
	var stem := PackedVector3Array()
	var sw := PackedFloat32Array()
	for s in 4:
		stem.append(Vector3(0, stem_h * s / 3.0, 0))
		sw.append(0.003)
	b.stem(stem, Vector3.RIGHT, sw)
	for l in 3:
		var la := l * 2.2
		var at := Vector3(0, stem_h * (0.3 + 0.2 * l), 0)
		var ld := Vector3(cos(la), 0.9, sin(la)).normalized()
		var leaf := PackedVector3Array([at, at + ld * stem_h * 0.08, at + ld * stem_h * 0.16])
		var lw := PackedFloat32Array([0.003, 0.007, 0.0])
		b.strip(leaf, ld.cross(Vector3.UP).normalized(), lw, DecoMeshBuilder.repeat(at, 3),
			DecoMeshBuilder.zeros(3), DecoMeshBuilder.STEM, false)
	for i in flowers:
		var a := i * 2.39996 + 0.7
		var out := Vector3(cos(a), 0.0, sin(a))
		var throat := Vector3(0.0, stem_h - 0.05 * i, 0.0) + out * 0.02 * nod
		var axis := Vector3.UP.lerp(out, nod).normalized()
		var ref := Vector3.FORWARD if absf(axis.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
		var u := axis.cross(ref).normalized()
		var v := axis.cross(u).normalized()
		for j in 6:
			var phi := TAU * j / 6.0
			var radial := u * cos(phi) + v * sin(phi)
			var pts := PackedVector3Array([throat,
				throat + axis * tepal_len * 0.45 + radial * tepal_len * 0.18,
				throat + axis * tepal_len * 0.8 + radial * tepal_len * 0.45,
				throat + axis * tepal_len * 0.85 + radial * tepal_len * 0.75])
			var w := PackedFloat32Array([tepal_w * 0.25, tepal_w * 0.8, tepal_w, tepal_w * 0.2])
			var across := axis.cross(radial).normalized()
			if j == 0 or j == 3:
				b.strip(pts, across, w, pts, DecoMeshBuilder.scaled(w, 2.0), DecoMeshBuilder.FLOWER, true)
			else:
				b.strip(pts, across, w, DecoMeshBuilder.repeat(throat, 4), DecoMeshBuilder.zeros(4),
					DecoMeshBuilder.FLOWER, false)
	return b.build()
