# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name SpikeMesh
extends RefCounted
## A stem and a spindle-shaped spike of `facets` crossed strips (a cylinder from any side):
## a silky grass spike, a toadflax. LOW keeps one facet, widened; the rest
## collapse to the spike's middle.


static func build(stem_h: float, spike_len: float, spike_w: float, facets: int) -> Array:
	var b := DecoMeshBuilder.new()
	b.plant_h = stem_h + spike_len
	var stem := PackedVector3Array([Vector3.ZERO, Vector3(0, stem_h * 0.5, 0), Vector3(0, stem_h, 0)])
	var sw := PackedFloat32Array([0.0025, 0.002, 0.0018])
	b.stem(stem, Vector3.RIGHT, sw)
	var pts := PackedVector3Array()
	var w := PackedFloat32Array()
	for s in 5:
		var t := s / 4.0
		pts.append(Vector3(0, stem_h + spike_len * t, 0))
		w.append(spike_w * (0.55 + 0.45 * sin(PI * t)) * (1.0 - t * t * t))
	var mid := Vector3(0, stem_h + spike_len * 0.5, 0)
	for f in facets:
		var ang := PI * f / facets
		var side := Vector3(cos(ang), 0.0, sin(ang))
		if f == 0:
			b.strip(pts, side, w, pts, DecoMeshBuilder.scaled(w, 1.5), DecoMeshBuilder.FLOWER, true)
		else:
			b.strip(pts, side, w, DecoMeshBuilder.repeat(mid, 5), DecoMeshBuilder.zeros(5),
				DecoMeshBuilder.FLOWER, false)
	return b.build()
