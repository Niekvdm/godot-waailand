# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name GrassPictureRenderer
extends RefCounted
## One species as the Grass library shows it: GrassSpeciesPreview.recipe drawn
## in a small world of its own inside a SubViewport. An 8 x 8 m patch of the species on a flat two-by-two-region
## terrain wearing the ground it grows on most (the pack's picture_ground; a plain soil colour without one), on its
## flowers' date; a sea species under its sea level with no water surface; a floating species on a pool of water over
## the patch (a water source and a plane, its patch in the water maps); the pack's picture_environment for sky and
## light (a neutral sky and sun without one); the blades at high quality and held still; the camera framed to its
## tallest part. Its decorations grow at full density and its blades wear their own colour: the picture shows the
## plant, not how much of it a ground grows or the ground's tint on it. Frames are FORCED: the caller turns the render
## loop off (the picture tool, the render suites).

const SHOT := Vector2i(720, 480)          # the card at 2x; the tile is its lower middle
const TILE_PX := 112
const CARD := Vector2i(360, 240)
const REGION := 128                       # vertices a region side
const SPACING := 0.5                      # m a vertex
const PATCH := Rect2(-4.0, -4.0, 8.0, 8.0)
const SOIL := Color(0.19, 0.2, 0.1)         # a grassland soil (sRGB): short grass reads as turf on it, as on a green texture
const WATER := Color(0.10, 0.16, 0.14)      # a pond's still water (sRGB), under a floating species

static var _warm := false                 # this process has drawn a picture


## A floating species' pool: the patch and a metre around it, `level` m over the flat ground (GrassBlades.set_water).
class _PatchWater:
	var level := 0.0

	func _init(p_level: float) -> void:
		level = p_level

	func is_empty() -> bool:
		return false

	func snapshot(_origin: Vector2, _window: float, _pad: float) -> Dictionary:
		var r := PATCH.grow(1.0)
		return {"polys": [PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end,
			Vector2(r.position.x, r.end.y)])], "heights": PackedFloat32Array([level]),
			"kinds": PackedStringArray(["Picture"])}


## The pack's own tables, on the project's slots: [GrassTypes, DecoKinds].
static func tables(p_pack: GrassSpeciesPack) -> Array:
	var c := GrassSpeciesCatalog.build([p_pack], GrassSlotTable.load_file(GrassBladesConfig.current().slots_path))
	var t := GrassTypes.from_catalog(c)
	return [t, DecoKinds.from_catalog(c, t)]


