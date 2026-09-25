# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
class_name TestGrassQuery
extends GrassSuite
## GrassQuery on a synthetic ground, the addon's fixture species: a mixed
## ground grows its mix by area; a painted override plants where the ground allows grass; a forced one plants anywhere;
## a band swaps the mix above its elevation; a land mix under the sea grows nothing, a sea species does; a road grows
## nothing and its verge the fallback; a bed's path grows nothing; a steep slope and a missing region grow nothing; a
## species in flower names its flower; a region still loading says so.

const A := 0
const B := 1
const ASPHALT := 2
const TABLE := {"default": 1.0, "slots": {
	"A": {"density": 1.0, "species": {"pasture": 0.5, "verge": 0.5}},
	"B": {"density": 1.0, "species": {"susuki": 1.0}, "bands": [{"above_m": 15.0, "species": {"summit": 1.0}}]},
	"Asphalt": {"density": 0.0}}}


## A footprint with one road along z = 10 (half width 3 m, with a verge), as a road source's snapshot gives it.
class _Road:
	func is_empty() -> bool:
		return false

	func snapshot(_origin: Vector2, _window: float, _pad: float) -> Dictionary:
		return {"segs": PackedFloat32Array([-100.0, 10.0, 100.0, 10.0, 3.0, 1.0]), "polys": []}


static func run() -> Dictionary:
	var keep := GrassSuite.use_fixture_species()
	var r := await GrassSuite.run_suite(TestGrassQuery.new(), "grass_query")
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
		ta.call("set_name", ["A", "B", "Asphalt"][i])
		ta.call("set_albedo_texture", ImageTexture.create_from_image(img))
		ta.call("set_normal_texture", ImageTexture.create_from_image(img))
		a.call("set_texture_asset", i, ta)
	return a


## A query over a flat ground at `h` of texture `ground` with map texel `tex` everywhere.
func _query(ground: int, tex: Color, h := 0.0) -> GrassQuery:
	var q := GrassQuery.new()
	q.types = GrassTypes.new()
	q.kinds = DecoKinds.new(DecoKinds.FROM_CONFIG, q.types)
	var growth := GrassTerrainGrowth.from_json_text(JSON.stringify(TABLE))
	var assets := _assets()
	q.allow = growth.table_for(assets)
	q.mix = growth.mix_bytes(assets, q.types).to_float32_array()
	q.spacing = 0.5
	q.texel = func(_v: Vector2i) -> Color: return tex
	q.control = func(_v: Vector2i) -> int: return _cw(ground)
	q.height = func(_v: Vector2i) -> float: return h
	return q


func _slot(q: GrassQuery, nm: String) -> int:
	return q.types.names().find(nm)


func test_a_mixed_ground() -> void:
	var q := _query(A, GrassMaps.NEUTRAL)
	var n := {}
	seed(3)
	for i in 400:
		var s := q.sample(Vector3(randf() * 200.0, 0.0, randf() * 200.0))
		n[s.species] = int(n.get(s.species, 0)) + 1
	assert_eq(n.keys().size(), 2, "two species (%s)" % [n])
	assert_true(absf(float(n.get(&"pasture", 0)) / 400.0 - 0.5) < 0.12, "by area, about half each (%s)" % [n])
	var s := q.sample(Vector3(3.0, 0.0, 4.0))
	var row := q.types.row(_slot(q, s.species))
	assert_near(s.density, 1.0, 1e-6, "x1 on a ground that allows grass: density 1")
	assert_near(s.height_m, float(row["height"]) * (128.0 / 255.0) * 2.0, 1e-4, "its height at the map's scale")
	assert_true(s.colour == GrassColour.at(row, 0.5, 0.5, float(row.get("accent", 0.0))) and not s.forced
		and not s.on_road, "its colour; not forced, not on a road")


