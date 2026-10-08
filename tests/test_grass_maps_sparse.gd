# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
class_name TestGrassMapsSparse
extends GrassSuite
## The map arrays cost memory by the maps that EXIST, not by the terrain's slots: a terrain with no map holds a 1x1x1
## array (the shaders read NEUTRAL without fetching), one with maps holds a layer per map it can have resident at once,
## and a region landing or leaving allocates no NEUTRAL image.

var dir := OS.get_temp_dir().path_join("grass_maps_sparse_%d" % Time.get_ticks_usec())


static func run() -> Dictionary:
	return await GrassSuite.run_suite(TestGrassMapsSparse.new(), "grass_maps_sparse")


## Counts the full-size NEUTRAL images it makes.
class _Counting extends GrassMaps:
	var neutrals := 0

	func _neutral() -> Image:
		neutrals += 1
		return super()


class FakeData extends RefCounted:
	var region_map := PackedInt32Array()
	var locations: Array = []

	func _init() -> void:
		region_map.resize(GrassMaps.MAP_SIZE * GrassMaps.MAP_SIZE)

	func put(loc: Vector2i, layer: int) -> void:
		region_map[(loc.y + 16) * GrassMaps.MAP_SIZE + loc.x + 16] = layer + 1
		if not locations.has(loc):
			locations.append(loc)

	func take(loc: Vector2i) -> void:
		region_map[(loc.y + 16) * GrassMaps.MAP_SIZE + loc.x + 16] = 0
		locations.erase(loc)

	func get_region_map() -> PackedInt32Array:
		return region_map

	func get_region_locations() -> Array:
		return locations


class UpstreamTerrain extends RefCounted:      # no streaming: one layer a region, re-packed when one goes
	var data := FakeData.new()
	var region_size := 4
	var vertex_spacing := 1.0
	var data_directory := ""


class StreamingTerrain extends UpstreamTerrain:     # a streaming Terrain3D build: one layer a slot
	var streaming_enabled := true
	var streaming_editor := true
	var streaming_slots := 4


func _file(folder: String, loc: Vector2i, c: Color, root := "") -> void:
	var d := (dir if root == "" else root).path_join(folder)
	DirAccess.make_dir_recursive_absolute(d)
	var img := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(c)
	ResourceSaver.save(img, d.path_join(Terrain3DUtil.location_to_filename(loc)))


## slot_table()'s first `n` entries.
func _slots(m: GrassMaps, n := 4) -> Array:
	return Array(m.slot_table().slice(0, n))


func _settle(maps: Array) -> void:
	var until := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < until:
		var busy := false
		for m in maps:
			(m as GrassMaps).poll()
			busy = busy or (m as GrassMaps).pending() > 0
		if not busy:
			return
		OS.delay_msec(2)


func _dims(m: GrassMaps) -> Vector3i:
	var t := m.texture()
	return Vector3i(t.get_width(), t.get_height(), t.get_layers()) if t != null else Vector3i(-1, -1, -1)


## The game (no images kept) on a streaming terrain of 4 slots: one grass map on disk, no water map at all.
func test_the_arrays_hold_only_the_maps_that_exist() -> void:
	_file("grass", Vector2i(3, 3), Color8(11, 22, 33, 255))
	var t := StreamingTerrain.new()
	t.data_directory = dir
	t.data.put(Vector2i(0, 0), 0)                               # resident, no map
	var grass := _Counting.new()
	var water := _Counting.new()
	water.folder = GrassBlades.water_folder("grass")
	grass.bind(t)
	water.bind(t)
	assert_eq(_dims(water), Vector3i(1, 1, 1), "no water map anywhere: a 1x1x1 array, not a layer a slot")
	assert_eq(_dims(grass), Vector3i(1, 1, 1), "no grass map resident yet: 1x1x1 too")
	assert_eq(grass.neutrals + water.neutrals, 0, "the bind made no NEUTRAL image")
	t.data.put(Vector2i(1, 0), 1)                               # lands, no map
	t.data.put(Vector2i(3, 3), 2)                               # lands, its map on disk
	grass.refresh()
	water.refresh()
	_settle([grass, water])
	assert_eq(_dims(grass), Vector3i(4, 4, 1), "one map on disk: one layer of the region's size")
	assert_eq(_dims(water), Vector3i(1, 1, 1), "the water array stays 1x1x1")
	assert_eq(grass.neutrals + water.neutrals, 0, "a landing allocates no NEUTRAL image")
	assert_eq(grass.layers(), [Vector2i(0, 0), Vector2i(1, 0), Vector2i(3, 3), null], "the slots still read as before")
	t.data.take(Vector2i(3, 3))                                 # leaves
	t.data.take(Vector2i(1, 0))
	t.data.put(Vector2i(2, 0), 1)                               # another lands in a freed slot, no map
	grass.refresh()
	water.refresh()
	_settle([grass, water])
	assert_eq([_dims(grass), grass.neutrals + water.neutrals], [Vector3i(4, 4, 1), 0],
		"leaving and landing again: no new layer, no NEUTRAL image")


