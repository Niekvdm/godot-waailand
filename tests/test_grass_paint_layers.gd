# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
class_name TestGrassPaintLayers
extends GrassSuite
## The Grass workspace's layer switch: the library lists the selected layer's species only and the bar hears of a
## switch, each layer keeps its own selection, strokes use the layer's maps, the Water layer's stroke lands on the
## surface, and the brush paints only where its mask allows (the Water layer: over water).


## The blades as the provider sees them: two sets of maps and a water surface at y 1 over |x| < 10.
class _Blades:
	extends Node
	var grass_maps := GrassMaps.new()
	var water_maps := GrassMaps.new()
	var terrain: Object = null

	func water_surface(p: Vector3) -> float:
		return 1.0 if absf(p.x) < 10.0 else NAN


static func run() -> Dictionary:
	var keep := TestGrassWaterGrowth.use_water_fixture()
	var r := await GrassSuite.run_suite(TestGrassPaintLayers.new(), "grass_paint_layers")
	GrassBladesConfig.use(keep)
	return r


func _provider() -> GrassPaintProvider:
	return GrassPaintProvider.new(GrassTypes.new())


func _names(p: GrassPaintProvider) -> PackedStringArray:
	var out := PackedStringArray()
	for it in p.library()["items"]:
		out.append(String(it["name"]).to_lower())
	return out


func test_the_library_follows_the_layer() -> void:
	var p := _provider()
	assert_true(not _names(p).has("t lily") and _names(p).has("pasture"), "Ground: ground species only")
	var fired := [0]
	p.library_changed.connect(func() -> void: fired[0] += 1)
	p.set_layer(GrassPaintProvider.Layer.WATER)
	assert_eq(fired[0], 1, "the bar is told")
	assert_true(_names(p).has("t lily") and _names(p).has("t duck") and not _names(p).has("pasture"),
		"Water: surface species only")
	assert_eq(p.library()["key"], "grass.species.water", "Water keeps its own favourites and recents")
	p.set_layer(GrassPaintProvider.Layer.WATER)
	assert_eq(fired[0], 1, "the same layer again: no news")


func test_each_layer_keeps_its_selection() -> void:
	var p := _provider()
	var t := p.types
	p.library_select(t.names().find("verge"))
	p.set_layer(GrassPaintProvider.Layer.WATER)
	assert_eq(t.row(p.library_selected()).get("layer", 0), GrassTypes.LAYER_SURFACE, "Water starts on a surface species")
	p.library_select(t.names().find("t_duck"))
	p.set_layer(GrassPaintProvider.Layer.GROUND)
	assert_eq(p.library_selected(), t.names().find("verge"), "Ground's pick comes back")
	p.set_layer(GrassPaintProvider.Layer.WATER)
	assert_eq(p.library_selected(), t.names().find("t_duck"), "and Water's")
	assert_eq(p.capture("grass.species").get("layer"), GrassPaintProvider.Layer.WATER, "a preset keeps the layer")
	var q := _provider()
	q.apply("grass.species", p.capture("grass.species"))
	assert_eq(q.layer, GrassPaintProvider.Layer.WATER, "and gives it back")


func test_maps_and_the_water_point() -> void:
	var p := _provider()
	var b := _Blades.new()
	p.blades_of = func() -> Object: return b
	assert_true(p.maps_of(b) == b.grass_maps, "Ground paints the ground maps")
	p.set_layer(GrassPaintProvider.Layer.WATER)
	assert_true(p.maps_of(b) == b.water_maps, "Water paints the water maps")
	var at := p.project_hit(Vector3(0, 11, 0), Vector3(0, -1, 0), Vector3(0, -3, 0))
	assert_eq(at, Vector3(0, 1, 0), "the stroke lands on the surface, not on the bed")
	var slant := p.project_hit(Vector3(-4, 11, 0), Vector3(0.6, -0.8, 0), Vector3(6.5, -3, 0))
	assert_near(slant.y, 1.0, 1e-5, "along a slanted ray: on the surface")
	assert_near(slant.x, 3.5, 1e-4, "where the ray meets it")
	var dry := p.project_hit(Vector3(50, 11, 0), Vector3(0, -1, 0), Vector3(50, 0, 0))
	assert_eq(dry, Vector3(50, 0, 0), "no water there: the hit")
	assert_eq(p.cursor_note(), "no water here", "the Water layer off water: the brush chip's note")
	p.project_hit(Vector3(0, 11, 0), Vector3(0, -1, 0), Vector3(0, -3, 0))
	assert_eq(p.cursor_note(), "", "over water: none")
	p.set_layer(GrassPaintProvider.Layer.GROUND)
	assert_eq(p.project_hit(Vector3(0, 11, 0), Vector3(0, -1, 0), Vector3(0, -3, 0)), Vector3(0, -3, 0),
		"Ground: the hit")
	b.free()


func test_the_brush_mask() -> void:
	var t := TestGrassBrush.FakeTerrain.new()
	var maps := GrassMaps.new()
	maps.keep_images = true
	maps.bind(t)
	var br := GrassBrush.new()
	br.maps = maps
	br.data = t.data
	br.texel_ok = func(pos: Vector3) -> bool: return pos.x < 20.0
	br.begin()
	br.dab(Vector3(20.0, 0.0, 20.0), TestGrassBrush._brush(8.0, 1.0),
		{"channel": 1, "mode": GrassBrush.Mode.SET_HARD, "value": 7})
	var inside := 0
	var outside := 0
	for x in range(14, 27):
		for z in range(14, 27):
			if roundi(maps.pixel(Vector3(x + 0.5, 0.0, z + 0.5)).g * 255.0) == 7:
				if x + 0.5 < 20.0:
					inside += 1
				else:
					outside += 1
	assert_eq(outside, 0, "nothing painted where the mask says no")
	assert_true(inside > 10, "painted where it allows (%d texels)" % inside)
	br.texel_ok = func(_pos: Vector3) -> bool: return false
	br.begin()
	br.dab(Vector3(0.0, 0.0, 0.0), TestGrassBrush._brush(8.0, 1.0),
		{"channel": 1, "mode": GrassBrush.Mode.SET_HARD, "value": 9, "fill_region": true})
	assert_eq(roundi(maps.pixel(Vector3(0.5, 0.0, 0.5)).g * 255.0), 0, "a region fill keeps the mask too")