func test_overrides_and_force() -> void:
	var chigaya := GrassMapCodec.encode(1.0, 3, 0.5)
	assert_eq(_query(A, chigaya).sample(Vector3(1, 0, 1)).species, &"chigaya", "an override plants on grass")
	var bare := _query(ASPHALT, GrassMaps.NEUTRAL).sample(Vector3(1, 0, 1))
	assert_true(bare.species == &"" and bare.density == 0.0, "Asphalt grows nothing")
	assert_eq(_query(ASPHALT, chigaya).sample(Vector3(1, 0, 1)).density, 0.0, "an override does not plant on Asphalt")
	var forced := _query(ASPHALT, GrassMapCodec.encode(1.0, 3, 0.5, true)).sample(Vector3(1, 0, 1))
	assert_true(forced.species == &"chigaya" and forced.forced and is_equal_approx(forced.density, 1.0),
		"a forced override plants anywhere")
	assert_near(_query(A, GrassMapCodec.encode(2.0, 3, 0.5)).sample(Vector3(1, 0, 1)).density, 2.0, 0.01,
		"R 255: twice the density")


func test_the_band() -> void:
	assert_eq(_query(B, GrassMaps.NEUTRAL, 0.0).sample(Vector3(1, 0, 1)).species, &"susuki", "below the band: susuki")
	assert_eq(_query(B, GrassMaps.NEUTRAL, 40.0).sample(Vector3(1, 40, 1)).species, &"summit", "above: summit")


func test_the_sea() -> void:
	var q := _query(A, GrassMaps.NEUTRAL)
	q.sea_level = 5.0
	var s := q.sample(Vector3(1, 0, 1))
	assert_true(s.species == &"" and s.density == 0.0, "a land mix 5 m under the sea grows nothing")
	var sg := _query(A, GrassMapCodec.encode(1.0, 18, 0.5))
	sg.sea_level = 5.0
	var t := sg.sample(Vector3(1, 0, 1))
	assert_true(t.species == &"seagrass" and t.density > 0.99, "seagrass 5 m down grows (%s, %.3f)" % [t.species, t.density])


func test_roads_and_beds() -> void:
	var q := _query(A, GrassMaps.NEUTRAL)
	var r := GrassRoads.new()
	r.footprint = _Road.new()
	q.road_origin = r.window_for(Vector2(0, 0))
	q.road_pack = r.pack(q.road_origin)
	var on := q.sample(Vector3(5, 0, 10))
	assert_true(on.on_road and on.density == 0.0, "on the road: nothing")
	var verge := q.sample(Vector3(5, 0, 10.0 + 3.0 + GrassRoads.MARGIN_M + 0.7))
	assert_true(verge.species == &"verge" and verge.density >= 0.85, "the verge band: the fallback, at least 0.85")
	var fr := _query(A, GrassMapCodec.encode(1.0, 6, 0.5))
	assert_eq(fr.sample(Vector3(1, 0, 0.5)).species, &"freesia", "freesia in its bed (1.2 m beds, 0.6 m paths)")
	assert_eq(fr.sample(Vector3(1, 0, 1.5)).density, 0.0, "nothing in the path")


func test_slope_and_missing_ground() -> void:
	var q := _query(A, GrassMaps.NEUTRAL)
	q.height = func(v: Vector2i) -> float: return float(v.x) * 0.5 * 2.0      # a 63 degree slope
	assert_eq(q.sample(Vector3(1, 2, 1)).density, 0.0, "steeper than max_slope: nothing")
	q.height = func(_v: Vector2i) -> float: return NAN
	assert_eq(q.sample(Vector3(1, 0, 1)).density, 0.0, "no region: nothing")


func test_flowers_and_pending() -> void:
	var q := _query(A, GrassMapCodec.encode(1.0, 6, 0.5))
	var ki := q.kinds.index_of("freesia")
	q.deco_state = func(i: int) -> Vector2: return Vector2(1.0, 1.0) if i == ki else Vector2.ZERO
	var s := q.sample(Vector3(1, 0, 0.5))
	var cols := q.kinds.colours(ki, 1.0)
	var pi := GrassHash.palette_index(Vector2(1, 0.5), q.kinds.kinds[ki]["cell"], cols.size(), q.kinds.palette_salt(ki))
	assert_true(s.flower == &"freesia" and s.flower_colour.is_equal_approx((cols[pi] as Color).linear_to_srgb()),
		"in bloom: its flower and its palette colour here")
	q.deco_state = func(_i: int) -> Vector2: return Vector2.ZERO
	assert_true(q.sample(Vector3(1, 0, 0.5)).flower == &"", "out of bloom: none")
	q.pending = func(_v: Vector2i) -> bool: return true
	assert_true(q.sample(Vector3(1, 0, 0.5)).pending, "a region still loading says so")
