# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name DecorationStreams
extends RefCounted
## The decoration streams: per kind a HIGH and a LOW indirect MultiMesh, filled each frame by
## deco_place.glsl, one dispatch per kind in season; out of season a kind
## is neither dispatched nor drawn. A sibling collaborator of GrassBlades: it owns its
## MultiMeshes, buffers and materials; GrassBlades calls it inside its own compute list with
## its params/types buffers, textures and interaction field, so both see the same world.
## Same indirect MultiMesh rules as GrassBlades (allocate(indirect) then set_mesh; custom AABB
## every frame; compute writes only command word 1; never the CPU MultiMesh API).

const PLACE_SHADER := "res://addons/waailand/deco_place.glsl"
const DECO_SHADER := "res://addons/waailand/grass_deco.gdshader"
const STRIDE := 20

var kinds := DecoKinds.new()
var enabled := true
## The colour handoff to blades and terrain (grass_handoff.gdshaderinc); false = none (the negative control).
var handoff := true
var materials: Array[ShaderMaterial] = []
var _types: GrassTypes
var _state: Array = []          # per kind Vector2 (grow, phase) for the current day
var _active: Array = []
var _visible := {}              # kind -> bool as last set
var _all_visible := true
var _k: Array = []              # per kind: {mm_hi, mm_lo, inst_hi, inst_lo, dst_hi, dst_lo, cmd_hi, cmd_lo, counters, stats, dummy, set, fin_set}
var _shader := RID()
var _pipe := RID()
var _kbuf := RID()
var _field_rd := RID()
var _params_buf := RID()
var _types_buf := RID()


## Main thread, before rt_init: meshes (built on first use) and one material per kind.
func prepare(types: GrassTypes) -> void:
	_types = types
	var sh: Shader = load(DECO_SHADER)
	materials.clear()
	_state.clear()
	for i in kinds.kinds.size():
		var k: Dictionary = kinds.kinds[i]
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("pal_n", float((k["palette"] as Array).size()))
		m.set_shader_parameter("pal_cell", k["cell"])
		m.set_shader_parameter("kind_salt", float(kinds.palette_salt(i)))
		var sc: Color = (k["stem"] as Color).srgb_to_linear()
		m.set_shader_parameter("stem_col", Vector3(sc.r, sc.g, sc.b))
		var cc: Color = k["centre"]
		var ccl := cc.srgb_to_linear()
		m.set_shader_parameter("centre_col", Vector4(ccl.r, ccl.g, ccl.b, cc.a))
		m.set_shader_parameter("backlight", k["backlight"])
		m.set_shader_parameter("flutter", k["flutter"])
		m.set_shader_parameter("wind_response", k["wind_response"])
		m.set_shader_parameter("hinge_response", k["hinge_response"])
		if int(types.row(int(k["host"])).get("layer", GrassTypes.LAYER_GROUND)) == GrassTypes.LAYER_SURFACE:
			m.set_shader_parameter("hinge_response", 0.0)     # floating: no stem to bend about
		materials.append(m)
		_state.append(Vector2.ZERO)
		kinds.mesh(i)


func state(i: int) -> Vector2:
	return _state[i]


## The day changed: each kind's bloom state and today's palette. `plan`: a map's season settings (GrassSeasonPlan),
## each kind at its species' setting.
func set_day(doy: float, plan: GrassSeasonPlan = null) -> void:
	for i in kinds.kinds.size():
		var k: Dictionary = kinds.kinds[i]
		_state[i] = plan.kind_state(k["bloom"], String(_types.row(int(k["host"])).get("name", "")), doy) \
			if plan != null else GrassSeason.bloom(k["bloom"], doy)
		var cols := kinds.colours(i, (_state[i] as Vector2).y)
		var pal := []
		for e in 6:
			var c: Color = cols[mini(e, cols.size() - 1)]
			pal.append(Vector3(c.r, c.g, c.b))
		materials[i].set_shader_parameter("pal", pal)