## The slot table the shaders read: terrain layer -> 1 + the map's layer, 0 for none. A landing takes a free layer, a
## region leaving gives it back, and the array is never rebuilt while the maps on disk fit.
func test_the_slot_table() -> void:
	var root := dir.path_join("table")
	_file("grass", Vector2i(3, 3), Color8(1, 2, 3, 255), root)
	_file("grass", Vector2i(5, 5), Color8(4, 5, 6, 255), root)
	var t := StreamingTerrain.new()
	t.data_directory = root
	t.data.put(Vector2i(0, 0), 0)
	t.data.put(Vector2i(3, 3), 1)
	var g := GrassMaps.new()
	g.bind(t)
	var tex := g.texture()
	assert_eq([g.capacity(), g.map_layer_of(Vector2i(3, 3)), g.map_layer_of(Vector2i(0, 0))], [2, 0, -1],
		"room for the 2 maps on disk; (3, 3) in layer 0, (0, 0) has none")
	assert_eq([g.slot_table().size(), _slots(g)], [GrassMaps.MAP_CELLS, [0, 1, 0, 0]],
		"MAP_CELLS long; slot 1 holds (3, 3): its map's layer + 1")
	var v0 := g.table_version()
	t.data.put(Vector2i(5, 5), 3)
	g.refresh()
	assert_eq(_slots(g), [0, 1, 0, 0], "landing: 0 while its map loads (NEUTRAL)")
	_settle([g])
	assert_true(g.table_version() > v0 and _slots(g) == [0, 1, 0, 2], "then its layer: %s" % [_slots(g)])
	t.data.take(Vector2i(3, 3))
	g.refresh()
	assert_eq([_slots(g), g.map_layer_of(Vector2i(3, 3))], [[0, 0, 0, 2], -1], "leaving: its layer is free")
	t.data.put(Vector2i(3, 3), 2)
	g.refresh()
	_settle([g])
	assert_eq([_slots(g), g.texture() == tex], [[0, 0, 1, 2], true],
		"back in another slot: the free layer again, the same array (nothing reallocated)")


## Upstream Terrain3D (no streaming, one layer a region): removing a region re-packs the layers. The maps keep their
## layers; only the table follows.
func test_an_upstream_terrain_repacks_its_layers() -> void:
	var root := dir.path_join("upstream")
	_file("grass", Vector2i(0, 0), Color8(1, 2, 3, 255), root)
	_file("grass", Vector2i(2, 0), Color8(4, 5, 6, 255), root)
	var t := UpstreamTerrain.new()
	t.data_directory = root
	t.data.put(Vector2i(0, 0), 0)
	t.data.put(Vector2i(1, 0), 1)
	t.data.put(Vector2i(2, 0), 2)
	var g := GrassMaps.new()
	g.bind(t)
	var tex := g.texture()
	assert_eq([g.layers().size(), g.capacity(), _slots(g, 3)], [3, 2, [1, 0, 2]], "3 regions, 2 maps: 2 layers")
	t.data.take(Vector2i(1, 0))
	t.data.take(Vector2i(2, 0))
	t.data.put(Vector2i(2, 0), 1)                               # Terrain3D re-packs: (2, 0) is layer 1 now
	g.refresh()
	assert_eq([g.layers(), _slots(g, 3), g.texture() == tex, g.pending()], [[Vector2i(0, 0), Vector2i(2, 0)],
		[1, 2, 0], true, 0], "the table follows; the array and its maps stay, nothing is read again")


