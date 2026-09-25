# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name CoralMesh
extends RefCounted
## Hard corals, built at UNIT size: a colony's instance scale is its
## size in metres: a TABLE (a plate 1 m across, 0.3 m off the rock on a stalk), a BRANCHING colony
## (staghorn limbs, about 0.9 m tall), a BOULDER (a lumpy dome 1 m across). The body is FLOWER (the
## palette: one colour per colony), the living growth edge and tips CENTRE (the kind's centre colour), the
## table's stalk STEM. Every FLOWER triangle has v = 1: the deco shader tints a FLOWER part's base
## (v < 0.4) with the centre colour when centre_col.a > 0, and a coral's body has no base.
## HIGH and LOW are separate shapes: a HIGH-only triangle collapses onto a point at morph 1 and a
## LOW-only one grows from that point (DecoMeshBuilder with degenerate halves), so HIGH at morph 1 IS LOW.
## Winding: (a, b, c) faces (c - a).cross(b - a); tops face up, domes and limbs face out.

const ONE := Vector3(1.0, 1.0, 1.0)


static func build(nm: String) -> Array:
	match nm:
		"table": return table()
		"branching": return branching()
		"boulder": return boulder()
	push_error("CoralMesh: no coral '%s'" % nm)
	return []


## A plate 1 m across: a fan from the centre, upturned toward a ragged rim, a pale growth band past it, on
## a hexagonal stalk. LOW: an octagonal plate, no stalk.
static func table(segs: int = 24) -> Array:
	var b := DecoMeshBuilder.new()
	b.plant_h = 0.36
	var c := Vector3(0.0, 0.3, 0.0)
	var ring := []
	var rim := []
	for i in segs:
		var a := TAU * i / segs
		var d := Vector3(cos(a), 0.0, sin(a))
		var r := 0.5 * (0.9 + 0.2 * _n(i, 1))
		ring.append(c + d * r * 0.9 + Vector3(0.0, 0.05, 0.0))
		rim.append(c + d * r + Vector3(0.0, 0.06, 0.0))
	for i in segs:
		var j := (i + 1) % segs
		_hi(b, [c, ring[i], ring[j]], DecoMeshBuilder.FLOWER, c)
		_hi(b, [ring[i], rim[j], ring[j]], DecoMeshBuilder.CENTRE, c)
		_hi(b, [ring[i], rim[i], rim[j]], DecoMeshBuilder.CENTRE, c)
	for i in 6:
		var d0 := Vector3(cos(TAU * i / 6.0), 0.0, sin(TAU * i / 6.0))
		var d1 := Vector3(cos(TAU * (i + 1) / 6.0), 0.0, sin(TAU * (i + 1) / 6.0))
		_hi(b, [d0 * 0.08, d1 * 0.08, c + d1 * 0.05], DecoMeshBuilder.STEM, c)
		_hi(b, [d0 * 0.08, c + d1 * 0.05, c + d0 * 0.05], DecoMeshBuilder.STEM, c)
	for k in 8:
		var o0 := c + Vector3(cos(TAU * k / 8.0), 0.0, sin(TAU * k / 8.0)) * 0.5 + Vector3(0.0, 0.05, 0.0)
		var o1 := c + Vector3(cos(TAU * (k + 1) / 8.0), 0.0, sin(TAU * (k + 1) / 8.0)) * 0.5 + Vector3(0.0, 0.05, 0.0)
		_lo(b, [c, o0, o1], DecoMeshBuilder.FLOWER, c)
	return b.build()


## Staghorn: `limbs` tapered three-sided limbs from a common base, each forking once; the last 15 % of
## every limb end is the pale living tip. LOW: three flat blades.
static func branching(limbs: int = 7) -> Array:
	var b := DecoMeshBuilder.new()
	b.plant_h = 0.9
	var o := Vector3.ZERO
	for k in limbs:
		var az := k * 2.39996
		var tilt := deg_to_rad(15.0 + 35.0 * _n(k, 2))
		var ln := 0.55 + 0.3 * _n(k, 3)
		var dir := Vector3(cos(az) * sin(tilt), cos(tilt), sin(az) * sin(tilt))
		var foot := Vector3(cos(az), 0.0, sin(az)) * 0.06
		var fork := foot + dir * ln * 0.6
		_limb(b, foot, fork, 0.035, 0.025, false, o)
		_limb(b, fork, foot + dir * ln, 0.025, 0.012, true, o)
		var side := (dir + Vector3(-sin(az), 0.0, cos(az)) * 0.6).normalized()
		_limb(b, fork, fork + side * ln * 0.35, 0.02, 0.01, true, o)
	for k in 3:
		var az := TAU * k / 3.0 + 0.4
		var d := Vector3(cos(az), 0.0, sin(az))
		var s := Vector3(-d.z, 0.0, d.x) * 0.06
		var top := d * 0.25 + Vector3(0.0, 0.8, 0.0)
		_lo(b, [-s, s, top + s], DecoMeshBuilder.FLOWER, o)
		_lo(b, [-s, top + s, top - s], DecoMeshBuilder.FLOWER, o)
	return b.build()


