# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name GrassWindState
extends RefCounted
## The CPU half of the wind. The gust field's scroll is INTEGRATED (it advances by speed x dt
## each frame), never computed as rate x TIME, which would re-phase the whole field every time
## the speed changes. It is kept in [0,1) UV because the gust texture repeats, which also keeps
## float precision at any world size.
## The scroll is uniform-driven and therefore invisible to motion vectors; it is SLOW.
## The fast part (sway) runs on TIME inside the shader's vertex().
## EVERY offset the shader samples the texture at is integrated and wrapped on its own
## (OFFSET_RATES): a derived `scroll x 1.9` would jump by 0.9 UV each time `scroll` wrapped, and
## the whole gust and swirl field would snap to a new place every few seconds.

## The shader's gust-texture offsets and their rates relative to the base octave (grass_wind.gdshaderinc).
const OFFSET_RATES := {"wind_scroll": 1.0, "wind_scroll2": 1.9, "wind_scroll_sw": 0.4}
## Below this the wind idles (m/s): a calm still stirs the grass.
const CALM_M_S := 0.9
## Within this angle (rad) of the wind coming straight across a blade, its comb turn tapers to zero
## (grass_wind.gdshaderinc's WIND_COMB_TAPER; comb_turn).
const COMB_TAPER := 0.6
## The tuning set_tuning heads for and ease_tuning eases (for_speed's keys, the speed aside).
const TUNING_KEYS := ["lean_base", "lean_gust", "sway_amp", "comb"]
## How fast the tuning eases toward its target (1/s): ~0.3 s to settle.
const TUNING_RATE := 8.0
## A plant's lean per m/s of air at wind response 1 (rad): grass_wind.gdshaderinc's LEAN_PER_MS (the 4 m/s tuning's
## lean_base, 0.30 rad, read as air speed).
const LEAN_PER_MS := 0.075
## The flattest a flow lays a plant (rad): LEAN_MAX.
const LEAN_MAX := 1.35
## How sharply the lean saturates toward LEAN_MAX (a soft minimum of this power): LEAN_SAT_POW.
const LEAN_SAT_POW := 4.0
## The wind speed (m/s) the tuning stops growing at (for_speed): the shader saturates the lean past it.
const GALE_M_S := 20.0

## Where the wind blows toward (xz, normalised).
var dir := Vector2(0.94, 0.33).normalized()
## The wind speed (m/s).
var speed := 4.0
## The gust texture's scale on the ground (UV per metre: the field repeats every 1 / gust_scale m).
var gust_scale := 0.02
## The gust field's base octave offset (the wind_scroll uniform).
var scroll := Vector2.ZERO
## The second octave's offset (wind_scroll2).
var scroll2 := Vector2.ZERO
## The direction swirl's offset (wind_scroll_sw).
var scroll_sw := Vector2.ZERO
## The steady downwind lean (rad) with no gust.
var lean_base := 0.30
## The extra lean (rad) in a full gust.
var lean_gust := 0.60
## The sway's amplitude (rad).
var sway_amp := 0.10
## The sway's frequency (Hz) for a 0.5 m blade; it scales with 1 / sqrt(height), so taller blades sway slower.
var sway_freq := 1.3
## DEPRECATED (1.6): the shaders no longer read a travelling ripple; the fine gusts (honami_vel) carry the waves.
## The ripple's wavenumber (rad/m), kept for callers of anchor / ripple_term.
var wave_k := 0.35
## How far the local wind direction wanders (rad).
var swirl_rad := 0.9
## How strongly blades turn their face into the local wind, 0..1.
var comb := 0.90
## DEPRECATED (1.6, see wave_k). The ripple's phase was measured from here, which followed the camera (anchor).
var ripple_origin := Vector2.ZERO
## DEPRECATED (1.6, see wave_k). The ripple's phase compensation for the origin's moves (anchor).
var ripple_phase := 0.0
## The air's velocity the fine gusts travel at (m/s, xz): dir x speed, eased with the tuning (ease_tuning), so a
## sudden change of speed or direction does not jump the waves.
var honami_vel := Vector2.ZERO
## TIME's rollover (s): the project's rendering/limits/time/time_rollover_secs, sent as waailand_time_rollover.
var time_rollover := float(ProjectSettings.get_setting("rendering/limits/time/time_rollover_secs", 3600.0))
## Counts calm() calls: the grass's memory of the air (GrassAirField) settles at once when it moves.
var calm_serial := 0
## Where the lean/sway/comb tuning is headed: set_tuning writes it, ease_tuning chases it, calm() stills it too.
var tuning_target := {"lean_base": 0.30, "lean_gust": 0.60, "sway_amp": 0.10, "comb": 0.90}


## How the grass answers a wind of `speed_m_s`: at a 4 m/s breeze exactly the defaults; lean and gust scale with
## the speed up to GALE_M_S (x5: the shader saturates the lean, so a gale lays the grass without folding it past
## flat; this stopped at x1.8, 7.2 m/s, and a gale looked like a stiff breeze), the sway with its square root.
## Zero wind means ZERO movement — still air, still grass (2026-09-27: the old 0.3 floor kept the field dancing in
## still air, which read as a bug). CALM_M_S remains the scroll/idle floor for winds above it.
static func for_speed(speed_m_s: float) -> Dictionary:
	var k := clampf(speed_m_s / 4.0, 0.0, GALE_M_S / 4.0)
	var speed := maxf(speed_m_s, 0.0)
	return {"speed": speed, "lean_base": 0.30 * k, "lean_gust": 0.60 * k,
		"sway_amp": 0.10 * sqrt(k),
		"comb": 0.90 * clampf(k * 1.5, 0.0, 1.0)}


