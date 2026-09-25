# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name PlumeMesh
extends RefCounted
## A grass plume (Miscanthus, Calamagrostis). UNIT HEIGHT: y = 1 is the top of the host tussock
## (the kernel scales by the host's blade height). A thin stem rises through the tussock and on
## as a rachis; `strands` racemes leave it in a golden-angle spiral, rising, spreading by
## `spread` and drooping by `droop`. LOW keeps every `lo_every`-th strand, widened; the rest
## collapse onto their attachment point.


static func build(strands: int, head_len: float, spread: float, droop: float, strand_w: float,
		lo_every: int) -> Array:
	var b := DecoMeshBuilder.new()
	b.plant_h = 1.0 + head_len
	var stem := PackedVector3Array([Vector3(0, 0, 0), Vector3(0, 0.5, 0), Vector3(0, 1.0, 0),
		Vector3(0, 1.0 + head_len * 0.6, 0)])
	var sw := PackedFloat32Array([0.004, 0.0035, 0.003, 0.002])
	b.stem(stem, Vector3.RIGHT, sw)
	for k in strands:
		var ang := k * 2.39996
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		var base := Vector3(0.0, 1.0 + head_len * 0.6 * float(k) / strands, 0.0)
		var pts := PackedVector3Array()
		var w := PackedFloat32Array()
		for s in 5:
			var t := s / 4.0
			pts.append(base + Vector3.UP * head_len * 0.8 * t + dir * spread * t - Vector3.UP * droop * t * t)
			w.append(strand_w * (1.0 - 0.6 * t))
		var across := dir.cross(Vector3.UP).normalized()
		if k % lo_every == 0:
			b.strip(pts, across, w, pts, DecoMeshBuilder.scaled(w, 0.5 + 0.5 * lo_every),
				DecoMeshBuilder.FLOWER, true)
		else:
			b.strip(pts, across, w, DecoMeshBuilder.repeat(base, 5), DecoMeshBuilder.zeros(5),
				DecoMeshBuilder.FLOWER, false)
	return b.build()