## A lumpy dome 1 m across and 0.55 m tall: `bands` rings of `around` points, each radius jittered (the
## pole kept round). LOW: a smooth 6 x 2 dome.
static func boulder(around: int = 12, bands: int = 4) -> Array:
	var b := DecoMeshBuilder.new()
	b.plant_h = 0.55
	var o := Vector3.ZERO
	var hi := _dome(around, bands, true)
	for j in bands:
		for i in around:
			var i1 := (i + 1) % around
			_hi(b, [hi[j][i], hi[j][i1], hi[j + 1][i1]], DecoMeshBuilder.FLOWER, o)
			if j < bands - 1:
				_hi(b, [hi[j][i], hi[j + 1][i1], hi[j + 1][i]], DecoMeshBuilder.FLOWER, o)
	var lo := _dome(6, 2, false)
	for j in 2:
		for i in 6:
			var i1 := (i + 1) % 6
			_lo(b, [lo[j][i], lo[j][i1], lo[j + 1][i1]], DecoMeshBuilder.FLOWER, o)
			if j < 1:
				_lo(b, [lo[j][i], lo[j + 1][i1], lo[j + 1][i]], DecoMeshBuilder.FLOWER, o)
	return b.build()


static func _dome(around: int, bands: int, lumpy: bool) -> Array:
	var rows := []
	for j in bands + 1:
		var el := PI * 0.5 * j / bands
		var row := []
		for i in around:
			var az := TAU * i / around
			var r := 0.5
			if lumpy and j < bands:
				r *= 0.88 + 0.24 * _n(j * 31 + i, 4)
			row.append(Vector3(cos(az) * cos(el) * r, sin(el) * r * 1.1, sin(az) * cos(el) * r))
		rows.append(row)
	return rows


## A tapered three-sided limb p0 -> p1 in HIGH; its last 15 % CENTRE (the living tip) when `tip`.
static func _limb(b: DecoMeshBuilder, p0: Vector3, p1: Vector3, r0: float, r1: float, tip: bool,
		c: Vector3) -> void:
	var ax := (p1 - p0).normalized()
	var u := ax.cross(Vector3.RIGHT if absf(ax.x) < 0.9 else Vector3.BACK).normalized()
	var w := ax.cross(u)
	var m := p0.lerp(p1, 0.85) if tip else p1
	var rm := lerpf(r0, r1, 0.85) if tip else r1
	_prism(b, p0, m, r0, rm, u, w, DecoMeshBuilder.FLOWER, c)
	if tip:
		_prism(b, m, p1, rm, r1 * 0.5, u, w, DecoMeshBuilder.CENTRE, c)


## Three outward-facing sides from p0 (radius r0) to p1 (radius r1) around the frame (u, w).
static func _prism(b: DecoMeshBuilder, p0: Vector3, p1: Vector3, r0: float, r1: float, u: Vector3,
		w: Vector3, part: float, c: Vector3) -> void:
	for s in 3:
		var e0 := u * cos(TAU * s / 3.0) + w * sin(TAU * s / 3.0)
		var e1 := u * cos(TAU * (s + 1) / 3.0) + w * sin(TAU * (s + 1) / 3.0)
		_hi(b, [p0 + e0 * r0, p1 + e1 * r1, p0 + e1 * r0], part, c)
		_hi(b, [p0 + e0 * r0, p1 + e0 * r1, p1 + e1 * r1], part, c)


## A triangle drawn in HIGH only: at morph 1 it collapses onto `c`.
static func _hi(b: DecoMeshBuilder, t: Array, part: float, c: Vector3) -> void:
	b.tri(t, [c, c, c], part, ONE, false)


## A triangle drawn in LOW only: at morph 0 it is a point at `c`.
static func _lo(b: DecoMeshBuilder, t: Array, part: float, c: Vector3) -> void:
	b.tri([c, c, c], t, part, ONE, true)


## A deterministic hash in [0, 1).
static func _n(i: int, salt: int) -> float:
	return fposmod(sin(float(i) * 12.9898 + float(salt) * 78.233) * 43758.5453, 1.0)
