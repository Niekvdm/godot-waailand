# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name GrassAirField
extends RefCounted
## The grass's MEMORY of the air. The blade and flower shaders are stateless: they lean each plant to the equilibrium
## of the air it stands in NOW, so a gust front or a rotor laid the grass and released it in the same frame, with no
## lag, no rebound and no trace. This field keeps what a spring keeps: a camera-centred, TOROIDAL window of the lean
## each patch of ground carries (a plant of wind response 1), integrated every frame toward the air's equilibrium
## lean (air_step.glsl): the lag behind a rising load, the overshoot when it falls away, and a patch held flat that
## creeps back up over seconds once released (MATTING: grass pressed down for a while stays down; a quick pass does
## not mat it).
##   state (RGBA16F): RG the lean (rad, xz), BA its rate (rad/s)
##   eq    (RGBA16F): RG this frame's equilibrium lean, B the matting 0..1
## The shaders add state - eq (air_dev in grass_air.gdshaderinc) scaled by the species' response: in a steady air
## the difference decays to zero, so a steady wind looks exactly as the stateless lean. The equilibrium leaves out
## the rotor wash's crests and all the TIME-driven motion (sway, buffeting, the fine gusts): those stay exact and
## carry motion vectors; the field's transients are uniform-driven, like the gust field's scroll.
## Cosmetic and client-local, like the interaction field.

## The step pass.
const SHADER := "res://addons/waailand/air_step.glsl"
## The spring's natural frequency (Hz) for a standing plant: a gust front's rebound.
const FREQ_HZ := 1.2
## Its damping ratio standing: under-damped, a released plant overshoots upright once.
const ZETA := 0.35
## A matted patch being RELEASED keeps this much of the stiffness (it creeps back up)...
const LAID_STIFFNESS := 0.03
## ...at this damping ratio (over-damped: no bounce off the ground).
const LAID_ZETA := 1.2
## The laid range (rad) the matting builds in: from LAID_FROM, fully from LAID_FULL.
const LAID_FROM := 0.8
const LAID_FULL := 1.15
## How fast the matting builds while a patch is held flat (s, a time constant)...
const MAT_RISE_S := 0.5
## ...and fades once it is up again (s): the creep's length.
const MAT_FALL_S := 4.0
## The flattest a patch lies (rad): it does not fold past the ground.
const CAP := 1.45
## The longest integration sub-step (s): a slow frame is stepped in pieces.
const MAX_SUBSTEP := 1.0 / 120.0
## A frame longer than this (s) is taken as this (a hitch, the editor waking).
const MAX_DT := 0.1

## The texture's side (texels).
var size_px := 256
## A texel's side (m): the window covers size_px x texel_m metres around the camera.
var texel_m := 0.5
## Off: the shaders get no deviation and the pass does not run.
var enabled := true
## The world texel at the window's corner this frame.
var origin_texel := Vector2i.ZERO
## The window's corner last frame (texels that entered since start at their equilibrium, at rest).
var prev_origin := Vector2i.ZERO
var _dt := 0.0
var _started := false
var _state := RID()
var _eq := RID()
var _buf := RID()
var _sampler := RID()
var _shader := RID()
var _pipe := RID()
var _set := RID()
var _gust := RID()


## One step of a patch's spring (the GLSL's, mirrored for the tests): its lean `lean` (rad, xz), rate `rate` (rad/s)
## and matting `mat` (0..1) moved `dt` toward the equilibrium `eq`. Returns [lean, rate, mat].
static func spring_step(lean: Vector2, rate: Vector2, mat: float, eq: Vector2, dt: float) -> Array:
	var n := maxi(1, ceili(minf(dt, MAX_DT) / MAX_SUBSTEP))
	var h := minf(dt, MAX_DT) / n
	var w0 := TAU * FREQ_HZ
	for i in n:
		var l := lean.length()
		var target := smoothstep(LAID_FROM, LAID_FULL, l)
		mat += (target - mat) * (1.0 - exp(-h / (MAT_RISE_S if target > mat else MAT_FALL_S)))
		var k := w0 * w0
		var zeta := ZETA
		if l > 1e-5:
			var soft := mat * smoothstep(0.0, 0.2, -(eq - lean).dot(lean / l))    # matted, and being released
			k *= pow(LAID_STIFFNESS, soft)             # geometric: the creep lasts while the matting fades
			zeta = lerpf(ZETA, LAID_ZETA, soft)
		rate += ((eq - lean) * k - rate * (2.0 * zeta * sqrt(k))) * h
		lean += rate * h
		var ll := lean.length()
		if ll > CAP:
			lean *= CAP / ll
			var out := lean / CAP
			rate -= out * maxf(rate.dot(out), 0.0)
	return [lean, rate, mat]


