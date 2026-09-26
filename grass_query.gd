# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name GrassQuery
extends RefCounted
## What grows at a point: the kernel's texel decision
## (grass_place_common.glsli place_at and ground_rule, blade_place.glsl's slope rule) mirrored on the CPU over the same
## inputs. Exact but for one per-blade draw: where the kernel picks one of the four corners around a blade at random,
## in proportion to the growth each contributes, the query takes the corner that contributes most. The GPU works in
## 32-bit floats and this in 64-bit, so a point exactly on a patch or weight boundary may name the neighbour's species.
## The inputs are plain data and callables: the tests feed a synthetic ground, GrassBlades.sample() the live one.

const CORNERS: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]
const BAND_SOFT_M := 20.0        # an elevation band's edge wanders this much (m, total)
const MIX_FLOATS := 28           # GrassTerrainGrowth.MIX_VEC4 vec4 per texture id

var types: GrassTypes
var kinds: DecoKinds
var deco_state: Callable = func(_i: int) -> Vector2: return Vector2.ZERO   # a kind's (grow, phase) today
var allow := PackedFloat32Array()   # per texture id: GrassTerrainGrowth.table_for
var mix := PackedFloat32Array()     # per texture id MIX_FLOATS: GrassTerrainGrowth.mix_bytes as floats
var sea_level := NAN
var species_patch_m := 3.0
var all_grounds := false
var spacing := 1.0
var max_slope_cos := cos(deg_to_rad(55.0))
var road_pack := {}                 # GrassRoads.pack()'s last result ({}: no roads)
var road_origin := Vector2.ZERO
var water_pack := {}                # GrassWater.pack()'s last result ({}: no water sources)
var water_origin := Vector2.ZERO
var sea_kind := -1                  # the sea's water kind index (GrassWater.SEA_KIND in the table), -1: none
## The ground at Terrain3D vertex v: its grass map texel, its control word, its height (NAN: no region), and whether
## its map is still loading.
var texel: Callable = func(_v: Vector2i) -> Color: return GrassMaps.NEUTRAL
var control: Callable = func(_v: Vector2i) -> int: return 0
var height: Callable = func(_v: Vector2i) -> float: return NAN
var pending: Callable = func(_v: Vector2i) -> bool: return false


