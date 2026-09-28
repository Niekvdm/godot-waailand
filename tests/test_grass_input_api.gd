# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
class_name TestGrassInputApi
extends GrassSuite
## GrassBlades' input API: the wind's answer to its speed and its eased
## direction; set_date's no-op; the weather, the sun and the sea; events that add up and clear with the frame; the
## frame's two strongest washes, and direct wash uniforms left alone when no one adds a wash; the locator.


static func run() -> Dictionary:
	return await GrassSuite.run_suite(TestGrassInputApi.new(), "grass_input_api")


## A GrassBlades outside the tree with the real blade material, so uniforms can be read back.
func _blades() -> GrassBlades:
	var b := GrassBlades.new()
	b.material = ShaderMaterial.new()
	b.material.shader = load("res://addons/waailand/grass_blade.gdshader")
	return b


func test_the_wind() -> void:
	var lab := GrassWindState.new()
	var p := GrassWindState.for_speed(4.0)
	assert_true(is_equal_approx(p["lean_base"], lab.lean_base) and is_equal_approx(p["lean_gust"], lab.lean_gust)
		and is_equal_approx(p["sway_amp"], lab.sway_amp), "a 4 m/s breeze: the default tuning")
	var calm := GrassWindState.for_speed(0.0)
	var gale := GrassWindState.for_speed(14.0)
	assert_near(float(calm["speed"]), 0.0, 1e-6, "zero wind stays zero (2026-09-27: still air, still grass)")
	assert_near(float(calm["sway_amp"]), 0.0, 1e-6, "zero wind: zero sway")
	assert_near(float(calm["comb"]), 0.0, 1e-6, "zero wind: zero comb")
	assert_true(calm["lean_base"] < p["lean_base"] and p["lean_base"] < gale["lean_base"], "lean grows with speed")
	assert_true(gale["lean_base"] > 0.30 * 1.8 + 1e-6, "a 14 m/s gale leans more than the old 7.2 m/s cap did")
	var storm := GrassWindState.for_speed(40.0)
	assert_near(float(storm["lean_base"]), 0.30 * GrassWindState.GALE_M_S / 4.0, 1e-6,
		"and is capped at GALE_M_S (the shader saturates the lean itself)")
	var b := _blades()
	b.wind.dir = Vector2(1.0, 0.0)
	b.set_wind(Vector2(0.0, 3.0), 3.0)
	assert_near(b.wind.speed, 3.0, 1e-6, "the speed at once")
	assert_eq(b.wind.dir, Vector2(1.0, 0.0), "the direction not yet: it eases")
	b._process(1.0)
	var want := Vector2(1.0, 0.0).slerp(Vector2(0.0, 1.0), 1.0 - exp(-1.0 * b.wind_veer_rate)).normalized()
	assert_true(b.wind.dir.is_equal_approx(want), "a second later, eased at wind_veer_rate (%s)" % b.wind.dir)
	b.wind.dir = Vector2(0.0, 1.0)
	b.set_wind(Vector2.ZERO, 0.0)
	for i in 600:
		b._process(0.1)
	assert_true(b.wind.dir.is_equal_approx(GrassWindState.default_dir()), "no direction (a calm): the default direction")
	b.free()


func test_the_date() -> void:
	var b := _blades()
	b.set_date(100.0)
	b._season_dirty = false
	b.set_date(100.0)
	assert_true(not b._season_dirty, "the same day: nothing re-applied")
	b.set_date(101.0)
	assert_true(b._season_dirty and is_equal_approx(b.get_day_of_year(), 101.0), "a new day: re-applied")
	b.free()