## Settles every patch at its equilibrium, at rest and unmatted, on the next frame (a calm: a still picture must not
## rebound from the wind it had).
func reset() -> void:
	_started = false


## Centres the window on the camera for this frame.
func frame_begin(cam: Vector3, dt: float) -> void:
	prev_origin = origin_texel
	origin_texel = Vector2i(floori(cam.x / texel_m), floori(cam.z / texel_m)) - Vector2i.ONE * (size_px / 2)
	if not _started:
		prev_origin = origin_texel - Vector2i.ONE * size_px     # the first frame: every texel enters, at rest
		_started = true
	_dt = minf(maxf(dt, 0.0), MAX_DT)


## The window as the shaders read it (air_window): the centre (world xz), the side (m), and 1 when live.
func window() -> Vector4:
	var side := size_px * texel_m
	var c := (Vector2(origin_texel) + Vector2.ONE * (size_px * 0.5)) * texel_m
	return Vector4(c.x, c.y, side, 1.0 if enabled and _pipe.is_valid() else 0.0)


## This frame's window, clock and air, packed for the render thread (rt_prepare): `wind` is GrassWindState.uniforms(),
## `washes` the frame's wash slots (x, z, footprint, intensity).
func payload(wind: Dictionary, washes: PackedVector4Array) -> Dictionary:
	var f := PackedFloat32Array()
	f.resize(8 * 4)
	f[0] = origin_texel.x
	f[1] = origin_texel.y
	f[2] = prev_origin.x
	f[3] = prev_origin.y
	f[4] = texel_m
	f[5] = size_px
	f[6] = _dt
	f[7] = mini(washes.size(), 2)
	var d: Vector2 = wind.get("wind_dir", Vector2(1, 0))
	f[8] = d.x
	f[9] = d.y
	f[10] = float(wind.get("gust_scale", 0.02))
	f[11] = float(wind.get("swirl_rad", 0.9))
	var s1: Vector2 = wind.get("wind_scroll", Vector2.ZERO)
	var s2: Vector2 = wind.get("wind_scroll2", Vector2.ZERO)
	var ssw: Vector2 = wind.get("wind_scroll_sw", Vector2.ZERO)
	f[12] = s1.x
	f[13] = s1.y
	f[14] = s2.x
	f[15] = s2.y
	f[16] = ssw.x
	f[17] = ssw.y
	f[18] = float(wind.get("lean_base", 0.0))
	f[19] = float(wind.get("lean_gust", 0.0))
	for k in mini(washes.size(), 2):
		var w := washes[k]
		f[24 + 4 * k] = w.x
		f[25 + 4 * k] = w.y
		f[26 + 4 * k] = w.z
		f[27 + 4 * k] = w.w
	return {"bytes": f.to_byte_array()}


