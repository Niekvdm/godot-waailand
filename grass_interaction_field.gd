# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name GrassInteractionField
extends RefCounted
## The camera-centred, TOROIDAL interaction texture: RGBA16F, size_px² texels of
## texel_m. World texel w lives at index w mod size_px, so scrolling copies nothing; the
## stamp pass clears texels whose world cell just entered the window.
##   RG lay direction, B crush (persistent, decays linearly), A transient push.
## Cosmetic and client-local: in multiplayer, every client stamps from the state it already replicates.

## A stamp that flattens the grass (it stays laid and recovers slowly).
const KIND_CRUSH := 0
## A stamp that bends the grass away for this frame only.
const KIND_PUSH := 1
## Stamps a frame, every caller together; the rest are dropped.
const MAX_STAMPS := 32
## The stamp pass.
const SHADER := "res://addons/waailand/interaction_stamp.glsl"

## The texture's side (texels).
var size_px := 512
## A texel's side (m): the field covers size_px x texel_m metres around the camera.
var texel_m := 0.125
## How fast a crush recovers (per second, of a full crush).
var decay_per_s := 0.03
## For tests: the frame time the decay uses (-1: the real one).
var dt_override := -1.0
## The world texel at the window's corner this frame.
var origin_texel := Vector2i.ZERO
## The window's corner last frame (texels that entered since are cleared).
var prev_origin := Vector2i.ZERO
var _stamps: Array = []
var _dt := 0.0
var _tex := RID()
var _buf := RID()
var _shader := RID()
var _pipe := RID()
var _set := RID()


## Stamps a capsule from `a` to `b` (radius m) this frame: KIND_CRUSH or KIND_PUSH, strength 0..1, laid or pushed
## along `dir` when given.
func add_capsule(a: Vector3, b: Vector3, radius: float, kind: int, strength: float, dir: Vector2) -> void:
	if _stamps.size() < MAX_STAMPS:
		_stamps.append([a, b, radius, kind, strength, dir.normalized() if dir.length() > 1e-6 else Vector2.ZERO])


## The texel that holds world point `xz`.
func world_to_index(xz: Vector2) -> Vector2i:
	var w := Vector2i(floori(xz.x / texel_m), floori(xz.y / texel_m))
	return Vector2i(posmod(w.x, size_px), posmod(w.y, size_px))


## One texel of a read-back texture (rt_read) of side `n`: (lay x, lay z, crush, push).
static func decode_texel(data: PackedByteArray, n: int, idx: Vector2i) -> Vector4:
	var o := (idx.y * n + idx.x) * 8
	return Vector4(data.decode_half(o), data.decode_half(o + 2), data.decode_half(o + 4), data.decode_half(o + 6))


## Centres the window on the camera for this frame.
func frame_begin(cam: Vector3, dt: float) -> void:
	prev_origin = origin_texel
	origin_texel = Vector2i(floori(cam.x / texel_m), floori(cam.z / texel_m)) - Vector2i.ONE * (size_px / 2)
	_dt = dt if dt_override < 0.0 else dt_override


## This frame's stamps and window, packed for the render thread (rt_prepare).
func payload() -> Dictionary:
	var f := PackedFloat32Array()
	f.resize((2 + 3 * MAX_STAMPS) * 4)
	f[0] = origin_texel.x
	f[1] = origin_texel.y
	f[2] = prev_origin.x
	f[3] = prev_origin.y
	f[4] = texel_m
	f[5] = size_px
	f[6] = decay_per_s * _dt
	f[7] = _stamps.size()
	for k in _stamps.size():
		var s: Array = _stamps[k]
		var o := (2 + 3 * k) * 4
		var a: Vector3 = s[0]
		var b: Vector3 = s[1]
		var d: Vector2 = s[5]
		f[o + 0] = a.x
		f[o + 1] = a.y
		f[o + 2] = a.z
		f[o + 3] = s[2]
		f[o + 4] = b.x
		f[o + 5] = b.y
		f[o + 6] = b.z
		f[o + 7] = float(s[3])
		f[o + 8] = d.x
		f[o + 9] = d.y
		f[o + 10] = s[4]
		f[o + 11] = 0.0
	_stamps.clear()
	return {"bytes": f.to_byte_array()}


## Render thread: creates the texture and the stamp pass; returns the texture.
func rt_create(rd: RenderingDevice) -> RID:
	var fmt := RDTextureFormat.new()
	fmt.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	fmt.width = size_px
	fmt.height = size_px
	fmt.usage_bits = (RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
		| RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT    # texture_clear requires it
		| RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT)
	_tex = rd.texture_create(fmt, RDTextureView.new(), [])
	rd.texture_clear(_tex, Color(0, 0, 0, 0), 0, 1, 0, 1)
	_buf = rd.storage_buffer_create((2 + 3 * MAX_STAMPS) * 16)
	var f = load(SHADER)
	var spirv: RDShaderSPIRV = (f as RDShaderFile).get_spirv()
	if spirv.compile_error_compute != "":
		push_error("GrassInteractionField: %s" % spirv.compile_error_compute)
		return _tex
	_shader = rd.shader_create_from_spirv(spirv)
	_pipe = rd.compute_pipeline_create(_shader)
	var ui := RDUniform.new()
	ui.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	ui.binding = 0
	ui.add_id(_tex)
	var ub := RDUniform.new()
	ub.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	ub.binding = 1
	ub.add_id(_buf)
	_set = rd.uniform_set_create([ui, ub], _shader, 0)
	return _tex


## Render thread: uploads a payload.
func rt_prepare(rd: RenderingDevice, p: Dictionary) -> void:
	if p.has("bytes") and _buf.is_valid():
		var b: PackedByteArray = p["bytes"]
		rd.buffer_update(_buf, 0, b.size(), b)


## Render thread: the stamp pass, into compute list `cl`.
func rt_dispatch(rd: RenderingDevice, cl: int) -> void:
	if not _set.is_valid():
		return
	rd.compute_list_bind_compute_pipeline(cl, _pipe)
	rd.compute_list_bind_uniform_set(cl, _set, 0)
	var g := int(ceil(size_px / 16.0))
	rd.compute_list_dispatch(cl, g, g, 1)
	rd.compute_list_add_barrier(cl)


## Render thread: the texture's bytes (decode_texel reads them).
func rt_read(rd: RenderingDevice) -> PackedByteArray:
	return rd.texture_get_data(_tex, 0)


## Render thread: frees what rt_create made.
func rt_free(rd: RenderingDevice) -> void:
	if _set.is_valid() and rd.uniform_set_is_valid(_set):
		rd.free_rid(_set)
	for r in [_pipe, _shader, _buf, _tex]:
		if (r as RID).is_valid():
			rd.free_rid(r)
