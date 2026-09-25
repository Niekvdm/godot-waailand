# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
class_name TestGrassBrush
extends GrassSuite
## The grass brush (a region's map starts NEUTRAL): SET_HARD at weight >= 0.5, SET_SPRAY never in between, LERP at least one step,
## SMOOTH toward the neighbours, several channels, REPLACE, the limits, the region fill (fast and texel paths agree).

const RS := 64


class FakeData extends RefCounted:
	var region_map := PackedInt32Array()

	func _init() -> void:
		region_map.resize(32 * 32)
		region_map[16 * 32 + 16] = 1                      # the region (0, 0), layer 0

	func get_region_map() -> PackedInt32Array:
		return region_map

	func get_region_locations() -> Array:
		return [Vector2i(0, 0)]

	func get_height(_p: Vector3) -> float:
		return 0.0                                          # flat at 0 m

	func get_normal(_p: Vector3) -> Vector3:
		return Vector3.UP                                   # slope 0°


class FakeTerrain extends RefCounted:
	var data := FakeData.new()
	var region_size := RS
	var vertex_spacing := 1.0
	var data_directory := ""


static func run() -> Dictionary:
	return await GrassSuite.run_suite(TestGrassBrush.new(), "grass_brush")


func _setup() -> GrassBrush:
	var t := FakeTerrain.new()
	var maps := GrassMaps.new()
	maps.keep_images = true
	maps.bind(t)
	var b := GrassBrush.new()
	b.maps = maps
	b.data = t.data
	b.rng.seed = 7
	return b


static func _brush(size := 8.0, strength := 1.0) -> Dictionary:
	var img := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	return {"size": size, "strength": strength, "image": img, "gamma": 1.0, "spin_speed": 0.0, "align_to_view": false,
		"rotation": 0.0, "pressure": 1.0}


func _dab(b: GrassBrush, x: float, z: float, brush: Dictionary, op: Dictionary) -> void:
	b.begin()
	b.dab(Vector3(x, 0.0, z), brush, op)


static func _byte(b: GrassBrush, x: float, z: float, ch: int) -> int:
	return roundi(b.maps.pixel(Vector3(x, 0.0, z))[ch] * 255.0)


func test_a_e_set_hard() -> void:
	var b := _setup()
	var M := GrassBrush.Mode
	_dab(b, 20, 20, _brush(8.0, 0.4), {"channel": 1, "mode": M.SET_HARD, "value": 7})
	assert_eq(_byte(b, 20, 20, 1), 0, "strength 0.4 < 0.5: SET_HARD changes nothing")
	assert_true(b.touched.is_empty(), "and touches no region")
	_dab(b, 20, 20, _brush(8.0, 0.6), {"channel": 1, "mode": M.SET_HARD, "value": 7})
	assert_eq(_byte(b, 20, 20, 1), 7, "SET_HARD wrote the value")
	assert_true(_byte(b, 20, 20, 0) == 128 and _byte(b, 20, 20, 2) == 128, "the other channels keep NEUTRAL")
	assert_true(_byte(b, 40, 40, 1) == 0 and _byte(b, 40, 40, 0) == 128, "outside the brush: NEUTRAL")
	assert_true(b.touched.has(Vector2i(0, 0)), "the region is touched (its dirty rect)")


func test_b_set_spray() -> void:
	var b := _setup()
	var op := {"channel": 1, "mode": GrassBrush.Mode.SET_SPRAY, "value": 9}
	_dab(b, 44, 44, _brush(8.0, 0.5), op)
	var nine := 0
	var zero := 0
	var other := 0
	for z in range(41, 48):
		for x in range(41, 48):
			var v := _byte(b, x, z, 1)
			nine += 1 if v == 9 else 0
			zero += 1 if v == 0 else 0
			other += 1 if v != 9 and v != 0 else 0
	assert_true(nine > 0 and zero > 0, "one spray dab at 0.5: some written (%d), some not (%d)" % [nine, zero])
	assert_eq(other, 0, "never an in-between value")
	for i in 30:
		_dab(b, 44, 44, _brush(8.0, 0.5), op)
	var all9 := true
	for z in range(41, 48):
		for x in range(41, 48):
			all9 = all9 and _byte(b, x, z, 1) == 9
	assert_true(all9, "30 more dabs fill the brush")


