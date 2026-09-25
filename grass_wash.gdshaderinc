// Copyright (c) 2026 Digitzone
// SPDX-License-Identifier: MIT
// Rotor downwash on grass: the blades and decorations (grass_blade.gdshader, grass_deco.gdshader) include
// it, so they cannot disagree. The wash itself (slots, profile, crests, buffeting) is
// grass_downwash.gdshaderinc, a profile a game's other surfaces can share; this file is only how GRASS
// answers it.
//
// NOT a trample: a trample crushes and darkens like a tyre rut, and a hovering
// helicopter would look like a heavy disc pressed into the lawn. A rotor is WIND: pressed down under the disc, laid outward by the
// jet beyond it, buffeting on top. The result is a LEAN ANGLE about the blade's
// root, which each shader applies as a rigid hinge (sin / cos) so a laid-over
// blade keeps its length.

#ifndef GRASS_WASH_INC
#define GRASS_WASH_INC

#include "res://addons/waailand/grass_downwash.gdshaderinc"

// Wind-laid grass shows its lighter underside and sheen; trampled grass goes dark.
uniform float wash_sheen : hint_range(0.0, 1.0) = 0.35;

varying float v_wash;    // 0 still, 1 fully laid over by a rotor

const float WASH_JET_LEAN = 1.1;     // rad at the jet peak, full thrust: ~63 degrees
const float WASH_CORE_LEAN = 1.3;    // rad under the disc: pressed nearly flat, the cap

// Lean of one plant: direction = where its tip goes (world XZ), length = the
// angle (rad). `seed` is a per-plant 0..1 random.
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
