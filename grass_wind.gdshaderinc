// Copyright (c) 2026 Digitzone
// SPDX-License-Identifier: MIT
// The wind field: blades, decorations and the terrain's far field. Rotor downwash is
// grass_wash.gdshaderinc (with grass_downwash.gdshaderinc), not part of this file.
//
// MOTION VECTORS: Godot runs vertex() twice (TIME and TIME - delta) but does NOT
// double-buffer uniforms or textures. So:
//   - gust scroll, lean: uniform-driven, SLOW -> small motion-vector error, accepted;
//   - sway, travelling ripple: driven by `time`, which the caller MUST
//     pass as TIME from inside vertex() (the engine flags a material animated only when
//     TIME appears textually in vertex()) -> exact motion vectors.

#include "res://addons/waailand/grass_time.gdshaderinc"   // rollover_hz: frequencies that survive TIME's rollover

uniform sampler2D gust_tex : filter_linear_mipmap, repeat_enable;   // mipmapped: the far field samples it minified
uniform vec2 wind_dir = vec2(0.94, 0.33);
uniform vec2 wind_scroll = vec2(0.0);      // each offset integrated and wrapped on its own (GrassWindState):
uniform vec2 wind_scroll2 = vec2(0.0);     // a derived `wind_scroll x 1.9` jumped at every wrap
uniform vec2 wind_scroll_sw = vec2(0.0);
uniform float gust_scale = 0.02;
uniform float lean_base = 0.30;
uniform float lean_gust = 0.60;
uniform float sway_amp = 0.10;
uniform float sway_freq = 1.3;
uniform float wave_k = 0.35;
uniform float swirl_rad = 0.9;       // how far the local wind direction wanders (rad)
uniform float comb = 0.90;           // how strongly blades turn their face into the local wind
uniform float debug_uniform_phase = -1.0;   // >= 0: sway phase from this UNIFORM (a negative control for motion-vector tests)
uniform vec2 ripple_origin = vec2(0.0);     // the ripple's phase is measured from here (the camera; GrassWindState.anchor)
uniform float ripple_phase = 0.0;           // its compensation for the origin's moves

// THE AIR. The natural wind and a rotor's wall jet are one flow over the ground (m/s, world XZ), and a plant
// answers the flow's speed with a lean that SATURATES: linear at a breeze (the tuning's lean_base + lean_gust g^2,
// read as air speed through LEAN_PER_MS, leans exactly as before), toward LEAN_MAX in a gale or a wall jet, never
// past it. (The linear lean put 1.62 rad on a full gust at the old 7.2 m/s cap; the wash was a separate hinge that
// ignored the species and the comb.) GrassWindState mirrors these for the tests.
const float LEAN_PER_MS = 0.075;   // rad per m/s at wind response 1: the 4 m/s tuning's 0.30 rad
const float LEAN_MAX = 1.35;       // rad (77 degrees): the flattest a flow lays a plant
const float LEAN_SAT_POW = 4.0;    // how sharply the lean saturates (a soft minimum of this power)
const float WIND_CROSS = 0.35;     // the sway across the wind, of the sway along it

// Gust intensity 0..1: the magnitude field scrolled downwind (wind x scrolled noise).
float wind_gust(vec2 xz) {
	float a = texture(gust_tex, xz * gust_scale - wind_scroll).r;
	float b = texture(gust_tex, xz * gust_scale * 2.7 - wind_scroll2 + vec2(0.37, 0.11)).r;
	return clamp(a * 0.7 + b * 0.3, 0.0, 1.0);
}

// The LOCAL wind direction: the mean direction swirled by a coarse, scrolled noise sample
// (that swirl is the "combed" field). Slow and uniform-driven, so its motion-vector error is
// small (see the header).
vec2 wind_dir_at(vec2 xz) {
	float n = texture(gust_tex, xz * gust_scale * 0.23 - wind_scroll_sw + vec2(0.61, 0.29)).r;
	float a = (n - 0.5) * 2.0 * swirl_rad;
	float c = cos(a);
	float s = sin(a);
	return vec2(wind_dir.x * c - wind_dir.y * s, wind_dir.x * s + wind_dir.y * c);
}

// The natural wind's air speed (m/s) at gust g: the lean the tuning gives, read through LEAN_PER_MS.
float wind_air_speed(float g) {
	return (lean_base + lean_gust * g * g) / LEAN_PER_MS;
}