func sample(pos: Vector3) -> GrassSample:
	var s := GrassSample.new()
	var p := Vector2(pos.x, pos.z)
	var g := p / spacing
	var v0 := Vector2i(floori(g.x), floori(g.y))
	var f := g - Vector2(v0)
	var c: Array[Color] = []
	var cw: Array[int] = []
	var hs: Array[float] = []
	for k in 4:
		var v := v0 + CORNERS[k]
		var h: float = height.call(v)
		if is_nan(h):
			return s                           # a corner's region is not loaded: place_at's false
		s.pending = s.pending or bool(pending.call(v))
		c.append(texel.call(v))
		cw.append(int(control.call(v)))
		hs.append(h)
	var w: Array[float] = [(1.0 - f.x) * (1.0 - f.y), f.x * (1.0 - f.y), (1.0 - f.x) * f.y, f.x * f.y]
	var gh := lerpf(lerpf(hs[0], hs[1], f.x), lerpf(hs[2], hs[3], f.x), f.y)
	var wt := _water_top(p)
	var depth := wt.x - gh if wt.x > GrassWater.NONE else -100.0
	var shore := wt.z
	var r := 0.0
	var b := 0.0
	var total := 0.0
	var k := 0
	var k_growth := -1.0
	for i in 4:
		r += c[i].r * w[i]
		b += c[i].b * w[i]
		var wa := w[i] * _corner_allow(cw[i], c[i])
		total += wa
		if wa > k_growth:
			k_growth = wa
			k = i
	if total <= 0.0:
		return s
	var dens := r * (255.0 / 128.0) * total
	var ty := c[k].g8 - 1
	if ty >= 0:
		ty = mini(ty, 31)
		dens *= _eligible(ty, depth, shore)
	else:
		var cell := Vector2i(floori(p.x * 64.0), floori(p.y * 64.0))
		var hp := GrassHash.rnd3(cell, 13)
		var wk := cw[k]
		var sb := (wk >> 27) & 0x1F
		var so := (wk >> 22) & 0x1F
		var bl := float((wk >> 14) & 0xFF) / 255.0
		var fk := c[k].a < 0.5 or all_grounds
		var ab := _allow(sb)
		var ao := _allow(so)
		var gb := (1.0 - bl) * (absf(ab) if fk else maxf(ab, 0.0))
		var go := bl * (absf(ao) if fk else maxf(ao, 0.0))
		var slot := so if hp.z * (gb + go) < go else sb
		var h := gh + (GrassHash.rnd3(cell, 14).x - 0.5) * BAND_SOFT_M
		var jit := (Vector2(hp.x, hp.y) - Vector2(0.5, 0.5)) * species_patch_m * 0.35
		var pick := _mix_pick(slot, h, depth, _species_patch(p + jit, slot), shore)
		ty = int(pick.x)
		var best := pick.y
		if ty < 0 and fk:
			ty = types.fallback_slot
			best = _eligible(ty, depth, shore)
		if ty < 0:
			return s
		dens *= best
	# ground_rule: the live roads, then the type's bed stripes.
	if int(road_pack.get("count", 0)) > 0:
		var reach := lerpf(GrassRoads.VERGE_M.x, GrassRoads.VERGE_M.y, _value_noise(p * 0.05))
		var rc := GrassRoads.classify(road_pack, road_origin, p, GrassRoads.MARGIN_M, reach)
		if rc == 2:
			s.on_road = true
			return s
		if rc == 1 and dens > 0.0:
			ty = types.fallback_slot
			dens = maxf(dens, 0.85)
	var row: Dictionary = types.rows[ty] if ty < types.rows.size() else {}
	var bed := float(row.get("bed_m", 0.0))
	if bed > 0.0:
		var ang := deg_to_rad(float(row.get("stripe_angle_deg", 0.0)))
		if fposmod(-sin(ang) * p.x + cos(ang) * p.y, bed + float(row.get("path_m", 0.0))) >= bed:
			return s
	if _ground_normal(p).y < max_slope_cos or dens <= 0.0:
		return s
	var tr := types.row(ty)
	s.species = StringName(tr.get("name", ""))
	s.density = dens
	s.forced = c[k].a < 0.5
	s.height_m = float(tr["height"]) * float(tr.get("season_h", 1.0)) * b * 2.0
	s.colour = GrassColour.at(tr, 0.5, 0.5, float(tr.get("accent", 0.0)))
	_flower(s, ty, p)
	return s


## The highest water over p (GrassWater.top over the live pack, the sea's included).
func _water_top(p: Vector2) -> Vector4:
	var on := not is_nan(sea_level)
	return GrassWater.top(water_pack, water_origin, p, Vector3(sea_level if on else 0.0, float(sea_kind),
		1.0 if on else 0.0))


## A corner's allowance (corner_allow): 1 where forced or on the editor's every-ground preview; 1 at a painted override
## on ground that allows any grass; else the control word's base and overlay allowances blended.
func _corner_allow(cw: int, t: Color) -> float:
	if t.a < 0.5 or all_grounds:
		return 1.0
	var ab := _allow((cw >> 27) & 0x1F)
	var ao := _allow((cw >> 22) & 0x1F)
	var bl := float((cw >> 14) & 0xFF) / 255.0
	if t.g8 > 0 and lerpf(absf(ab), absf(ao), bl) > 0.0:
		return 1.0
	return lerpf(maxf(ab, 0.0), maxf(ao, 0.0), bl)


func _allow(i: int) -> float:
	return allow[i] if i < allow.size() else 1.0


## A type's eligibility d m below the sea (the kernel reads GrassTypes.depth_table: an empty slot is land).
func _eligible(ty: int, d: float, shore := GrassTypes.SEA_SHORE_M) -> float:
	return GrassTypes.eligibility(types.rows[ty] if ty < types.rows.size() else {}, d, shore)