## Main thread, every dispatch: which kinds run, where their grids start, their AABBs.
func frame(cam: Vector3, grow_m: float) -> Dictionary:
	var dispatches := []
	_active = []
	for i in kinds.kinds.size():
		var on: bool = enabled and _all_visible and (_state[i] as Vector2).x > 0.0
		_set_kind_visible(i, on)
		if not on or i >= _k.size():
			continue
		var k: Dictionary = kinds.kinds[i]
		var cs: float = k["spacing"] if k["mode"] == DecoKinds.GRID else float(_types.row(k["host"])["clump_cell"])
		var tsize := 16.0 * cs
		var reach: float = k["radius"] + 0.5 * grow_m + tsize
		var tiles := int(ceil(2.0 * reach / tsize)) + 1
		var t0 := Vector2i(floori((cam.x - reach) / tsize), floori((cam.z - reach) / tsize))
		var half: float = k["radius"] + grow_m + 4.0
		var box := AABB(cam - Vector3(half, half + 100.0, half), Vector3(half, half + 100.0, half) * 2.0)
		RenderingServer.multimesh_set_custom_aabb(_k[i]["mm_hi"], box)
		RenderingServer.multimesh_set_custom_aabb(_k[i]["mm_lo"], box)
		var push := PackedByteArray()
		push.resize(16)
		push.encode_s32(0, t0.x)
		push.encode_s32(4, t0.y)
		push.encode_s32(8, tiles)
		push.encode_s32(12, i)
		dispatches.append([i, push, tiles])
		_active.append(i)
	return {"kbytes": kinds.params_bytes(_types, _state), "dispatches": dispatches}


## The handoff uniforms (grass_handoff.gdshaderinc) on the given materials, for today's bloom.
## A type hosts at most two kinds; handoff = false clears them (the negative control).
func apply_handoff(mats: Array) -> void:
	var hosts := []
	for t in GrassTypes.SLOTS * 2:
		hosts.append(Vector4(-1.0, 0.0, 0.0, 0.0))
	var used := {}
	var curve := []
	var n := PackedFloat32Array()
	var salt := PackedFloat32Array()
	var pal := []
	for i in DecoKinds.MAX_KINDS:
		if i >= kinds.kinds.size():
			curve.append(Vector4(0.0, 0.0, 1000.0, 1000.0))
			n.append(1.0)
			salt.append(0.0)
			for e in 6:
				pal.append(Vector3.ZERO)
			continue
		var k: Dictionary = kinds.kinds[i]
		var st: Vector2 = _state[i]
		var h: int = k["host"]
		var s: int = used.get(h, 0)
		if handoff and s < 2 and st.x > 0.0:
			hosts[h * 2 + s] = Vector4(i, kinds.coverage(i, _types) * k["handoff_vis"] * st.x, k["d_full"], k["radius"])
			used[h] = s + 1
		var cell: Vector2 = k["cell"]
		curve.append(Vector4(k["k_edge"], k["radius"] * k["fade_frac"], cell.x, cell.y))
		var cols := kinds.colours(i, st.y)
		n.append(float(cols.size()))
		salt.append(float(kinds.palette_salt(i)))
		for e in 6:
			var c: Color = cols[mini(e, cols.size() - 1)]
			pal.append(Vector3(c.r, c.g, c.b))
	for m in mats:
		m.set_shader_parameter("hand_hosts", hosts)
		m.set_shader_parameter("hand_curve", curve)
		m.set_shader_parameter("hand_n", n)
		m.set_shader_parameter("hand_salt", salt)
		m.set_shader_parameter("hand_pal", pal)


func set_visible(on: bool) -> void:
	_all_visible = on
	for i in _k.size():
		_set_kind_visible(i, on and enabled and (_state[i] as Vector2).x > 0.0)


func _set_kind_visible(i: int, on: bool) -> void:
	if i >= _k.size() or _visible.get(i, null) == on:
		return
	_visible[i] = on
	RenderingServer.instance_set_visible(_k[i]["inst_hi"], on)
	RenderingServer.instance_set_visible(_k[i]["inst_lo"], on)


# ── Render thread ────────────────────────────────────────────────────────────