## Render thread: creates the textures and the step pass over the gust texture `gust_rd` (an RD texture).
func rt_create(rd: RenderingDevice, gust_rd: RID) -> void:
	_gust = gust_rd
	var fmt := RDTextureFormat.new()
	fmt.width = size_px
	fmt.height = size_px
	fmt.usage_bits = (RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
		| RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
		| RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT)
	fmt.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	_state = rd.texture_create(fmt, RDTextureView.new(), [])
	rd.texture_clear(_state, Color(0, 0, 0, 0), 0, 1, 0, 1)
	_eq = rd.texture_create(fmt, RDTextureView.new(), [])
	rd.texture_clear(_eq, Color(0, 0, 0, 0), 0, 1, 0, 1)
	_buf = rd.storage_buffer_create(8 * 16)
	var ss := RDSamplerState.new()
	ss.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	ss.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	ss.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	ss.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	_sampler = rd.sampler_create(ss)
	var f = load(SHADER)
	var spirv: RDShaderSPIRV = (f as RDShaderFile).get_spirv()
	if spirv.compile_error_compute != "":
		push_error("GrassAirField: %s" % spirv.compile_error_compute)
		return
	_shader = rd.shader_create_from_spirv(spirv)
	_pipe = rd.compute_pipeline_create(_shader)
	_bind(rd)


func _bind(rd: RenderingDevice) -> void:
	if not _shader.is_valid() or not _gust.is_valid():
		return
	var us := RDUniform.new()
	us.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	us.binding = 0
	us.add_id(_state)
	var ue := RDUniform.new()
	ue.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	ue.binding = 1
	ue.add_id(_eq)
	var ub := RDUniform.new()
	ub.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	ub.binding = 2
	ub.add_id(_buf)
	var ug := RDUniform.new()
	ug.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	ug.binding = 3
	ug.add_id(_sampler)
	ug.add_id(_gust)
	_set = rd.uniform_set_create([us, ue, ub, ug], _shader, 0)


## Whether the step pass can run.
func pipe_valid() -> bool:
	return _pipe.is_valid() and _set.is_valid()


## The textures the shaders sample (air_state, air_eq).
func state_rid() -> RID:
	return _state


func eq_rid() -> RID:
	return _eq


## Render thread: uploads a payload.
func rt_prepare(rd: RenderingDevice, p: Dictionary) -> void:
	if p.has("bytes") and _buf.is_valid():
		var b: PackedByteArray = p["bytes"]
		rd.buffer_update(_buf, 0, b.size(), b)


## Render thread: the step pass, into compute list `cl`.
func rt_dispatch(rd: RenderingDevice, cl: int) -> void:
	if not enabled or not pipe_valid():
		return
	rd.compute_list_bind_compute_pipeline(cl, _pipe)
	rd.compute_list_bind_uniform_set(cl, _set, 0)
	var g := int(ceil(size_px / 16.0))
	rd.compute_list_dispatch(cl, g, g, 1)
	rd.compute_list_add_barrier(cl)


## Render thread: the state texture's bytes (decode reads them).
func rt_read(rd: RenderingDevice) -> Dictionary:
	return {"state": rd.texture_get_data(_state, 0), "eq": rd.texture_get_data(_eq, 0)}


## One texel of a read-back (rt_read) as [lean, rate, eq, mat].
static func decode(data: Dictionary, n: int, idx: Vector2i) -> Array:
	var s: PackedByteArray = data["state"]
	var e: PackedByteArray = data["eq"]
	var o := (idx.y * n + idx.x) * 8
	return [Vector2(s.decode_half(o), s.decode_half(o + 2)), Vector2(s.decode_half(o + 4), s.decode_half(o + 6)),
		Vector2(e.decode_half(o), e.decode_half(o + 2)), e.decode_half(o + 4)]


## The texel that holds world point `xz`.
func world_to_index(xz: Vector2) -> Vector2i:
	var w := Vector2i(floori(xz.x / texel_m), floori(xz.y / texel_m))
	return Vector2i(posmod(w.x, size_px), posmod(w.y, size_px))


## Render thread: frees what rt_create made.
func rt_free(rd: RenderingDevice) -> void:
	if _set.is_valid() and rd.uniform_set_is_valid(_set):
		rd.free_rid(_set)
	for r in [_pipe, _shader, _buf, _sampler, _state, _eq]:
		if (r as RID).is_valid():
			rd.free_rid(r)
	_set = RID()
	_pipe = RID()
	_shader = RID()
	_buf = RID()
	_sampler = RID()
	_state = RID()
	_eq = RID()
