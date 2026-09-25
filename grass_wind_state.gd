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
## The travelling ripple's wavenumber (rad/m): it runs downwind at sway_freq x TAU / wave_k m/s.
var wave_k := 0.35
## How far the local wind direction wanders (rad).
var swirl_rad := 0.9
## How strongly blades turn their face into the local wind, 0..1.
var comb := 0.90
## The sway ripple's phase is measured from here, which follows the camera (anchor): measured from the
## world origin, kilometres of distance x a veering wind direction would make the sway race and reverse.
## ripple_phase compensates every move of the origin.
var ripple_origin := Vector2.ZERO
## The ripple's phase compensation for the origin's moves (anchor).
var ripple_phase := 0.0


## How the grass answers a wind of `speed_m_s`: at a 4 m/s breeze exactly the defaults; lean and gust scale with
## the speed (x0.3 to x1.8), the sway with its square root; below CALM_M_S it idles.
static func for_speed(speed_m_s: float) -> Dictionary:
	var speed := maxf(speed_m_s, CALM_M_S)
	var k := clampf(speed / 4.0, 0.3, 1.8)
	return {"speed": speed, "lean_base": 0.30 * k, "lean_gust": 0.60 * k,
		"sway_amp": 0.10 * clampf(sqrt(speed / 4.0), 0.5, 1.4)}


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


## Follow the camera: move the ripple's origin to cam_xz and compensate the phase so the field does not
## slide. The shader's term is -dot(xz - origin, dir) x wave_k + ripple_phase.
func anchor(cam_xz: Vector2) -> void:
	var d := cam_xz - ripple_origin
	if d.length_squared() < 1e-10:
		return
	ripple_phase = fposmod(ripple_phase - d.dot(dir) * wave_k, TAU)
	ripple_origin = cam_xz


## The ripple's phase at xz (the shader's travelling term, without TIME and the blade's own offsets).
func ripple_term(xz: Vector2) -> float:
	return -(xz - ripple_origin).dot(dir) * wave_k + ripple_phase


## The gust texture's offsets, by uniform name.
func offsets() -> Dictionary:
	return {"wind_scroll": scroll, "wind_scroll2": scroll2, "wind_scroll_sw": scroll_sw}


## Stills the grass at once: no lean, sway or comb (the gust field keeps moving).
func calm() -> void:
	lean_base = 0.0
	lean_gust = 0.0
	sway_amp = 0.0
	comb = 0.0


## Every wind uniform the shaders read, by name.
func uniforms() -> Dictionary:
	return {
		"wind_dir": dir, "wind_scroll": scroll, "wind_scroll2": scroll2, "wind_scroll_sw": scroll_sw,
		"gust_scale": gust_scale,
		"lean_base": lean_base, "lean_gust": lean_gust, "sway_amp": sway_amp,
		"sway_freq": sway_freq, "wave_k": wave_k, "swirl_rad": swirl_rad, "comb": comb,
		"ripple_origin": ripple_origin, "ripple_phase": ripple_phase,
	}