func rt_init(rd: RenderingDevice, scenario: RID, field_rd: RID, params_buf: RID, types_buf: RID,
		fin_shader: RID) -> void:
	_field_rd = field_rd
	_params_buf = params_buf
	_types_buf = types_buf
	var spirv: RDShaderSPIRV = (load(PLACE_SHADER) as RDShaderFile).get_spirv()
	if spirv.compile_error_compute != "":
		push_error("DecorationStreams: %s" % spirv.compile_error_compute)
		return
	_shader = rd.shader_create_from_spirv(spirv)
	_pipe = rd.compute_pipeline_create(_shader)
	_kbuf = rd.storage_buffer_create(DecoKinds.MAX_KINDS * DecoKinds.KP_VEC4 * 16)
	var zero16 := PackedByteArray()
	zero16.resize(16)
	var zero20 := PackedByteArray()
	zero20.resize(20)
	for i in kinds.kinds.size():
		var k: Dictionary = kinds.kinds[i]
		var cap: Vector2i = k["cap"]
		var ms := kinds.mesh(i)
		var e := {}
		for which in ["hi", "lo"]:
			var mm := RenderingServer.multimesh_create()
			RenderingServer.multimesh_allocate_data(mm, cap.x if which == "hi" else cap.y,
				RenderingServer.MULTIMESH_TRANSFORM_3D, true, true, true)
			RenderingServer.multimesh_set_mesh(mm, (ms[0 if which == "hi" else 1] as ArrayMesh).get_rid())
			var inst := RenderingServer.instance_create2(mm, scenario)
			RenderingServer.instance_geometry_set_material_override(inst, materials[i].get_rid())
			var casts: bool = k["casts"] and which == "hi"
			RenderingServer.instance_geometry_set_cast_shadows_setting(inst,
				RenderingServer.SHADOW_CASTING_SETTING_ON if casts else RenderingServer.SHADOW_CASTING_SETTING_OFF)
			RenderingServer.instance_set_visible(inst, false)
			e["mm_" + which] = mm
			e["inst_" + which] = inst
			e["dst_" + which] = RenderingServer.multimesh_get_buffer_rd_rid(mm)
			e["cmd_" + which] = RenderingServer.multimesh_get_command_buffer_rd_rid(mm)
		e["counters"] = rd.storage_buffer_create(16, zero16)
		e["stats"] = rd.storage_buffer_create(16, zero16)
		e["dummy"] = rd.storage_buffer_create(20, zero20)    # blade_finalize's third command slot
		e["set"] = RID()   # rt_bind builds it once GrassBlades has the terrain's arrays
		var fin: Array[RDUniform] = [
			GrassBlades._storage(0, e["counters"]), GrassBlades._storage(1, e["cmd_hi"]),
			GrassBlades._storage(2, e["cmd_lo"]), GrassBlades._storage(3, e["dummy"]),
			GrassBlades._storage(4, e["stats"]),
		]
		e["fin_set"] = rd.uniform_set_create(fin, fin_shader, 0)
		_k.append(e)
		_visible[i] = false


## (Re)build each kind's placement set with the terrain bindings GrassBlades hands over.
func rt_bind(rd: RenderingDevice, ground: Array[RDUniform]) -> void:
	for e in _k:
		if (e["set"] as RID).is_valid() and rd.uniform_set_is_valid(e["set"]):
			rd.free_rid(e["set"])
		var u: Array[RDUniform] = [
			GrassBlades._storage(0, _params_buf), GrassBlades._storage(1, _types_buf),
			GrassBlades._storage(4, e["counters"]), GrassBlades._storage(5, e["dst_hi"]),
			GrassBlades._storage(6, e["dst_lo"]), GrassBlades._storage(7, _kbuf),
		]
		u.append_array(ground)
		var fu := RDUniform.new()
		fu.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		fu.binding = 8
		fu.add_id(_field_rd)
		u.append(fu)
		e["set"] = rd.uniform_set_create(u, _shader, 0)