func test_c_lerp() -> void:
	var b := _setup()
	var up := {"channel": 0, "mode": GrassBrush.Mode.LERP, "value": 255}
	_dab(b, 20, 44, _brush(8.0, 0.01), up)
	assert_eq(_byte(b, 20, 44, 0), 129, "a 1% dab still moves one step")
	for i in 200:
		_dab(b, 20, 44, _brush(8.0, 0.01), up)
	assert_eq(_byte(b, 20, 44, 0), 255, "and reaches the value, never past it")
	_dab(b, 10, 30, _brush(8.0, 0.01), {"channel": 0, "mode": GrassBrush.Mode.LERP, "value": 0})
	assert_eq(_byte(b, 10, 30, 0), 127, "and down: one step toward 0")


func test_d_smooth() -> void:
	var b := _setup()
	_dab(b, 50, 10, _brush(2.0, 1.0), {"channel": 2, "mode": GrassBrush.Mode.SET_HARD, "value": 255})
	var spike := _byte(b, 50, 10, 2)
	_dab(b, 50, 10, _brush(8.0, 1.0), {"channel": 2, "mode": GrassBrush.Mode.SMOOTH})
	assert_true(spike == 255 and _byte(b, 50, 10, 2) < 255, "SMOOTH lowers the spike (%d -> %d)" % [spike, _byte(b, 50, 10, 2)])


func test_j_k_l_channels_replace_and_nothing() -> void:
	var b := _setup()
	_dab(b, 30, 50, _brush(8.0, 1.0), {})
	assert_true(_byte(b, 30, 50, 0) == 128 and b.touched.is_empty(), "no channel: nothing (the fork's case J)")
	_dab(b, 12, 52, _brush(4.0, 1.0), {"channel": 1, "channels": PackedInt32Array([1, 3]), "values": PackedInt32Array([5, 0]),
		"mode": GrassBrush.Mode.SET_HARD})
	assert_true(_byte(b, 12, 52, 1) == 5 and _byte(b, 12, 52, 3) == 0 and _byte(b, 12, 52, 0) == 128,
		"two channels in one stroke; the others keep NEUTRAL")
	_dab(b, 16, 52, _brush(16.0, 1.0), {"channel": 1, "mode": GrassBrush.Mode.REPLACE, "from": 5, "value": 9})
	assert_eq(_byte(b, 12, 52, 1), 9, "replace: 5 becomes 9")
	assert_eq(_byte(b, 20, 52, 1), 0, "a texel holding something else stays")


func test_m_limits() -> void:
	var b := _setup()
	var op := {"channel": 0, "mode": GrassBrush.Mode.SET_HARD, "value": 3}
	_dab(b, 52, 30, _brush(4.0, 1.0), op.merged({"height": Vector2(1.0, 10.0)}))
	assert_eq(_byte(b, 52, 30, 0), 128, "outside the elevation range: nothing")
	_dab(b, 52, 30, _brush(4.0, 1.0), op.merged({"slope": Vector2(10.0, 90.0)}))
	assert_eq(_byte(b, 52, 30, 0), 128, "outside the slope range: nothing")
	_dab(b, 52, 30, _brush(4.0, 1.0), op.merged({"slope": Vector2(0.0, 5.0), "height": Vector2(-1.0, 1.0)}))
	assert_eq(_byte(b, 52, 30, 0), 3, "inside both: written")


func test_n_region_fill() -> void:
	var b := _setup()
	var op := {"channel": 2, "mode": GrassBrush.Mode.SET_HARD, "value": 40, "fill_region": true}
	b.begin()
	b.dab(Vector3(5, 0, 5), _brush(2.0, 1.0), op)
	assert_true(_byte(b, 60, 60, 2) == 40 and _byte(b, 1, 62, 2) == 40, "a click fills the region, far from the brush")
	b.dab(Vector3(5, 0, 5), _brush(2.0, 1.0), op.merged({"value": 90}))
	assert_eq(_byte(b, 60, 60, 2), 40, "once a stroke")
	var slow := _setup()                                    # the texel path (a limit that never binds) agrees
	slow.begin()
	slow.dab(Vector3(5, 0, 5), _brush(2.0, 1.0), op.merged({"slope": Vector2(0.0, 90.0)}))
	assert_eq(slow.maps.image(Vector2i(0, 0)).get_data(), b.maps.image(Vector2i(0, 0)).get_data(),
		"the fast fill and the texel fill write the same bytes")
