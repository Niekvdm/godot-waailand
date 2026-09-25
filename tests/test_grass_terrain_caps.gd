# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
class_name TestGrassTerrainCaps
extends GrassSuite
## What the running Terrain3D provides to the grass: streaming by its
## property names (IF provided AND enabled), the layer count of the region arrays, a sliding region-map window, against
## fakes shaped like each Terrain3D build.


static func run() -> Dictionary:
	return await GrassSuite.run_suite(TestGrassTerrainCaps.new(), "grass_terrain_caps")


class Upstream extends RefCounted:          # no streaming properties
	var data := Data.new()


class Fork extends RefCounted:              # a streaming Terrain3D build
	var streaming_enabled := true
	var streaming_editor := false
	var streaming_slots := 29
	var data := WindowData.new()


class Data extends RefCounted:
	func get_region_locations() -> Array:
		return [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]


class WindowData extends Data:
	func get_region_map_origin() -> Vector2i:
		return Vector2i(3, -2)


func test_upstream() -> void:
	var t := Upstream.new()
	assert_true(not GrassTerrainCaps.has_streaming(t) and not GrassTerrainCaps.streaming_on(t, false),
		"no streaming properties: no streaming")
	assert_eq(GrassTerrainCaps.layer_count(t, false), 3, "one layer a region")
	assert_eq(GrassTerrainCaps.region_map_origin(t.data), Vector2i.ZERO, "no window: the origin")


func test_the_fork() -> void:
	var t := Fork.new()
	assert_true(GrassTerrainCaps.has_streaming(t) and GrassTerrainCaps.streaming_on(t, false), "the game streams")
	assert_eq(GrassTerrainCaps.layer_count(t, false), 29, "while streaming: its slots")
	assert_true(not GrassTerrainCaps.streaming_on(t, true), "the editor's own switch is off: no streaming there")
	assert_eq(GrassTerrainCaps.layer_count(t, true), 3, "so one layer a region")
	t.streaming_enabled = false
	assert_true(GrassTerrainCaps.has_streaming(t) and not GrassTerrainCaps.streaming_on(t, false),
		"provided but not enabled: not used")
	assert_eq(GrassTerrainCaps.region_map_origin(t.data), Vector2i(3, -2), "the window's origin")