// How far a plant turns its face into the natural wind at gust g, 0..1: comb x (0.35 + g)^2.
float wind_comb_at(float g) {
	return clamp(comb * (0.35 + g) * (0.35 + g), 0.0, 1.0);
}

// The lean (rad) a flow of `speed` m/s gives a plant of wind response `resp`.
float wind_lean_angle(float speed, float resp) {
	float x = max(resp, 0.0) * LEAN_PER_MS * max(speed, 0.0);
	return x / pow(1.0 + pow(x / LEAN_MAX, LEAN_SAT_POW), 1.0 / LEAN_SAT_POW);
}

// The flow `u`'s lean as a vector: toward where it pushes, its length the angle. Continuous through still air
// (angle / speed tends to resp x LEAN_PER_MS), where the flow's direction is undefined.
vec2 wind_lean_vec(vec2 u, float resp) {
	float s = length(u);
	return s > 1e-4 ? u * (wind_lean_angle(s, resp) / s) : u * (max(resp, 0.0) * LEAN_PER_MS);
}

// Steady downwind lean: xy = local direction, z = angle (rad). Grass is pushed over and
// springs back; it does not bend into the wind.
vec3 wind_lean(vec2 xz) {
	float g = wind_gust(xz);
	return vec3(wind_dir_at(xz), lean_base + lean_gust * g * g);
}

// How far a blade turns its face into the local wind, 0..1: comb x (0.35 + gust)^2.
float wind_comb(vec2 xz) {
	float g = wind_gust(xz);
	return clamp(comb * (0.35 + g) * (0.35 + g), 0.0, 1.0);
}

// The COMB turn (rad) of a blade whose face is `ang` rad from the local wind (signed, (-pi, pi]) at comb factor `c`
// (0..1): toward the wind's AXIS (a face and its reverse lie along one line) by a fraction c of the folded angle,
// TAPERED to zero as the wind comes straight across the face. Folded alone, that blade had two equally near targets
// and flipped by c x 180 degrees in one frame whenever the swirl veered the wind over its perpendicular (2026-09-28:
// "blades snap to another rotation, then the wind continues from there"). A shader keeps no state to pick a side, so
// the blade across the wind stays across (an unstable balance) and turns smoothly as the wind veers off it; within
// WIND_COMB_TAPER rad of the perpendicular it turns part of the way. GrassWindState.comb_turn mirrors this.
const float WIND_COMB_TAPER = 0.6;
float wind_comb_turn(float ang, float c) {
	if (ang > 1.5707963) {
		ang -= 3.14159265;
	} else if (ang < -1.5707963) {
		ang += 3.14159265;
	}
	return ang * clamp(c, 0.0, 1.0) * smoothstep(0.0, WIND_COMB_TAPER, 1.5707963 - abs(ang));
}

// The sway at control point `lag` (1..3) at gust g, rad: x along the local wind, y across it (WIND_CROSS of it, at
// 1.37x the frequency, so a tip traces a loop rather than a line). See wind_sway below for the phase.
vec2 wind_sway2(vec2 xz, float g, float height, float seed, float lag, float time) {
	float f = rollover_hz(sway_freq * sqrt(0.5 / max(height, 0.05)));
	float fc = rollover_hz(f * 1.37);
	float tt = debug_uniform_phase >= 0.0 ? debug_uniform_phase : time;
	float ph = tt * TAU * f - dot(xz - ripple_origin, wind_dir) * wave_k + ripple_phase + seed * 2.2 - lag * 0.45;
	float pc = tt * TAU * fc + seed * 5.1 - lag * 0.6;
	float a = sway_amp * (0.35 + g);
	return vec2(a * sin(ph), a * WIND_CROSS * sin(pc));
}

// Oscillation angle (rad) for control point `lag` (1..3). Frequency falls with height;
// phase from the blade seed AND the point's position along the blade (so it sways rather
// than tilting rigidly) plus a ripple travelling downwind at sway_freq*TAU/wave_k m/s.
// `height` must NOT change under a blade (the TYPE's height, not the live one): the phase is
// TIME x f, so a frequency that moves (the grow ramp, snow burying the blade) would spin the sway
// at any large TIME. The ripple is measured from ripple_origin, not the world origin.
// Both of wind_sway2's frequencies fit TIME's rollover (rollover_hz).
float wind_sway(vec2 xz, float height, float seed, float lag, float time) {
	return wind_sway2(xz, wind_gust(xz), height, seed, lag, time).x;
}