## The editor: a region without a file has no layer until it is painted (update_layer, as the brush and undo call it);
## then the array grows (doubling, at most the terrain's layers), and a pick or a stand-in image makes none.
func test_painting_gives_a_region_its_layer() -> void:
	var root := dir.path_join("editor")
	var t := UpstreamTerrain.new()
	t.data_directory = root
	t.data.put(Vector2i(0, 0), 0)
	t.data.put(Vector2i(1, 0), 1)
	t.data.put(Vector2i(0, 1), 2)
	var g := GrassMaps.new()
	g.keep_images = true
	g.editor = true
	g.bind(t)
	assert_eq([_dims(g), _slots(g, 3)], [Vector3i(1, 1, 1), [0, 0, 0]], "no map: the placeholder, no slot points at it")
	assert_eq(g.pixel(Vector3(1.5, 0.0, 5.5)), GrassMaps.NEUTRAL, "the picker on a region without a map: NEUTRAL")
	assert_eq(g.capacity(), 0, "and that made no layer")
	g.image(Vector2i(1, 0)).set_pixel(1, 1, Color8(9, 3, 128, 255))
	g.update_layer(Vector2i(1, 0))
	g.mark_dirty(Vector2i(1, 0))
	assert_eq([_dims(g), _slots(g, 3)], [Vector3i(4, 4, 1), [0, 1, 0]], "painted: a layer of its own")
	g.image(Vector2i(0, 1)).set_pixel(0, 0, Color8(7, 0, 128, 255))
	g.update_layer(Vector2i(0, 1))
	g.mark_dirty(Vector2i(0, 1))
	assert_eq([g.capacity(), _slots(g, 3)], [2, [0, 1, 2]], "a second: the array doubles, the first keeps its map")
	g.image(Vector2i(0, 0)).set_pixel(2, 2, Color8(5, 0, 128, 255))
	g.update_layer(Vector2i(0, 0))
	g.mark_dirty(Vector2i(0, 0))
	assert_eq([g.capacity(), _slots(g, 3)], [3, [3, 1, 2]], "a third: 3 layers, no more than the terrain has")
	assert_eq(g.pixel(Vector3(0.5, 0.0, 4.5)).r8, 7, "the picker reads the painted texel")
	g.save_dirty()
	assert_true(not g.unsaved() and FileAccess.file_exists(g.path_for(Vector2i(0, 1))), "saved")
	var game := GrassMaps.new()
	game.bind(t)
	assert_eq([game.capacity(), _slots(game, 3), game._images.is_empty()], [3, [1, 2, 3], true],
		"the game loads the 3 saved maps into 3 layers and keeps no image")


## The game adopting maps (pictures, the test world): each one placed, the array growing past the maps on disk. A map
## the game no longer holds is read again (on the worker pool) when it grows.
func test_adopted_maps_grow_the_game_array() -> void:
	var root := dir.path_join("adopt")
	_file("grass", Vector2i(0, 0), Color8(1, 2, 3, 255), root)
	var t := UpstreamTerrain.new()
	t.data_directory = root
	t.data.put(Vector2i(0, 0), 0)
	t.data.put(Vector2i(1, 0), 1)
	t.data.put(Vector2i(0, 1), 2)
	var g := GrassMaps.new()
	g.bind(t)
	assert_eq([g.capacity(), _slots(g, 3), g._images.is_empty()], [1, [1, 0, 0], true], "one map on disk, not held")
	var img := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color8(50, 0, 128, 255))
	g.adopt(Vector2i(1, 0), img)
	assert_eq([g.capacity(), g.map_layer_of(Vector2i(0, 0)) >= 0, g.map_layer_of(Vector2i(1, 0)) >= 0, g.sync_loads],
		[2, true, true, 0], "grown to 2: the file's map read again on the worker pool, both placed")
	g.adopt(Vector2i(0, 1), img)
	var got := _slots(g, 3)
	got.sort()
	assert_eq([g.capacity(), got, g._images.keys()], [3, [1, 2, 3], [Vector2i(1, 0), Vector2i(0, 1)]],
		"3 layers, each map its own; only the adopted images are held")


## What the GPU gets: binding 9 is the region map then the two tables (MAP_CELLS ints each, padded); the terrain shader's
## table is one RF texel per terrain layer.
func test_the_buffer_and_the_far_table() -> void:
	var map := PackedInt32Array()
	map.resize(GrassMaps.MAP_CELLS)
	map[3] = 7
	var b := GrassBlades.region_bytes(map, PackedInt32Array([0, 2, 1]), PackedInt32Array([5]))
	var ints := b.to_int32_array()
	assert_eq([b.size(), GrassBlades.REGION_BUF_BYTES], [3 * GrassMaps.MAP_CELLS * 4, b.size()], "3 x MAP_CELLS ints")
	assert_eq([ints[3], ints[1024], ints[1025], ints[1026], ints[1027], ints[2048], ints[2049]], [7, 0, 2, 1, 0, 5, 0],
		"region map, grass table at 1024, water table at 2048, zero-padded")
	var img := GrassFarField.slot_image(PackedInt32Array([0, 3, 1]))
	assert_eq([img.get_format(), img.get_size(), img.get_pixel(1, 0).r, img.get_pixel(2, 0).r, img.get_pixel(9, 0).r],
		[Image.FORMAT_RF, Vector2i(GrassMaps.MAP_CELLS, 1), 3.0, 1.0, 0.0], "the far field's table: exact, padded")
