# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
class_name TestGrassWaterQuery
extends GrassSuite
## GrassQuery with water sources: the depth the species read is below the highest surface over them (a pond's or the
## sea's): land grass reaches an inland waterline and stops there, an emergent species stands in shallow water, a bed
## species grows under it; the surface layer (sample_water) floats a water kind's mix or a painted species on it.

const A := 0
const B := 1
const W := 2
const TABLE := {"default": 1.0, "slots": {
	"A": {"density": 1.0, "species": {"t_land": 1.0}},
	"B": {"density": 1.0, "species": {"t_rice": 1.0}},
	"W": {"density": 1.0, "species": {"t_weed": 1.0}}},
	"water": {"Vijver": {"density": 1.0, "species": {"t_lily": 1.0}}}}


static func run() -> Dictionary:
	var land := GrassSpecies.new()
	land.id = &"t_land"
	var rice := GrassSpecies.new()
	rice.id = &"t_rice"
	rice.wet_depth_m = 0.3
	var weed := GrassSpecies.new()
	weed.id = &"t_weed"
	weed.depth_m = Vector2(0.2, 3.0)
	weed.depth_feather_m = 0.1
	var keep := TestGrassWaterGrowth.use_water_fixture([land, rice, weed] as Array[GrassSpecies])
	var r := await GrassSuite.run_suite(TestGrassWaterQuery.new(), "grass_water_query")
	GrassBladesConfig.use(keep)
	return r


static func _cw(base: int) -> int:
	return (base & 0x1F) << 27


static func _assets() -> Resource:
	var a: Resource = ClassDB.instantiate("Terrain3DAssets")
	for i in 3:
		var img := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.3, 0.3, 0.3, 0.5))
		var ta: Resource = ClassDB.instantiate("Terrain3DTextureAsset")
		ta.call("set_name", ["A", "B", "W"][i])
		ta.call("set_albedo_texture", ImageTexture.create_from_image(img))
		ta.call("set_normal_texture", ImageTexture.create_from_image(img))
		a.call("set_texture_asset", i, ta)
	return a


## A query over a flat ground at `h` of texture `ground` with map texel `tex` everywhere, no water yet.
func _query(ground: int, tex: Color, h := 0.0) -> GrassQuery:
	var q := GrassQuery.new()
	q.types = GrassTypes.new()
	q.kinds = DecoKinds.new(DecoKinds.FROM_CONFIG, q.types)
	var growth := GrassTerrainGrowth.from_json_text(JSON.stringify(TABLE, "", false))
	assert_true(growth.errors.is_empty(), "the table reads: %s" % [growth.errors])
	var assets := _assets()
	q.allow = growth.table_for(assets)
	q.mix = growth.mix_bytes(assets, q.types).to_float32_array()
	q.water_mix = growth.water_bytes(q.types).to_float32_array()
	q.spacing = 0.5
	q.texel = func(_v: Vector2i) -> Color: return tex
	q.control = func(_v: Vector2i) -> int: return _cw(ground)
	q.height = func(_v: Vector2i) -> float: return h
	return q


## A pond 20 m square over x 0..20, z -10..10, its surface at `surface`, kind Vijver.
func _with_pond(q: GrassQuery, surface := 0.5) -> void:
	var w := GrassWater.new()
	var s := TestGrassWater._Ponds.new()
	s.polys = [PackedVector2Array([Vector2(0, -10), Vector2(20, -10), Vector2(20, 10), Vector2(0, 10)])]
	s.heights = PackedFloat32Array([surface])
	s.kinds = PackedStringArray(["Vijver"])
	w.source = s
	q.water_origin = w.window_for(Vector2.ZERO)
	q.water_pack = w.pack(q.water_origin, {"vijver": 0})


