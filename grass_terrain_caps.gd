# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name GrassTerrainCaps
extends RefCounted
## What the running Terrain3D provides to the grass. Streaming is used IF the Terrain3D build provides it AND it is
## enabled (STREAMING_PROPS names the switches of the builds that have it); a sliding region-map window likewise.
## Properties are read by NAME (Object.get: null when absent), so this compiles and runs on any Terrain3D. The only
## file of the addon that names an API upstream Terrain3D does not have.

## [the switch, the editor's own switch], per Terrain3D that has streaming.
const STREAMING_PROPS := [["streaming_enabled", "streaming_editor"]]
## The slot count of a streaming Terrain3D's region arrays.
const SLOTS_PROPS := ["streaming_slots"]


static func has_streaming(p_terrain: Object) -> bool:
	for pair in STREAMING_PROPS:
		if p_terrain != null and p_terrain.get(pair[0]) != null:
			return true
	return false


## Streaming is provided AND enabled (in the editor, its own switch too).
static func streaming_on(p_terrain: Object, p_editor: bool) -> bool:
	if p_terrain == null:
		return false
	for pair in STREAMING_PROPS:
		if p_terrain.get(pair[0]) == true:
			var ed = p_terrain.get(pair[1])
			return not p_editor or ed == null or ed == true
	return false


## The layer count of the terrain's region arrays: its slots while streaming, else one a region.
static func layer_count(p_terrain: Object, p_editor: bool) -> int:
	if streaming_on(p_terrain, p_editor):
		for p in SLOTS_PROPS:
			if p_terrain.get(p) != null:
				return int(p_terrain.get(p))
	var data: Object = p_terrain.get("data") if p_terrain != null else null
	return (data.call("get_region_locations") as Array).size() if data != null else 0


## The region map's window origin: a streaming build may slide it; upstream Terrain3D's is fixed at (0, 0).
static func region_map_origin(p_data: Object) -> Vector2i:
	if p_data != null and p_data.has_method("get_region_map_origin"):
		return p_data.call("get_region_map_origin")
	return Vector2i.ZERO