## The species on `p_slot` as drawn into `vp` (sized SHOT). `bare`: the same ground, date and pose without it (the
## tests' control). The tables are copied: the picture's own changes (own colour, full density) stay in it.
static func render(vp: SubViewport, p_pack: GrassSpeciesPack, p_types: GrassTypes, p_kinds: DecoKinds,
		p_growth: GrassTerrainGrowth, p_slot: int, p_bare := false) -> Image:
	if not _warm:
		# The first picture a process draws reads darker (about 5% here) than the same picture drawn again, so the
		# first call draws it once to throw away.
		_warm = true
		await render(vp, p_pack, p_types, p_kinds, p_growth, p_slot, p_bare)
	var r := GrassSpeciesPreview.recipe(p_types, p_kinds, p_growth, p_slot)
	var types := GrassTypes.new("")
	types.rows = p_types.rows.duplicate(true)
	types.fallback_slot = p_types.fallback_slot
	types.rows[p_slot]["ground_colour"] = 0.0
	var kinds := DecoKinds.new("")
	kinds.kinds = p_kinds.kinds.duplicate(true)
	for k in kinds.kinds:
		if int(k["host"]) == p_slot:
			k["density"] = 1.0
			k["patch_share"] = 1.0
	var world := Node3D.new()
	vp.add_child(world)
	var cam := Camera3D.new()
	cam.current = true
	cam.fov = 70.0
	cam.far = 4000.0
	world.add_child(cam)
	var terrain: Node = await _terrain(world, cam, p_pack, String(r["ground"]))
	var blades := GrassBlades.new()
	blades.terrain = terrain
	blades.camera = cam
	blades.inputs = false
	blades.far_field = false
	blades.types = types
	blades.decorations.kinds = kinds
	blades.growth = p_growth
	blades.grid_pitch = 0.10
	blades.d_far0 = 25.0
	blades.d_far1 = 90.0
	blades.radius = 40.0
	blades.edge_fade_m = 2.0
	blades.cull_frustum = false
	blades.set_date(float(r["day"]))
	world.add_child(blades)
	var wd := float(r.get("water_depth", NAN))
	var floats := not is_nan(wd)
	var maps := _maps(p_slot, p_bare or floats)        # a floating species: the ground grows nothing
	for loc in maps:
		blades.grass_maps.adopt(loc, maps[loc])
	if floats:
		var wmaps := _maps(p_slot, p_bare)
		for loc in wmaps:
			blades.water_maps.adopt(loc, wmaps[loc])
		blades.set_water(_PatchWater.new(wd))
		blades.water_bob_m = 0.0
		world.add_child(_water_plane(wd))
	blades.set_uniform(&"colour_tex", blades.colour_texture())
	blades.set_shadow_mode(GrassBlades.ShadowMode.HIGH_CASTS)
	if not is_nan(float(r["sea_depth"])):
		blades.set_sea(float(r["sea_depth"]))        # the flat ground at 0: the patch that far under the sea
	blades.wind.calm()
	blades.wind.speed = 0.0
	for i in 60:
		if blades.is_live():
			break
		await world.get_tree().process_frame
	await world.get_tree().process_frame
	# The sky and light go in now, once the blades are live, and the picture is the eighth draw after: the sky's
	# light is still settling over those first draws (thirty draws later every picture reads about 5% brighter).
	# Every picture is drawn this way: changing the order or the count means bumping RENDER_VERSION.
	var sun := _environment(world, p_pack)
	blades.set_sun(-sun.global_basis.z)
	var h := maxf(float(r["frame_h"]), 0.25)
	var target := Vector3(0.0, 0.4 * h + (wd if floats else 0.0), 0.0)
	cam.global_position = target + Vector3(-0.35, 0.5, -1.0).normalized() * (1.5 * h + 1.3)
	cam.look_at(target, Vector3.UP)
	RenderingServer.camera_set_transform(cam.get_camera_rid(), cam.global_transform)   # forced draws skip the frame
	for i in 8:
		await blades.step()
	blades.frozen = true
	RenderingServer.force_draw(true, 0.0)
	RenderingServer.force_draw(true, 0.0)
	var img := vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	world.queue_free()
	await vp.get_tree().process_frame
	return img


## The tile: a square of the picture's lower middle, three quarters of its height (the plant, not the sky).
static func tile_of(img: Image, px: int) -> Image:
	var side := img.get_height() * 3 / 4
	var t := img.get_region(Rect2i((img.get_width() - side) / 2, img.get_height() - side - img.get_height() / 16,
		side, side))
	t.resize(px, px, Image.INTERPOLATE_LANCZOS)
	return t


## Saves a picture's tile (<id>.png) and card (<id>_card.png) into `p_dir` (an absolute or res:// folder).
static func save(img: Image, p_dir: String, p_id: String) -> void:
	var abs_dir := ProjectSettings.globalize_path(p_dir)
	var card := img.duplicate() as Image
	card.resize(CARD.x, CARD.y, Image.INTERPOLATE_LANCZOS)
	card.save_png(abs_dir.path_join(GrassSpeciesPreview.CARD % p_id))
	tile_of(img, TILE_PX).save_png(abs_dir.path_join(GrassSpeciesPreview.TILE % p_id))


## The sky and the sun: the pack's environment scene (auto exposure off, so pictures agree), or a neutral one.
static func _environment(world: Node3D, p_pack: GrassSpeciesPack) -> DirectionalLight3D:
	if p_pack != null and p_pack.picture_environment != null:
		var env := p_pack.picture_environment.instantiate()
		world.add_child(env)
		if env is WorldEnvironment and (env as WorldEnvironment).camera_attributes != null:
			(env as WorldEnvironment).camera_attributes.set("auto_exposure_enabled", false)
		var lights := env.find_children("*", "DirectionalLight3D", true, false)
		if not lights.is_empty():
			return lights[0] as DirectionalLight3D
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = e
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 80.0
	world.add_child(sun)
	return sun


