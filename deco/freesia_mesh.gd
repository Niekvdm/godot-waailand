# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name FreesiaMesh
extends RefCounted
## A freesia plant: `spikes` racemes (a real plant carries two or three), each a stem to stem_h
## then an arch of arch_len bending over, with `flowers` funnel flowers on its upper side,
## largest first. A flower is `petals` diamond petals around a funnel axis tilted up and
## forward. LOW keeps one petal per flower, grown to about the flower's spread; the others
## collapse to the flower's throat. (One spike of 2.8 cm flowers per plant covers 4 % of the ground, no
## carpet; two spikes of 3.5 cm flowers, like the plant, about 13 %.)


static func build(stem_h: float, arch_len: float, flowers: int, flower_r: float, petals: int,
		spikes: int = 2) -> Array:
	var b := DecoMeshBuilder.new()
	b.plant_h = stem_h + 0.06
	for sp in spikes:
		var rot := Basis(Vector3.UP, sp * 2.4)
		var sh := stem_h * (1.0 - 0.12 * sp)
		var stem := PackedVector3Array()
		var sw := PackedFloat32Array()
		for s in 4:
			stem.append(rot * Vector3(0, sh * s / 3.0, 0))
			sw.append(0.002)
		b.stem(stem, rot * Vector3.RIGHT, sw)
		var arch := PackedVector3Array()
		var aw := PackedFloat32Array()
		for s in 5:
			arch.append(rot * _arch(sh, arch_len, s / 4.0))
			aw.append(0.0018)
		b.stem(arch, rot * Vector3.RIGHT, aw)
		var axis := rot * Vector3(0.0, 0.85, 0.53).normalized()
		var u := rot * Vector3.RIGHT
		var v := axis.cross(u).normalized()
		for i in flowers:
			var t := 0.1 + 0.8 * float(i) / maxf(flowers - 1, 1)
			var c := rot * _arch(sh, arch_len, t) + Vector3.UP * 0.008
			var r := flower_r * (1.0 - 0.45 * t)
			for j in petals:
				var phi := TAU * j / petals
				var out := u * cos(phi) + v * sin(phi)
				var dirp := (axis * 0.75 + out * 0.66).normalized()
				var across := axis.cross(out).normalized()
				var tip := c + dirp * r
				var mid := c + dirp * r * 0.55
				var lft := mid - across * r * 0.3
				var rgt := mid + across * r * 0.3
				var keep := j == 0
				var k := 1.8
				var lo := [c, c + (lft - c) * k, c + (tip - c) * k, c + (rgt - c) * k] if keep else [c, c, c, c]
				b.tri([c, lft, tip], [lo[0], lo[1], lo[2]], DecoMeshBuilder.FLOWER, Vector3(0.0, 0.55, 1.0), keep)
				b.tri([c, tip, rgt], [lo[0], lo[2], lo[3]], DecoMeshBuilder.FLOWER, Vector3(0.0, 1.0, 0.55), keep)
	return b.build()


static func _arch(stem_h: float, arch_len: float, t: float) -> Vector3:
	return Vector3(0.0, stem_h + 0.03 * sin(PI * t) - 0.02 * t, arch_len * t)