## Before GrassBlades opens its compute list (the RD forbids buffer updates inside one).
func rt_prepare(rd: RenderingDevice, payload: Dictionary) -> void:
	if not _pipe.is_valid() or not payload.has("kbytes"):
		return
	var kb: PackedByteArray = payload["kbytes"]
	rd.buffer_update(_kbuf, 0, kb.size(), kb)


## Inside GrassBlades' compute list, after the blades.
## Whether the deco pass can run (the host's fail-loud check reads this).
func pipe_valid() -> bool:
	return _pipe.is_valid()


func rt_frame(rd: RenderingDevice, cl: int, payload: Dictionary, fin_pipe: RID) -> void:
	if not _pipe.is_valid() or not payload.has("kbytes"):
		return
	for dsp in payload["dispatches"]:
		var i: int = dsp[0]
		var push: PackedByteArray = dsp[1]
		var tiles: int = dsp[2]
		var e: Dictionary = _k[i]
		if not (e["set"] as RID).is_valid():
			continue
		rd.compute_list_bind_compute_pipeline(cl, _pipe)
		rd.compute_list_bind_uniform_set(cl, e["set"], 0)
		rd.compute_list_set_push_constant(cl, push, push.size())
		rd.compute_list_dispatch(cl, tiles, tiles, 1)
		rd.compute_list_add_barrier(cl)
		var cap: Vector2i = kinds.kinds[i]["cap"]
		var fp := PackedByteArray()
		fp.resize(16)
		fp.encode_u32(0, cap.x)
		fp.encode_u32(4, cap.y)
		fp.encode_u32(8, 0)
		rd.compute_list_bind_compute_pipeline(cl, fin_pipe)
		rd.compute_list_bind_uniform_set(cl, e["fin_set"], 0)
		rd.compute_list_set_push_constant(cl, fp, fp.size())
		rd.compute_list_dispatch(cl, 1, 1, 1)
		rd.compute_list_add_barrier(cl)


func rt_readback(rd: RenderingDevice, box: Dictionary) -> void:
	var out := []
	for e in _k:
		var st := rd.buffer_get_data(e["stats"]).to_int32_array()
		var d := {"counts": st}
		for which in ["hi", "lo"]:
			var n: int = st[0 if which == "hi" else 1]
			d[which] = (rd.buffer_get_data(e["dst_" + which], 0, n * STRIDE * 4).to_float32_array()
				if n > 0 else PackedFloat32Array())
		out.append(d)
	box["deco"] = out


func rt_free(rd: RenderingDevice) -> void:
	# Our uniform sets first: freeing a MultiMesh frees its buffers and auto-frees the sets on them.
	for e in _k:
		for us in [e["set"], e["fin_set"]]:
			if (us as RID).is_valid() and rd.uniform_set_is_valid(us):
				rd.free_rid(us)
		for r in [e["counters"], e["stats"], e["dummy"]]:
			if (r as RID).is_valid():
				rd.free_rid(r)
	for r in [_pipe, _shader, _kbuf]:
		if (r as RID).is_valid():
			rd.free_rid(r)
	for e in _k:
		for which in ["hi", "lo"]:
			RenderingServer.free_rid(e["inst_" + which])
			RenderingServer.free_rid(e["mm_" + which])
	_k.clear()


static func decode(buf: PackedFloat32Array, i: int) -> Dictionary:
	var o := i * STRIDE
	var s := buf[o + 16]
	var ly := GrassBlades.unpack2(buf[o + 13]) * 2.0 - Vector2.ONE
	var cp := GrassBlades.unpack2(buf[o + 14])
	return {
		"root": Vector3(buf[o + 3], buf[o + 7], buf[o + 11]),
		"facing": Vector3(buf[o + 2], buf[o + 6], buf[o + 10]) / maxf(s, 1e-6),
		"scale": s,
		"g": buf[o + 17],
		"seed": GrassBlades.unpack2(buf[o + 12]).x,
		"lay": ly,
		"crush": cp.x,
		"push": cp.y,
		"morph": GrassBlades.unpack2(buf[o + 15]).x,
	}
