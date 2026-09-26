# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
class_name TestGrassMaps
extends GrassSuite
## The grass maps: the region map's layout (the compute's inverse, with a
## window), files loaded (a missing one NEUTRAL, a wrong size converted with an error), layers following a changed
## region map, streaming slots, adopted maps (tests, tools), the picker's texel, the game dropping its images.

var dir := OS.get_temp_dir().path_join("grass_maps_test_%d" % Time.get_ticks_usec())


static func run() -> Dictionary:
	return await GrassSuite.run_suite(TestGrassMaps.new(), "grass_maps")


class FakeData extends RefCounted:
	var region_map := PackedInt32Array()
	var locations: Array = []

	func _init() -> void:
		region_map.resize(GrassMaps.MAP_SIZE * GrassMaps.MAP_SIZE)

	func put(loc: Vector2i, layer: int) -> void:
		region_map[(loc.y + 16) * GrassMaps.MAP_SIZE + loc.x + 16] = layer + 1
		if not locations.has(loc):
			locations.append(loc)

	func get_region_map() -> PackedInt32Array:
		return region_map

	func get_region_locations() -> Array:
		return locations


class FakeTerrain extends RefCounted:
	var data := FakeData.new()
	var region_size := 4
	var vertex_spacing := 1.0
	var data_directory := ""


class StreamingTerrain extends FakeTerrain:     # a streaming Terrain3D build: one layer a slot
	var streaming_enabled := true
	var streaming_editor := true
	var streaming_slots := 4


func _file(loc: Vector2i, c: Color, size := 4) -> void:
	DirAccess.make_dir_recursive_absolute(dir.path_join("grass"))
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	img.fill(c)
	ResourceSaver.save(img, dir.path_join("grass").path_join(Terrain3DUtil.location_to_filename(loc)))


func _terrain() -> FakeTerrain:
	var t := FakeTerrain.new()
	t.data_directory = dir
	return t


func test_the_layout_is_the_computes_inverse() -> void:
	var m := PackedInt32Array()
	m.resize(32 * 32)
	m[(0 + 16) * 32 + (0 + 16)] = 1
	m[(-1 + 16) * 32 + (2 + 16)] = 3
	assert_eq(GrassMaps.layout(m, Vector2i.ZERO), {0: Vector2i(0, 0), 2: Vector2i(2, -1)}, "layer = value - 1, at its cell")
	assert_eq(GrassMaps.layout(m, Vector2i(5, 1)), {0: Vector2i(5, 1), 2: Vector2i(7, 0)}, "a window shifts it")


func test_files_neutral_and_errors() -> void:
	_file(Vector2i(0, 0), Color8(200, 3, 64, 255))
	_file(Vector2i(1, 0), Color8(9, 9, 9, 255), 8)            # the wrong size
	var t := _terrain()
	t.data.put(Vector2i(0, 0), 0)
	t.data.put(Vector2i(1, 0), 1)
	t.data.put(Vector2i(0, 1), 2)                              # no file
	var g := GrassMaps.new()
	g.keep_images = true
	g.bind(t)
	assert_eq(g.layers(), [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)], "one layer a region, in the map's order")
	assert_eq(g.image(Vector2i(0, 0)).get_pixel(1, 1).to_rgba32(), Color8(200, 3, 64, 255).to_rgba32(), "a file loads")
	assert_eq(g.image(Vector2i(0, 1)).get_pixel(0, 0).to_rgba32(), GrassMaps.NEUTRAL.to_rgba32(), "no file: NEUTRAL")
	assert_eq(g.image(Vector2i(1, 0)).get_size(), Vector2i(4, 4), "a wrong size is resized")
	assert_eq(g.errors.size(), 1, "and reported (%s)" % [g.errors])
	assert_true(g.texture() != null and g.rid().is_valid(), "the texture is built")


func test_a_changed_region_map() -> void:
	_file(Vector2i(2, 2), Color8(1, 2, 3, 255))
	var t := _terrain()
	t.data.put(Vector2i(0, 0), 0)
	var g := GrassMaps.new()
	g.keep_images = true
	var fired := [0]
	g.changed.connect(func() -> void: fired[0] += 1)
	g.bind(t)
	t.data.put(Vector2i(2, 2), 1)
	g.refresh()
	assert_eq([g.layers(), g.layer_of(Vector2i(2, 2)), fired[0]], [[Vector2i(0, 0), Vector2i(2, 2)], 1, 2],
		"a new region: a new layer, loaded; changed told twice")
	var t2 := _terrain()                                        # a terrain without regions
	var g2 := GrassMaps.new()
	g2.keep_images = true
	g2.bind(t2)
	assert_eq(g2.layers(), [], "no regions: no layers")


func test_adopt_pixel_and_the_game() -> void:
	var t := _terrain()
	t.data.put(Vector2i(0, 0), 0)
	var g := GrassMaps.new()
	g.keep_images = true
	g.bind(t)
	var img := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color8(7, 8, 9, 255))
	img.set_pixel(2, 1, Color8(50, 60, 70, 255))
	g.adopt(Vector2i(0, 0), img)
	assert_eq(g.pixel(Vector3(2.4, 0.0, 1.6)).to_rgba32(), Color8(50, 60, 70, 255).to_rgba32(), "the picker: the texel under it")
	assert_eq(g.location_of(Vector3(-0.5, 0.0, 5.0)), Vector2i(-1, 1), "a position's region")
	assert_eq(g.pixel(Vector3(-3.0, 0.0, 0.0)).to_rgba32(), GrassMaps.NEUTRAL.to_rgba32(), "outside every region: NEUTRAL")
	var game := GrassMaps.new()
	game.bind(t)
	assert_true(game._images.is_empty(), "the game keeps no images (VRAM only)")