func test_weather_sun_and_sea() -> void:
	var b := _blades()
	b.set_weather(0.5, 2.0)
	assert_eq([b.material.get_shader_parameter("weather_wetness"), b.material.get_shader_parameter("snow_coverage")],
		[0.5, 1.0], "wetness, and snow clamped to 1")
	b.set_sun(Vector3(0.0, -1.0, 0.0))
	assert_eq(b.material.get_shader_parameter("sun_travel_dir"), Vector3(0.0, -1.0, 0.0), "the sun's travel")
	b.set_sea(2.0, {"dir": Vector2(2.0, 0.0), "height": 1.5})
	assert_true(is_equal_approx(b.get_sea_level(), 2.0) and b.get_swell()["dir"] == Vector2(1.0, 0.0)
		and is_equal_approx(b.get_swell()["height"], 1.5), "the level; the swell's direction normalised")
	assert_near(float(b.get_swell()["k"]), float(GrassBlades.DEFAULT_SWELL["k"]), 1e-9, "a missing key: its default")
	b.set_sea(NAN)
	assert_true(is_nan(b.get_sea_level()), "NAN: no sea")
	b.free()


## The inputs are written through the setters and read through getters: the fields behind them are private; a copy
## of the swell changes nothing; an instant wind takes its direction at once.
func test_the_fields_are_private_behind_getters() -> void:
	var b := _blades()
	assert_true(not ("day_of_year" in b) and not ("sea_level" in b) and not ("swell" in b), "no public input fields")
	b.set_date(101.0)
	assert_near(b.get_day_of_year(), 101.0, 1e-9, "the date through its getter")
	b.set_sea(2.0, {"height": 1.5})
	var sw := b.get_swell()
	sw["height"] = 9.0
	assert_true(is_equal_approx(b.get_sea_level(), 2.0) and is_equal_approx(float(b.get_swell()["height"]), 1.5),
		"the sea through its getters; the swell handed out is a copy")
	b.set_wind(Vector2(0.0, 1.0), 5.0, true)
	assert_true(b.wind.dir.is_equal_approx(Vector2(0.0, 1.0)), "an instant wind turns at once")
	b.free()


func test_events_add_up_and_clear_with_the_frame() -> void:
	var b := _blades()
	b.add_crush(Vector3.ZERO, Vector3(1.0, 0.0, 0.0), 0.2)
	b.add_push(Vector3(5.0, 0.0, 5.0), Vector3(5.0, 0.0, 5.0), 0.4, 0.6)
	var st: Array = b.interaction._stamps
	assert_eq([st.size(), st[0][3], st[1][3]], [2, GrassInteractionField.KIND_CRUSH, GrassInteractionField.KIND_PUSH],
		"a crush and a push, in order")
	b.interaction.payload()
	assert_eq(b.interaction._stamps.size(), 0, "the frame's dispatch takes them")
	assert_near(b.interaction_reach(), b.interaction.size_px * b.interaction.texel_m * 0.5, 1e-6, "the stamps' reach")
	b.free()


func test_the_washes() -> void:
	var b := _blades()
	b.add_wash(Vector3(1.0, 0.0, 1.0), 6.0, 0.2)
	b.add_wash(Vector3(2.0, 0.0, 2.0), 6.0, 0.9)
	b.add_wash(Vector3(3.0, 0.0, 3.0), 6.0, 0.5)
	b._process(1.0 / 60.0)
	var w: PackedVector4Array = b.material.get_shader_parameter("wash")
	assert_eq([b.material.get_shader_parameter("wash_count"), w[0], w[1]],
		[2, Vector4(2.0, 2.0, 6.0, 0.9), Vector4(3.0, 3.0, 6.0, 0.5)], "the two strongest, in the order they came")
	b._process(1.0 / 60.0)
	assert_eq(b.material.get_shader_parameter("wash_count"), 0, "a frame without washes clears them")
	b.set_uniform(&"wash_count", 1)
	b._process(1.0 / 60.0)
	assert_eq(b.material.get_shader_parameter("wash_count"), 1, "no one adds washes: a direct setting stays")
	b.free()


func test_no_grass_no_active() -> void:
	assert_true(GrassBlades.active() == null, "no GrassBlades in the tree: none")
