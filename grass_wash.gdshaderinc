// Copyright (c) 2026 Digitzone
// SPDX-License-Identifier: MIT
// Rotor downwash on grass: the blades and decorations (grass_blade.gdshader, grass_deco.gdshader) include
// it, so they cannot disagree. The wash itself (slots, profile, crests, buffeting) is
// grass_downwash.gdshaderinc, a profile a game's other surfaces can share; this file is only how GRASS
// answers it.
//
// NOT a trample: a trample crushes and darkens like a tyre rut, and a hovering
// helicopter would look like a heavy disc pressed into the lawn. A rotor is WIND: pressed down under the disc, laid outward by the
// jet beyond it, buffeting on top. The blades and flowers take it as AIR
// (grass_wash_air): the wall jet joins the wind's flow (grass_wind.gdshaderinc), so
// it leans each species by its own wind response and combs the faces outward, and
// only the column under the disc presses as a rigid hinge about the root. The card
// grass still takes the old answer, one lean (grass_wash_lean).

#ifndef GRASS_WASH_INC
#define GRASS_WASH_INC

#include "res://addons/waailand/grass_downwash.gdshaderinc"

// Wind-laid grass shows its lighter underside and sheen; trampled grass goes dark.
uniform float wash_sheen : hint_range(0.0, 1.0) = 0.35;

varying float v_wash;    // 0 still, 1 fully laid over by a rotor

const float WASH_JET_LEAN = 1.1;     // rad at the jet peak, full thrust: ~63 degrees
const float WASH_CORE_LEAN = 1.3;    // rad under the disc: pressed nearly flat, the cap

const float WASH_V_FULL = 25.0;      // m/s of wake at intensity 1 (RotorWashVeg.WASH_V_REF)
const float WASH_V_FLAT = 18.0;      // m/s of column that presses a plant under the disc fully flat
const float WASH_BUFFET = 0.30;      // rad: the buffeting in a full wash, across the flow (along it: 0.6 of it)

// A rotor's wash at a plant as AIR, for the blades and the flowers (grass_blade, grass_deco): `jet_u` the wall jet
// (m/s, world XZ, crests included) to add to the wind's flow; `press` the column pressing down under the disc, a
// hinge about the root (rad, splaying outward, flat at WASH_V_FLAT); `strength` the wash here, 0..1 (the buffeting's
// and the sheen's weight); `dir` the way it flows (outward).
void grass_wash_air(vec2 world_xz, float seed, out vec2 jet_u, out vec2 press, out float strength, out vec2 dir) {
	vec2 p;
	vec2 jet;
	vec2 across;
	float wash_flutter;
	rotor_wash_at(world_xz, seed, p, jet, across, wash_flutter);
	jet_u = jet * WASH_V_FULL;
	float pl = length(p);
	press = pl > 1e-4 ? p * (WASH_CORE_LEAN * min(pl * WASH_V_FULL / WASH_V_FLAT, 1.0) / pl) : vec2(0.0);
	strength = clamp(length(across), 0.0, 1.0);
	vec2 flow = jet + p;
	float fl = length(flow);
	dir = fl > 1e-4 ? flow / fl : vec2(1.0, 0.0);
}

// The buffeting at control point `lag` for a full wash (rad): x along the flow, y across it. Two frequencies per
// plant (3-6 Hz and 6.5-10 Hz, fitted to TIME's rollover), so a laid-over field thrashes instead of nodding.
vec2 grass_wash_buffet(float seed, float lag, float time) {
	float f1 = rollover_hz(3.0 + 3.0 * seed);
	float f2 = rollover_hz(6.5 + 3.5 * fract(seed * 7.31));
	float a = sin(time * TAU * f1 + seed * 37.0 - lag * 0.7);
	float b = sin(time * TAU * f2 + seed * 11.0 - lag * 1.1);
	return WASH_BUFFET * vec2(0.6 * (0.7 * a + 0.3 * b), 0.3 * a + 0.7 * b);
}

// The old answer, a lean of one plant (the card grass, src/terrain/grass_field, still reads it): direction = where
// its tip goes (world XZ), length = the angle (rad). `seed` is a per-plant 0..1 random.
vec2 grass_wash_lean(vec2 world_xz, float seed) {
	vec2 press;
	vec2 jet;
	vec2 across;
	// Not `flutter`: a local named like a including shader's uniform (grass_deco's plume flutter)
	// compiles as an assignment to the uniform.
	float wash_flutter;
	rotor_wash_at(world_xz, seed, press, jet, across, wash_flutter);
	vec2 lean = (press * WASH_CORE_LEAN + jet * WASH_JET_LEAN) * (1.0 + 0.12 * wash_flutter)
			+ across * (0.22 * wash_flutter);
	float a = length(lean);
	return a > WASH_CORE_LEAN ? lean * (WASH_CORE_LEAN / a) : lean;
}

// The sheen of wind-laid grass; pass v_wash (the lean the vertex stage stored).
vec3 grass_wash_sheen(vec3 albedo, float laid) {
	return mix(albedo, albedo * 1.18 + vec3(0.015), clamp(laid, 0.0, 1.0) * wash_sheen);
}

#endif