## Streaming: a region that streams into a slot has its map read on a worker thread (NEUTRAL until poll() lands it),
## never on the main thread.
func test_streamed_regions_load_off_the_main_thread() -> void:
	_file(Vector2i(3, 3), Color8(11, 22, 33, 255))
	var t := StreamingTerrain.new()
	t.data_directory = dir
	t.data.put(Vector2i(0, 0), 0)
	var g := GrassMaps.new()
	g.keep_images = true
	g.bind(t)
	assert_eq(g.layers().size(), 4, "streaming: one layer a slot")
	t.data.put(Vector2i(3, 3), 2)                              # a region streams into slot 2
	g.refresh()
	assert_true(g.pending() == 1 and g.sync_loads == 0,
		"its map loads on a worker thread (%d pending, %d on the main thread)" % [g.pending(), g.sync_loads])
	var until := Time.get_ticks_msec() + 5000
	while g.pending() > 0 and Time.get_ticks_msec() < until:
		OS.delay_msec(2)
		g.poll()
	assert_eq(g.image(Vector2i(3, 3)).get_pixel(0, 0).to_rgba32(), Color8(11, 22, 33, 255).to_rgba32(),
		"poll() lands it in its layer")
	assert_eq(g.sync_loads, 0, "and nothing was decoded on the main thread")


## Saving: a painted map is dirty until saved; the save writes the .res Image by the region's name; a region
## added in the editor gets its NEUTRAL map saved; one removed has its file deleted on the save, unless it came back first.
func test_saving_and_regions() -> void:
	var t := _terrain()
	t.data_directory = dir.path_join("saving")      # its own folder: test_files_neutral_and_errors left a map for (1, 0)
	t.data.put(Vector2i(0, 0), 0)
	var g := GrassMaps.new()
	g.keep_images = true
	g.editor = true
	g.bind(t)
	assert_true(not g.unsaved(), "a fresh bind has nothing to save")
	g.image(Vector2i(0, 0)).set_pixel(1, 1, Color8(0, 0, 0, 0))
	g.mark_dirty(Vector2i(0, 0))
	assert_true(g.unsaved(), "painted: unsaved")
	var r := g.save_dirty()
	var saved: Image = ResourceLoader.load(g.path_for(Vector2i(0, 0)), "Image", ResourceLoader.CACHE_MODE_IGNORE)
	assert_true(r[Vector2i(0, 0)] == OK and saved != null and saved.get_pixel(1, 1).r8 == 0 and not g.unsaved(),
		"saved by the region's name; clean after")
	t.data.put(Vector2i(1, 0), 1)
	g.refresh()
	assert_true(g.unsaved(), "a region added in the editor: its NEUTRAL map is to be saved")
	g.save_dirty()
	assert_true(FileAccess.file_exists(g.path_for(Vector2i(1, 0))), "and is")
	t.data.region_map[(0 + 16) * 32 + 1 + 16] = 0          # remove (1, 0)
	t.data.locations.erase(Vector2i(1, 0))
	g.refresh()
	assert_true(g.unsaved(), "a removed region: its file is to be deleted")
	t.data.put(Vector2i(1, 0), 1)                            # undo the removal before saving
	g.refresh()
	g.save_dirty()
	assert_true(FileAccess.file_exists(g.path_for(Vector2i(1, 0))), "back before the save: the file stays")
	t.data.region_map[(0 + 16) * 32 + 1 + 16] = 0
	t.data.locations.erase(Vector2i(1, 0))
	g.refresh()
	g.save_dirty()
	assert_true(not FileAccess.file_exists(g.path_for(Vector2i(1, 0))), "removed and saved: the file is gone")


## Every GrassMaps with unsaved changes, whatever scene tab it is in (the save and the quit prompt must not see only the
## edited scene's): unsaved_maps() lists them; unsaved_for(scene) those of one scene, "" all.
func test_the_unsaved_registry() -> void:
	var t := _terrain()
	t.data.put(Vector2i(0, 0), 0)
	var a := GrassMaps.new()
	a.keep_images = true
	a.scene_path = "res://maps/a.scn"
	a.bind(t)
	var b := GrassMaps.new()
	b.keep_images = true
	b.scene_path = "res://maps/b.scn"
	b.bind(t)
	a.mark_dirty(Vector2i(0, 0))
	assert_true(GrassMaps.unsaved_maps().has(a) and not GrassMaps.unsaved_maps().has(b), "only the painted one")
	assert_eq([GrassMaps.unsaved_for("res://maps/a.scn").size(), GrassMaps.unsaved_for("res://maps/b.scn").size(),
		GrassMaps.unsaved_for("").has(a)], [1, 0, true], "by scene; \"\" is every scene (quitting)")
	a.save_dirty()
	assert_true(not GrassMaps.unsaved_maps().has(a), "saved: off the list")


func test_the_water_maps() -> void:
	assert_eq(GrassBlades.water_folder("grass"), "grass_water", "the surface layer's folder, beside the ground maps")
	var b := GrassBlades.new()
	assert_true(b.water_maps != null and b.water_maps != b.grass_maps, "their own maps")
	b.free()
	var w := GrassMaps.new()
	w.folder = GrassBlades.water_folder("grass")
	w.bind(_terrain())
	assert_eq(w.path_for(Vector2i(0, 0)), dir.path_join("grass_water").path_join(
		Terrain3DUtil.location_to_filename(Vector2i(0, 0))), "a region's water map sits in grass_water")
	assert_eq(w.pixel(Vector3(1.0, 0.0, 1.0)), GrassMaps.NEUTRAL, "no file: neutral (the water kind's mix floats)")