## The direction the wind blows toward when it has none (a calm).
static func default_dir() -> Vector2:
	return Vector2(0.94, 0.33).normalized()


## Moves the gust field on by `dt` seconds of wind.
func advance(dt: float) -> void:
	var step := dir * speed * dt * gust_scale
	scroll = _wrap(scroll + step * OFFSET_RATES["wind_scroll"])
	scroll2 = _wrap(scroll2 + step * OFFSET_RATES["wind_scroll2"])
	scroll_sw = _wrap(scroll_sw + step * OFFSET_RATES["wind_scroll_sw"])


static func _wrap(v: Vector2) -> Vector2:
	return Vector2(fposmod(v.x, 1.0), fposmod(v.y, 1.0))


## DEPRECATED (1.6, see wave_k): the shaders no longer read the ripple. Follow the camera: move the ripple's origin
## to cam_xz and compensate the phase so the field does not slide (the term was -dot(xz - origin, dir) x wave_k +
## ripple_phase).
func anchor(cam_xz: Vector2) -> void:
	var d := cam_xz - ripple_origin
	if d.length_squared() < 1e-10:
		return
	ripple_phase = fposmod(ripple_phase - d.dot(dir) * wave_k, TAU)
	ripple_origin = cam_xz


## DEPRECATED (1.6, see wave_k). The ripple's phase at xz (the old travelling term, without TIME and the blade's own
## offsets).
func ripple_term(xz: Vector2) -> float:
	return -(xz - ripple_origin).dot(dir) * wave_k + ripple_phase


## The natural wind's air speed (m/s) at gust `g` (0..1): the lean the tuning gives, read through LEAN_PER_MS
## (grass_wind.gdshaderinc's wind_air_speed).
func air_speed(g: float) -> float:
	return (lean_base + lean_gust * g * g) / LEAN_PER_MS


## The lean (rad) a flow of `speed` m/s gives a plant of wind response `resp`: linear at a breeze, saturating
## toward LEAN_MAX (grass_wind.gdshaderinc's wind_lean_angle, mirrored for the tests).
static func lean_angle(speed: float, resp: float) -> float:
	var x := maxf(resp, 0.0) * LEAN_PER_MS * maxf(speed, 0.0)
	return x / pow(1.0 + pow(x / LEAN_MAX, LEAN_SAT_POW), 1.0 / LEAN_SAT_POW)


## `hz` moved to the nearest frequency with a whole number of cycles in `rollover` s (grass_time.gdshaderinc).
static func rollover_hz(hz: float, rollover: float) -> float:
	return roundf(hz * rollover) / rollover


## The COMB turn (rad) of a blade whose face is `ang` rad from the local wind (signed, -PI..PI), at comb factor `c`
## (0..1): grass_wind.gdshaderinc's wind_comb_turn, mirrored for the tests. Toward the wind's axis, tapered to zero
## as the wind comes straight across the face, so a veer over the perpendicular never flips a blade.
static func comb_turn(ang: float, c: float) -> float:
	if ang > PI * 0.5:
		ang -= PI
	elif ang < -PI * 0.5:
		ang += PI
	return ang * clampf(c, 0.0, 1.0) * smoothstep(0.0, COMB_TAPER, PI * 0.5 - absf(ang))


## The gust texture's offsets, by uniform name.
func offsets() -> Dictionary:
	return {"wind_scroll": scroll, "wind_scroll2": scroll2, "wind_scroll_sw": scroll_sw}


## Heads the lean/sway/comb tuning for `p` (for_speed's keys); `instant` lands it at once, else ease_tuning eases
## toward it.
func set_tuning(p: Dictionary, instant := false) -> void:
	for k in TUNING_KEYS:
		tuning_target[k] = float(p[k])
		if instant:
			set(k, tuning_target[k])


## One frame of the tuning's low-pass toward its target: a feeder's per-frame flutter (the weather's wind speed)
## becomes a smooth drift instead of stepping every blade to a new equilibrium mid-bend.
func ease_tuning(dt: float) -> void:
	var w := 1.0 - exp(-dt * TUNING_RATE)
	for k in TUNING_KEYS:
		set(k, lerpf(float(get(k)), float(tuning_target[k]), w))
	honami_vel = honami_vel.lerp(dir * speed, w)


## Stills the grass at once and keeps it still until the next set_tuning: no lean, sway or comb (the gust field
## keeps moving). The target stills too, or the easing would bring the wind back within a fraction of a second; and
## the grass's memory of the air settles (calm_serial), or it would rebound from the wind it had.
func calm() -> void:
	for k in TUNING_KEYS:
		set(k, 0.0)
		tuning_target[k] = 0.0
	calm_serial += 1


## Every wind uniform the shaders read, by name.
func uniforms() -> Dictionary:
	return {
		"wind_dir": dir, "wind_scroll": scroll, "wind_scroll2": scroll2, "wind_scroll_sw": scroll_sw,
		"gust_scale": gust_scale,
		"lean_base": lean_base, "lean_gust": lean_gust, "sway_amp": sway_amp,
		"sway_freq": sway_freq, "swirl_rad": swirl_rad, "comb": comb,
		"honami_vel": honami_vel, "waailand_time_rollover": time_rollover,
	}