## The slot's mix at elevation h and depth d (mix_pick): Vector2(type, best eligibility); type -1: nothing may grow.
func _mix_pick(slot: int, h: float, d: float, u01: float, shore := GrassTypes.SEA_SHORE_M) -> Vector2:
	var base := slot * MIX_FLOATS
	if base + MIX_FLOATS > mix.size():
		return Vector2(-1.0, 0.0)
	var o := base + (12 if mix[base + 25] > 0.5 and h > mix[base + 24] else 0)
	var tot := 0.0
	var prev := 0.0
	var best := 0.0
	for i in 6:
		var t := mix[o + i * 2]
		if t < 0.0:
			break
		var e := _eligible(int(t), d, shore)
		tot += (mix[o + i * 2 + 1] - prev) * e
		best = maxf(best, e)
		prev = mix[o + i * 2 + 1]
	if tot <= 0.0:
		return Vector2(-1.0, best)
	var want := u01 * tot
	var acc := 0.0
	var last := -1
	prev = 0.0
	for i in 6:
		var t := mix[o + i * 2]
		if t < 0.0:
			break
		var e := _eligible(int(t), d, shore)
		acc += (mix[o + i * 2 + 1] - prev) * e
		prev = mix[o + i * 2 + 1]
		if e > 0.0:
			last = int(t)
			if want < acc:
				return Vector2(last, best)
	return Vector2(last, best)


## The species patch value at pos for a slot (species_patch): the nearest of the 9 jittered sites' hash.
func _species_patch(pos: Vector2, slot: int) -> float:
	var cs := species_patch_m
	var base := Vector2i(floori(pos.x / cs), floori(pos.y / cs))
	var best := 1e9
	var cid := base
	for y in range(-1, 2):
		for x in range(-1, 2):
			var kk := base + Vector2i(x, y)
			var r3 := GrassHash.rnd3(kk, 41)
			var pt := (Vector2(kk) + Vector2(r3.x, r3.y)) * cs
			var dd := (pt - pos).length_squared()
			if dd < best:
				best = dd
				cid = kk
	return GrassHash.rnd3(cid, 64 + slot).x


## Smooth value noise from the cell hash (value_noise, stream 31): the verge's width.
static func _value_noise(p: Vector2) -> float:
	var i := Vector2i(floori(p.x), floori(p.y))
	var fr := p - Vector2(i)
	fr = fr * fr * (Vector2(3.0, 3.0) - 2.0 * fr)
	var a := GrassHash.rnd3(i, 31).x
	var b := GrassHash.rnd3(i + Vector2i(1, 0), 31).x
	var c := GrassHash.rnd3(i + Vector2i(0, 1), 31).x
	var d := GrassHash.rnd3(i + Vector2i(1, 1), 31).x
	return lerpf(lerpf(a, b, fr.x), lerpf(c, d, fr.x), fr.y)


## The ground height at p (ground_h: bilinear over the 4 vertices), NAN where a region is missing.
func _ground_h(p: Vector2) -> float:
	var g := p / spacing
	var v0 := Vector2i(floori(g.x), floori(g.y))
	var f := g - Vector2(v0)
	var h: Array[float] = []
	for k in 4:
		var hv: float = height.call(v0 + CORNERS[k])
		if is_nan(hv):
			return NAN
		h.append(hv)
	return lerpf(lerpf(h[0], h[1], f.x), lerpf(h[2], h[3], f.x), f.y)


## The ground normal at p (ground_n), up where a region is missing.
func _ground_normal(p: Vector2) -> Vector3:
	var h := _ground_h(p)
	var n := Vector3(h - _ground_h(p + Vector2(spacing, 0.0)), spacing, h - _ground_h(p + Vector2(0.0, spacing)))
	return Vector3.UP if is_nan(n.x) or is_nan(n.z) else n.normalized()


## The first flower the species hosts that is out today, and its palette colour at p.
func _flower(s: GrassSample, ty: int, p: Vector2) -> void:
	if kinds == null:
		return
	for i in kinds.kinds.size():
		var kd: Dictionary = kinds.kinds[i]
		if int(kd["host"]) != ty:
			continue
		var st: Vector2 = deco_state.call(i)
		if st.x <= 0.0:
			continue
		var cols := kinds.colours(i, st.y)
		if cols.is_empty():
			continue
		var pi := GrassHash.palette_index(p, kd["cell"], cols.size(), kinds.palette_salt(i))
		s.flower = StringName(kd["name"])
		s.flower_colour = (cols[pi] as Color).linear_to_srgb()
		return
