# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name GrassBrush
extends RefCounted
## The grass brush: paints GrassMaps' images, so the grass paints on any Terrain3D. One texel per vertex; SET_HARD at weight >= 0.5, SET_SPRAY by a coin per texel (a texel's channels
## together), LERP at least one step, SMOOTH toward the 4 neighbours, REPLACE where the first channel holds `from`; several
## channels in one stroke; slope and elevation limits; the region fill once a stroke (a hard fill without limits writes
## the bytes directly). Pure CPU.

enum Mode { SET_HARD, SET_SPRAY, LERP, SMOOTH, REPLACE }

var maps: GrassMaps = null
var data: Object = null                  # the terrain's data: get_height, get_normal (the limits)
var rng := RandomNumberGenerator.new()
var on_first_change := Callable()        # (loc) before a region's first change this stroke: the undo's "before"
var texel_ok := Callable()               # (pos: Vector3) -> bool: false leaves the texel (the Water layer: over water)
var touched := {}                        # loc -> Rect2i: what this stroke changed
var _filled := false
var _now := {}                           # loc -> true: changed by this dab (its layer is re-sent)


func begin() -> void:
	touched.clear()
	_filled = false


## One dab at `center`. brush: {size m, strength 0..1, image, gamma, spin_speed, align_to_view,
## rotation, pressure}; op: GrassPaintTool.brush_data: {channel, value, mode, channels, values, from, slope, height,
## fill_region}.
func dab(p_center: Vector3, p_brush: Dictionary, p_op: Dictionary) -> void:
	var channel := int(p_op.get("channel", -1))
	if maps == null or channel < 0:
		return
	var channels: PackedInt32Array = p_op.get("channels", PackedInt32Array())
	var values: PackedInt32Array = p_op.get("values", PackedInt32Array())
	if channels.is_empty() or channels.size() != values.size():
		channels = PackedInt32Array([channel])
		values = PackedInt32Array([int(p_op.get("value", 0))])
	var o := {"channels": channels, "values": values, "from": int(p_op.get("from", -1)),
		"mode": clampi(int(p_op.get("mode", Mode.SET_HARD)), 0, Mode.size() - 1),
		"slope": p_op.get("slope"), "height": p_op.get("height")}
	var strength := float(p_brush.get("strength", 1.0)) * clampf(float(p_brush.get("pressure", 1.0)), 0.0, 1.0)
	_now.clear()
	if bool(p_op.get("fill_region", false)):
		if _filled:
			return
		_filled = true
		_fill(maps.location_of(p_center), p_center.y, clampf(strength, 0.0, 1.0), o)
	else:
		_stamp(p_center, p_brush, strength, o)
	for loc in _now:
		maps.update_layer(loc)


func _stamp(p_center: Vector3, p_brush: Dictionary, p_strength: float, o: Dictionary) -> void:
	var img: Image = p_brush.get("image")
	if img == null:
		return
	var isz := img.get_size()
	var size := clampf(float(p_brush.get("size", 10.0)), 2.0, 4096.0)
	var gamma := float(p_brush.get("gamma", 1.0))
	var vs := maps.vertex_spacing()
	var rot := rng.randf() * PI * float(p_brush.get("spin_speed", 0.0))
	if bool(p_brush.get("align_to_view", true)):
		rot += float(p_brush.get("rotation", 0.0))
	var x := 0.0
	while x < size:
		var y := 0.0
		while y < size:
			var off := Vector2(x, y) - Vector2(size, size) * 0.5
			var pos := Vector3(p_center.x + off.x + 0.5, p_center.y, p_center.z + off.y + 0.5)
			var bpx := Vector2i(_rotated_uv(Vector2(x, y) / size, rot) * Vector2(isz))
			if bpx.x >= 0 and bpx.y >= 0 and bpx.x < isz.x and bpx.y < isz.y:
				var alpha := pow(img.get_pixelv(bpx).r, gamma)
				alpha = 0.0 if is_nan(alpha) else alpha
				var t := clampf(alpha * p_strength, 0.0, 1.0)
				if t > 0.0:
					_apply(pos, t, o)
			y += vs
		x += vs


func _fill(p_loc: Vector2i, p_y: float, p_t: float, o: Dictionary) -> void:
	if maps.layer_of(p_loc) < 0:
		return
	var n := maps.region_size()
	if o["mode"] == Mode.SET_HARD and o["slope"] == null and o["height"] == null and not texel_ok.is_valid():
		if p_t < 0.5:
			return
		var img := maps.image(p_loc)
		var bytes := img.get_data()
		var chs: PackedInt32Array = o["channels"]
		var vals: PackedInt32Array = o["values"]
		var before := bytes.duplicate()
		for k in chs.size():
			var v := clampi(vals[k], 0, 255)
			for i in range(clampi(chs[k], 0, 3), bytes.size(), 4):
				bytes[i] = v
		if bytes == before:
			return
		if not touched.has(p_loc) and on_first_change.is_valid():
			on_first_change.call(p_loc)
		img.set_data(n, n, false, Image.FORMAT_RGBA8, bytes)
		touched[p_loc] = Rect2i(0, 0, n, n)
		_now[p_loc] = true
		return
	var vs := maps.vertex_spacing()
	for y in n:
		for x in n:
			_apply(Vector3((float(p_loc.x * n + x) + 0.5) * vs, p_y, (float(p_loc.y * n + y) + 0.5) * vs), p_t, o)


