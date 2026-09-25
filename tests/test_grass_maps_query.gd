# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
class_name TestGrassMapsQuery
extends GrassSuite
## The map texels GrassBlades.sample() reads: a held map at once; a region
## the game holds no image of is read from its file on a worker thread (NEUTRAL, and pending, until it lands); a region
## without a file is NEUTRAL; at most QUERY_REGIONS regions are kept, the least recently used going first.


class _Maps extends GrassMaps:
	var dir := ""

	func path_for(p_loc: Vector2i) -> String:
		return dir.path_join("m_%d_%d.res" % [p_loc.x, p_loc.y])


static func run() -> Dictionary:
	return await GrassSuite.run_suite(TestGrassMapsQuery.new(), "grass_maps_query")


func _maps() -> _Maps:
	var m := _Maps.new()
	m._size = 4
	m.dir = OS.get_temp_dir().path_join("grass_maps_query_test")
	DirAccess.make_dir_recursive_absolute(m.dir)
	for f in DirAccess.get_files_at(m.dir):
		DirAccess.remove_absolute(m.dir.path_join(f))
	return m


func _write(m: _Maps, loc: Vector2i, c: Color) -> void:
	var img := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(c)
	ResourceSaver.save(img, m.path_for(loc))


func _settle(m: _Maps, v: Vector2i) -> Color:
	var c := m.query_texel(v)
	for i in 400:
		if not m.query_pending(v):
			break
		OS.delay_msec(5)
		c = m.query_texel(v)
	return m.query_texel(v)


func test_held_loaded_and_missing() -> void:
	var m := _maps()
	var held := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	held.fill(Color8(10, 20, 30, 255))
	m.adopt(Vector2i(-1, 0), held)
	assert_eq(m.query_texel(Vector2i(-2, 1)), Color8(10, 20, 30, 255), "a held map at once")
	_write(m, Vector2i(0, 0), Color8(200, 4, 128, 255))
	var first := m.query_texel(Vector2i(1, 2))
	assert_true(first == GrassMaps.NEUTRAL and m.query_pending(Vector2i(1, 2)), "a file: NEUTRAL and pending at first")
	assert_eq(_settle(m, Vector2i(1, 2)), Color8(200, 4, 128, 255), "then its texel")
	assert_true(m.query_texel(Vector2i(9, 9)) == GrassMaps.NEUTRAL and not m.query_pending(Vector2i(9, 9)),
		"no file: NEUTRAL, not pending")


func test_the_least_recently_used_goes() -> void:
	var m := _maps()
	for i in GrassMaps.QUERY_REGIONS + 1:
		_write(m, Vector2i(i, 0), Color8(i, 0, 128, 255))
	for i in GrassMaps.QUERY_REGIONS + 1:
		_settle(m, Vector2i(i * 4, 0))
	assert_true(not m._q_images.has(Vector2i(0, 0)) and m._q_images.has(Vector2i(GrassMaps.QUERY_REGIONS, 0)),
		"the oldest region went, the newest stays")
	assert_eq(m._q_images.size(), GrassMaps.QUERY_REGIONS, "no more than QUERY_REGIONS kept")