## A flat terrain of four regions around the origin, wearing the ground (texture id 0). Region size, spacing and
## assets only hold once Terrain3D is initialised, so they are set a frame after it enters the tree.
static func _terrain(world: Node3D, cam: Camera3D, p_pack: GrassSpeciesPack, p_ground: String) -> Node:
	var t: Node = ClassDB.instantiate("Terrain3D")
	if p_pack != null and p_pack.picture_material != null:
		t.set("material", p_pack.picture_material.duplicate())
	world.add_child(t)
	t.call("set_camera", cam)
	await world.get_tree().process_frame
	t.set("region_size", REGION)
	t.set("vertex_spacing", SPACING)
	t.set("assets", _ground_assets(p_pack, p_ground))
	var data: Object = t.get("data")
	for ry in 2:
		for rx in 2:
			data.call("add_region_blank", Vector2i(rx - 1, ry - 1), false)
	data.call("update_maps")
	await world.get_tree().process_frame
	return t


## The pack's texture named like the ground (the pack's picture_default_ground for a species no ground grows; a copy:
## the pack's asset list keeps its ids), else a plain soil colour under the ground's name, so the growth table's
## allowance for it applies. Without a texture Terrain3D shows its checkered debug view instead of the ground.
static func _ground_assets(p_pack: GrassSpeciesPack, p_ground: String) -> Resource:
	var a: Resource = ClassDB.instantiate("Terrain3DAssets")
	var src: Resource = p_pack.picture_ground if p_pack != null else null       # held while its list is read
	var want := p_ground if p_ground != "" or p_pack == null else p_pack.picture_default_ground
	var ta: Resource = null
	if src != null and want != "":
		for x in src.call("get_texture_list"):
			if x != null and String(x.get("name")).to_lower() == want.to_lower():
				ta = (x as Resource).duplicate()
				break
	if ta == null:
		ta = _plain(want if want != "" else "Soil", SOIL)
	a.call("set_texture_asset", 0, ta)
	return a


## The pool's surface under a floating species: still water just below the floating roots.
static func _water_plane(level: float) -> MeshInstance3D:
	var pm := PlaneMesh.new()
	pm.size = PATCH.grow(1.0).size
	var m := StandardMaterial3D.new()
	m.albedo_color = WATER
	m.roughness = 0.55                       # still water, but no mirror of the sun: the plants are the picture
	m.metallic_specular = 0.25
	pm.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.position = Vector3(PATCH.get_center().x, level - 0.002, PATCH.get_center().y)
	return mi


## A 64 px texture asset of one colour (alpha: height), with a flat normal (alpha: roughness).
static func _plain(p_name: String, c: Color) -> Resource:
	var alb := Image.create_empty(64, 64, false, Image.FORMAT_RGBA8)
	alb.fill(Color(c.r, c.g, c.b, 0.5))
	alb.generate_mipmaps()
	var nrm := Image.create_empty(64, 64, false, Image.FORMAT_RGBA8)
	nrm.fill(Color(0.5, 0.5, 1.0, 0.95))
	nrm.generate_mipmaps()
	var ta: Resource = ClassDB.instantiate("Terrain3DTextureAsset")
	ta.call("set_name", p_name)
	ta.call("set_albedo_texture", ImageTexture.create_from_image(alb))
	ta.call("set_normal_texture", ImageTexture.create_from_image(nrm))
	return ta


## The grass maps: nothing grows (R 0) except the patch, which is the species at full density.
static func _maps(p_slot: int, p_bare: bool) -> Dictionary:
	var out := {}
	var empty := GrassMapCodec.encode(0.0, -1, 0.5)
	var plant := GrassMapCodec.encode(1.0, p_slot, 0.5)
	for ry in 2:
		for rx in 2:
			var loc := Vector2i(rx - 1, ry - 1)
			var img := Image.create_empty(REGION, REGION, false, Image.FORMAT_RGBA8)
			img.fill(empty)
			if not p_bare:
				for y in REGION:
					for x in REGION:
						if PATCH.has_point(Vector2(loc.x * REGION + x, loc.y * REGION + y) * SPACING):
							img.set_pixel(x, y, plant)
			out[loc] = img
	return out