## One texel: the limits, then each channel's new byte.
func _apply(p_pos: Vector3, p_t: float, o: Dictionary) -> void:
	var loc := maps.location_of(p_pos)
	if maps.layer_of(loc) < 0:
		return
	var n := maps.region_size()
	var px := _texel(p_pos, n)
	if px.x < 0 or px.y < 0 or px.x >= n or px.y >= n:
		return
	if texel_ok.is_valid() and not bool(texel_ok.call(p_pos)):
		return
	if o["height"] != null:
		var h := float(data.call("get_height", p_pos)) if data != null else NAN
		if is_nan(h) or h < (o["height"] as Vector2).x or h > (o["height"] as Vector2).y:
			return
	if o["slope"] != null:
		var nrm: Vector3 = data.call("get_normal", p_pos) if data != null else Vector3(NAN, NAN, NAN)
		if not nrm.is_finite():
			return
		var deg := rad_to_deg(acos(clampf(nrm.y, -1.0, 1.0)))
		if deg < (o["slope"] as Vector2).x or deg > (o["slope"] as Vector2).y:
			return
	var img := maps.image(loc)
	var src := img.get_pixelv(px)
	var chs: PackedInt32Array = o["channels"]
	var vals: PackedInt32Array = o["values"]
	if o["mode"] == Mode.REPLACE and roundi(src[clampi(chs[0], 0, 3)] * 255.0) != int(o["from"]):
		return
	var coin := rng.randf()
	var dst := src
	var changed := false
	for k in chs.size():
		var ch := clampi(chs[k], 0, 3)
		var value := clampi(vals[k], 0, 255)
		var s := roundi(src[ch] * 255.0)
		var d := s
		match o["mode"]:
			Mode.SET_HARD, Mode.REPLACE:
				d = value if p_t >= 0.5 else s
			Mode.SET_SPRAY:
				d = value if coin < p_t else s
			Mode.LERP:
				d = roundi(lerpf(float(s), float(value), p_t))
				if d == s and s != value:
					d = s + (1 if value > s else -1)       # byte rounding must not stall a slow brush
			Mode.SMOOTH:
				d = roundi(lerpf(float(s), float(_neighbours(p_pos, ch, s)), p_t))
		if d != s:
			dst[ch] = float(d) / 255.0
			changed = true
	if not changed:
		return
	if not touched.has(loc):
		if on_first_change.is_valid():
			on_first_change.call(loc)
		touched[loc] = Rect2i(px, Vector2i.ONE)
	else:
		touched[loc] = (touched[loc] as Rect2i).merge(Rect2i(px, Vector2i.ONE))
	img.set_pixelv(px, dst)
	_now[loc] = true


## SMOOTH's neighbourhood: one channel's mean over the 4 neighbouring vertices; a neighbour
## outside every region counts as `base`.
func _neighbours(p_pos: Vector3, p_ch: int, p_base: int) -> int:
	var vs := maps.vertex_spacing()
	var n := maps.region_size()
	var sum := 0
	for o in [Vector3(-vs, 0, 0), Vector3(vs, 0, 0), Vector3(0, 0, -vs), Vector3(0, 0, vs)]:
		var p: Vector3 = p_pos + o
		var loc := maps.location_of(p)
		var px := _texel(p, n)
		if maps.layer_of(loc) >= 0 and px.x >= 0 and px.y >= 0 and px.x < n and px.y < n:
			sum += roundi(maps.image(loc).get_pixelv(px)[p_ch] * 255.0)
		else:
			sum += p_base
	return roundi(float(sum) / 4.0)


## The texel of `pos` within its region (its UV position in the region x the region size).
func _texel(p_pos: Vector3, p_n: int) -> Vector2i:
	var d := Vector2(p_pos.x, p_pos.z) / maps.vertex_spacing()
	var uv := d / float(p_n) - (d / float(p_n)).floor()
	return Vector2i(uv * float(p_n))


static func _rotated_uv(p_uv: Vector2, p_angle: float) -> Vector2:
	return ((p_uv - Vector2(0.5, 0.5)).rotated(p_angle) + Vector2(0.5, 0.5)).clamp(Vector2.ZERO, Vector2.ONE)
