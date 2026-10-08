# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name GrassFarField
extends RefCounted
## The grass far field in the terrain shader (grass_far.gdshaderinc, which the terrain's shader includes):
## canopy light + carpet grain past the blades. GrassBlades feeds it through Terrain3DMaterial's own
## set_shader_param and switches it with the blades. A terrain without grass keeps the shader's default
## grass_far_enabled = false: the ground exactly as without it.
##
## NOT by RID: Terrain3DMaterial re-sends every uniform the shader declares from its OWN table whenever
## it rebuilds its shader (a repaint, new assets), and a uniform it never saw goes out as null: a
## value set with RenderingServer.material_set_param is ERASED (the far field would switch itself off
## after the first repaint). set_shader_param stores into that table; it drops a name the material
## does not list yet (before its first shader build), so in_sync() reads the switch back each frame
## and the caller re-pushes when it is missing.
##
## The EDITOR (`direct`): that table is saved with the scene, so every save would carry wind and sun values
## into the terrain. There the far field writes the RenderingServer's copy only: a rebuild erases it, and
## in_sync() then reads back so the caller re-pushes the next frame (a rebuild is a shader change or a
## Navigation/Region tool switch, not a paint stroke).

const WIND_KEYS := [&"wind_dir", &"wind_scroll", &"wind_scroll2", &"wind_scroll_sw", &"gust_scale"]

var _mat: Object = null
var _rid := RID()
var _enabled := false
var _slot_tex: ImageTexture = null   # slot_texture()
var direct := false            # the editor: RenderingServer writes only, never the saved table (set before bind)


## Bind to `terrain`'s material. True when it is new (the caller pushes the static inputs).
func bind(terrain: Node) -> bool:
	var m: Object = terrain.get("material") if terrain != null else null
	var rid := RID()
	if m != null and m.has_method("get_material_rid"):
		rid = m.call("get_material_rid")
	if m == _mat and rid == _rid:
		return false
	_mat = m
	_rid = rid
	_enabled = false
	return rid.is_valid()


func is_bound() -> bool:
	return _mat != null and _rid.is_valid()


## One uniform on the terrain material: through Terrain3DMaterial's table (Textures as objects), or in the
## editor straight to the RenderingServer (Textures as RIDs).
func set_param(uniform_name: StringName, value) -> void:
	if _mat == null:
		return
	if direct:
		RenderingServer.material_set_param(_rid, uniform_name, value.get_rid() if value is Texture else value)
	else:
		_mat.call("set_shader_param", uniform_name, value)


## True while the material still holds the switch as last set (false before it lists the far field's
## uniforms, or if anything took them away): the caller re-pushes everything.
func in_sync() -> bool:
	if not is_bound():
		return false
	var v = RenderingServer.material_get_param(_rid, &"grass_far_enabled") if direct \
		else _mat.call("get_shader_param", &"grass_far_enabled")
	return v == _enabled


func set_enabled(on: bool) -> void:
	if not is_bound() or (on == _enabled and in_sync()):
		return
	_enabled = on
	set_param(&"grass_far_enabled", on)


func is_enabled() -> bool:
	return _enabled


## What changes rarely: the grain bake (GrassFarGrain.load_baked; {} runs without grain), the terrain
## rule by texture id, each type's blade height, the gust texture, the grass map array and its slot table
## (GrassMaps.slot_table: the shader reads a terrain layer's map through it).
func push_static(grain: Dictionary, allow: PackedFloat32Array, heights: PackedFloat32Array, gust: Texture2D,
		slots := PackedVector4Array(), maps: Texture2DArray = null, map_slots := PackedInt32Array()) -> void:
	set_param(&"grass_allow", allow)
	if not slots.is_empty():
		set_param(&"far_slot", slots)       # each texture id's mix (GrassTerrainGrowth.far_slot_params)
	set_param(&"far_type_h", heights)
	set_param(&"gust_tex", gust)
	var on := grain.has("tex")
	set_param(&"far_grain_on", on)
	if on:
		set_param(&"far_grain_tex", grain["tex"])
		set_param(&"far_grain_mean", grain["mean"])
		set_param(&"far_grain_std", grain["std"])
		set_param(&"far_grain_m", float(grain.get("tile_m", GrassFarGrain.TILE_M)))
	if maps != null:
		set_param(&"grass_maps", maps)      # GrassMaps: the grass map array, a layer per map
		set_param(&"grass_map_slots", slot_texture(map_slots))


## GrassMaps.slot_table() as the terrain shader reads it (grass_map_slots): one RF texel per terrain layer, 1 + its map's
## layer, 0 where its region has no map. Updated in place: its RID stays the one the material holds.
func slot_texture(table: PackedInt32Array) -> ImageTexture:
	var img := slot_image(table)
	if _slot_tex == null:
		_slot_tex = ImageTexture.create_from_image(img)
	else:
		_slot_tex.update(img)
	return _slot_tex


## The slot table as GrassMaps.MAP_CELLS x 1 RF texels (exact integers), padded with 0 (no map) or cut to that length.
static func slot_image(table: PackedInt32Array) -> Image:
	var f := PackedFloat32Array()
	f.resize(GrassMaps.MAP_CELLS)
	for i in mini(table.size(), GrassMaps.MAP_CELLS):
		f[i] = float(table[i])
	return Image.create_from_data(GrassMaps.MAP_CELLS, 1, false, Image.FORMAT_RF, f.to_byte_array())


## Every frame: the wind (the gust bands follow it), the sun, and where the blades fade.
func push_frame(wind_uniforms: Dictionary, sun_travel: Vector3, ramp: Vector2, sea_level := -1e9) -> void:
	for k in WIND_KEYS:          # what wind_gust() and the gust bands read; the rest is the blades'
		set_param(k, wind_uniforms[k])
	set_param(&"sun_travel_dir", sun_travel)
	set_param(&"far_ramp", ramp)
	set_param(&"far_sea_level", sea_level)       # land only: below the sea it adds nothing


## True when a terrain material's shader (Terrain3DMaterial) declares `uniform_name`: the far field's include is in it,
## and new enough.
static func shader_has(mat: Object, uniform_name: StringName) -> bool:
	if mat == null or not mat.has_method("get_shader_rid"):
		return false
	var sh: RID = mat.call("get_shader_rid")
	if not sh.is_valid():
		return false
	for u in RenderingServer.get_shader_parameter_list(sh):
		if StringName(u.get("name", "")) == uniform_name:
			return true
	return false


## The paint overlay (GrassOverlay.Mode; OFF: the far field as usual) and the colors it draws with.
func set_overlay(mode: int) -> void:
	set_param(&"grass_overlay", mode)
	if mode != GrassOverlay.Mode.OFF:
		set_param(&"grass_overlay_hue", GrassOverlay.hues_linear())
		set_param(&"grass_overlay_key", GrassOverlay.key_linear())


## Off, then forget the material (GrassBlades leaving the tree).
func unbind() -> void:
	if is_bound():
		set_param(&"grass_far_enabled", false)
	_mat = null
	_rid = RID()
	_enabled = false


## Each type's blade height (m), GrassTypes.SLOTS slots (empty slots 0): how much ground a blade's side hides.
static func type_heights(types: GrassTypes) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for i in GrassTypes.SLOTS:
		out.append(float(types.row(i).get("height", 0.0)))
	return out