func test_land_stops_at_the_waterline() -> void:
	var q := _query(A, GrassMaps.NEUTRAL, 0.0)
	_with_pond(q)
	assert_eq(q.sample(Vector3(10, 0, 0)).species, &"", "0.5 m under a pond: no land grass")
	assert_eq(q.sample(Vector3(-10, 0, 0)).species, &"t_land", "beside it: land grass")
	var hi := _query(A, GrassMaps.NEUTRAL, 0.8)
	_with_pond(hi)
	assert_eq(hi.sample(Vector3(10, 0.8, 0)).species, &"t_land", "0.3 m above the surface: land (no shore inland)")
	var at_sea := _query(A, GrassMaps.NEUTRAL, 0.8)
	at_sea.sea_level = 0.5
	assert_true(at_sea.sample(Vector3(-10, 0.8, 0)).density < 0.01, "0.3 m above the SEA: none (its shore)")


func test_emergent_and_bed() -> void:
	var q := _query(B, GrassMaps.NEUTRAL, 0.3)
	_with_pond(q)
	assert_eq(q.sample(Vector3(10, 0.3, 0)).species, &"t_rice", "rice in 0.2 m of water")
	var deep := _query(B, GrassMaps.NEUTRAL, 0.0)
	_with_pond(deep)
	assert_eq(deep.sample(Vector3(10, 0, 0)).species, &"", "rice in 0.5 m: none")
	var bed := _query(W, GrassMaps.NEUTRAL, -0.5)
	_with_pond(bed)
	assert_eq(bed.sample(Vector3(10, -0.5, 0)).species, &"t_weed", "pond weed on a bed 1 m down")
	assert_eq(bed.sample(Vector3(-10, -0.5, 0)).species, &"", "and none on dry ground")


func test_the_highest_surface_and_the_sea() -> void:
	var q := _query(W, GrassMaps.NEUTRAL, -0.5)
	_with_pond(q, 0.5)
	q.sea_level = -2.0
	q.sea_kind = -1
	assert_eq(q.sample(Vector3(10, -0.5, 0)).species, &"t_weed", "the pond over a lower sea")
	q.sea_level = 3.0
	assert_eq(q.sample(Vector3(10, -0.5, 0)).species, &"", "under a sea 3.5 m deep the weed (to 3 m) stops")


func test_what_floats() -> void:
	var q := _query(W, GrassMaps.NEUTRAL, -0.5)
	_with_pond(q)
	var s := q.sample_water(Vector3(10, 0, 0))
	assert_eq(s.species, &"t_lily", "the pond's mix floats the lily")
	assert_near(s.surface_m, 0.5, 1e-6, "on the surface")
	assert_eq(q.sample_water(Vector3(-10, 0, 0)).species, &"", "no water: nothing floats")
	assert_true(is_nan(q.sample(Vector3(10, -0.5, 0)).surface_m), "the ground layer names no surface")
	var duck := _slot(q, "t_duck")
	var paint := _query(W, GrassMaps.NEUTRAL, -0.5)
	_with_pond(paint)
	paint.water_texel = func(_v: Vector2i) -> Color: return GrassMapCodec.encode(1.0, duck, 0.5)
	assert_eq(paint.sample_water(Vector3(10, 0, 0)).species, &"t_duck", "a painted override floats")
	var ground_sp := _query(W, GrassMaps.NEUTRAL, -0.5)
	_with_pond(ground_sp)
	ground_sp.water_texel = func(_v: Vector2i) -> Color: return GrassMapCodec.encode(1.0, _slot(q, "t_land"), 0.5)
	assert_eq(ground_sp.sample_water(Vector3(10, 0, 0)).species, &"", "a painted ground species floats nothing")
	var dry := _query(W, GrassMaps.NEUTRAL, 1.0)
	_with_pond(dry)
	assert_eq(dry.sample_water(Vector3(10, 1, 0)).species, &"", "a bank inside the outline: nothing floats")


func _slot(q: GrassQuery, nm: String) -> int:
	return q.types.names().find(nm)
