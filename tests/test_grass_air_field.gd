# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
class_name TestGrassAirField
extends GrassSuite
## The grass's memory of the air (GrassAirField, air_step.glsl): a spring per patch toward the air's equilibrium lean.
## The shaders were stateless: a gust front or a rotor laid the grass and released it in the same frame. A steady air
## must leave no trace (the shaders add only the deviation), a released gust rebounds past its rest once, a rising
## load lags, a patch held flat (matted) creeps back up over seconds, yet a rotor arriving still lays it at once; and the
## result does not depend on the frame rate. The GPU pass mirrors spring_step (its constants pinned here).


static func run() -> Dictionary:
	return await GrassSuite.run_suite(TestGrassAirField.new(), "grass_air_field")


## Runs a patch from `lean` at rest (matting `mat`) toward `eq` for `seconds` at `hz`; returns
## [lean, rate, min x, max x, mat].
func _run(lean: Vector2, eq: Vector2, seconds: float, hz := 60.0, mat := 0.0) -> Array:
	var rate := Vector2.ZERO
	var lo := lean.x
	var hi := lean.x
	var n := int(round(seconds * hz))
	for i in n:
		var r := GrassAirField.spring_step(lean, rate, mat, eq, 1.0 / hz)
		lean = r[0]
		rate = r[1]
		mat = r[2]
		lo = minf(lo, lean.x)
		hi = maxf(hi, lean.x)
	return [lean, rate, lo, hi, mat]


func test_a_steady_air_leaves_no_trace() -> void:
	var r := _run(Vector2.ZERO, Vector2(0.5, 0.2), 6.0)
	assert_near(((r[0] as Vector2) - Vector2(0.5, 0.2)).length(), 0.0, 1e-3, "the equilibrium is reached")
	assert_near((r[1] as Vector2).length(), 0.0, 1e-3, "and held at rest: no deviation for the shaders to add")


func test_a_released_gust_rebounds_once() -> void:
	var r := _run(Vector2(0.5, 0.0), Vector2(0.1, 0.0), 3.0)
	assert_true(float(r[2]) < 0.05, "released from a gust's 0.5 rad to 0.1, it swings past 0.1 toward upright (%.3f)"
		% float(r[2]))
	assert_near((r[0] as Vector2).x, 0.1, 0.01, "and settles")


func test_a_rising_load_lags() -> void:
	var early := _run(Vector2.ZERO, Vector2(0.6, 0.0), 0.1)
	var late := _run(Vector2.ZERO, Vector2(0.6, 0.0), 1.0)
	assert_true((early[0] as Vector2).x < 0.3, "0.1 s into a gust the patch has not arrived (%.3f)" % (early[0] as Vector2).x)
	assert_true(float(late[3]) > 0.55, "within a second it has (%.3f)" % float(late[3]))


func test_a_matted_patch_creeps_back() -> void:
	var held := _run(Vector2(1.25, 0.0), Vector2(1.25, 0.0), 3.0)
	var mat := float(held[4])
	assert_true(mat > 0.95, "held flat 3 s under a hovering rotor, the patch mats (%.3f)" % mat)
	var one := _run(Vector2(1.25, 0.0), Vector2.ZERO, 1.0, 60.0, mat)
	var six := _run(Vector2(1.25, 0.0), Vector2.ZERO, 6.0, 60.0, mat)
	assert_true((one[0] as Vector2).x > 0.6, "a second after the rotor leaves it is still down (%.3f)"
		% (one[0] as Vector2).x)
	assert_true((six[0] as Vector2).x < 0.1, "six seconds on it is up (%.3f)" % (six[0] as Vector2).x)
	assert_true(float(six[2]) > -0.1, "creeping, not bouncing (%.3f)" % float(six[2]))
	var quick := _run(Vector2(1.25, 0.0), Vector2(1.25, 0.0), 0.3)
	var back := _run(Vector2(1.25, 0.0), Vector2.ZERO, 1.0, 60.0, float(quick[4]))
	assert_true(absf((back[0] as Vector2).x) < 0.3, "a quick pass (0.3 s) barely mats it: nearly up within a second (%.3f)"
		% (back[0] as Vector2).x)


func test_a_rotor_still_lays_a_patch_at_once() -> void:
	var r := _run(Vector2.ZERO, Vector2(1.25, 0.0), 0.6)
	assert_true(float(r[3]) > 1.0, "the softening is the RELEASE's: loading lays the patch within 0.6 s (%.3f)"
		% float(r[3]))
	assert_true(float(r[3]) <= GrassAirField.CAP + 1e-4, "and never folds it past the ground (%.3f)" % float(r[3]))


func test_the_frame_rate_does_not_matter() -> void:
	var a := _run(Vector2(1.25, 0.0), Vector2.ZERO, 1.5, 30.0, 1.0)
	var b := _run(Vector2(1.25, 0.0), Vector2.ZERO, 1.5, 144.0, 1.0)
	var c := _run(Vector2(0.5, 0.0), Vector2(0.1, 0.0), 1.0, 30.0)
	var d := _run(Vector2(0.5, 0.0), Vector2(0.1, 0.0), 1.0, 144.0)
	assert_near((a[0] as Vector2).x, (b[0] as Vector2).x, 0.02, "a matted patch's creep at 30 and 144 Hz")
	assert_near((c[0] as Vector2).x, (d[0] as Vector2).x, 0.02, "a gust's rebound at 30 and 144 Hz")


func test_the_gpu_pass_is_the_mirror() -> void:
	var glsl := FileAccess.get_file_as_string("res://addons/waailand/air_step.glsl")
	var inc := FileAccess.get_file_as_string("res://addons/waailand/grass_wind.gdshaderinc")
	var wash := FileAccess.get_file_as_string("res://addons/waailand/grass_wash.gdshaderinc") \
		+ FileAccess.get_file_as_string("res://addons/waailand/grass_downwash.gdshaderinc")
	var pins := [["FREQ_HZ", GrassAirField.FREQ_HZ], ["ZETA", GrassAirField.ZETA],
		["LAID_STIFFNESS", GrassAirField.LAID_STIFFNESS], ["LAID_ZETA", GrassAirField.LAID_ZETA],
		["LAID_FROM", GrassAirField.LAID_FROM], ["LAID_FULL", GrassAirField.LAID_FULL],
		["MAT_RISE_S", GrassAirField.MAT_RISE_S], ["MAT_FALL_S", GrassAirField.MAT_FALL_S], ["CAP", GrassAirField.CAP],
		["LEAN_PER_MS", GrassWindState.LEAN_PER_MS], ["LEAN_MAX", GrassWindState.LEAN_MAX],
		["LEAN_SAT_POW", GrassWindState.LEAN_SAT_POW]]
	for p in pins:
		assert_eq(_const(glsl, p[0]), float(p[1]), "air_step.glsl's %s is the mirror's" % p[0])
	for k in ["LEAN_PER_MS", "LEAN_MAX", "LEAN_SAT_POW"]:
		assert_eq(_const(glsl, k), _const(inc, k), "air_step.glsl's %s is grass_wind.gdshaderinc's" % k)
	for k in ["WASH_REACH", "WASH_V_FULL", "WASH_V_FLAT", "WASH_CORE_LEAN"]:
		assert_eq(_const(glsl, k), _const(wash, k), "air_step.glsl's %s is the wash's" % k)


static func _const(src: String, name: String) -> float:
	var m := RegEx.create_from_string("const float %s = ([0-9.]+)" % name).search(src)
	return float(m.get_string(1)) if m != null else NAN
