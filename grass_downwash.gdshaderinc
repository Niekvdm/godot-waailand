// Copyright (c) 2026 Digitzone
// SPDX-License-Identifier: MIT
// A rotor's downwash as WIND at a point on the ground: the one profile the grass reads (grass_wash.gdshaderinc)
// and that a game can share with its other surfaces so a gust front runs through all of them in step
// (trees, bushes, water: include this file in their shaders).
//
// The CPU pushes one slot per washing rotor near the camera into the material's `wash` / `wash_count`
// (GrassBlades.add_wash does it for the grass): xy = the column's world XZ, z = the footprint radius F at
// the deck (m), w = intensity 0..1 (thrust x height falloff). No slots, no wash.
//
// The shape: under the disc the column presses DOWN and splays outward; the wall
// jet then runs out along the deck, strongest at 1.7-2 rotor radii and spent by
// WASH_REACH footprints, with ripple crests riding outward on the vortices it
// sheds and a fast buffeting on top. Intensity 1 is a 25 m/s wake at the deck
// (RotorWashVeg.WASH_V_REF: the wake speed from the ship's weight and thrust).

#ifndef GRASS_DOWNWASH_INC
#define GRASS_DOWNWASH_INC

#include "res://addons/waailand/grass_time.gdshaderinc"   // rollover_hz: the buffeting survives TIME's rollover

const int MAX_WASH = 2;
uniform vec4 wash[MAX_WASH];
uniform int wash_count = 0;

const float WASH_REACH = 4.0;        // footprints (F ~ 1.15 R): outwash spent at ~4.6 rotor radii
const float WASH_RING_K = 2.1;       // rad/m: ~3 m between ripple crests
const float WASH_RING_W = 13.0;      // rad/s: crests run outward at ~6 m/s
const float WASH_FLUTTER_W = 17.0;   // rad/s: ~2.7 Hz buffeting, jittered per plant

// One slot's geometry at a point: false when out of its reach. `dir` is outward,
// `core` the pressed zone under the disc, `jet_k` the wall jet's envelope.
bool rotor_wash_slot(vec4 w, vec2 world_xz, out vec2 dir, out float d, out float core,
		out float jet_k) {
	vec2 away = world_xz - w.xy;
	d = length(away);
	float rho = d / max(w.z, 0.5);
	dir = d > 1e-3 ? away / d : vec2(1.0, 0.0);
	// Pressed down under the disc, easing into the jet at the rim.
	core = 1.0 - smoothstep(0.55, 1.05, rho);
	// Wall jet: rises out of the stagnation core, peaks at 1.5-1.7 footprints (1.7-2 R; NASA's T613 outwash test
	// measured the peak at 1.7-1.8 R whatever the rotor's height, ~0.75 of it at 1.2 R, still strong at 2.6 R), dies
	// out by WASH_REACH.
	jet_k = smoothstep(0.35, 1.5, rho) * (1.0 - smoothstep(1.7, WASH_REACH, rho));
	return w.w > 0.0 && rho < WASH_REACH;
}

// The wash at world_xz, summed over the rotors washing it. All vectors point where
// the air pushes (world XZ), scaled by intensity:
//   press:  the column pressing down under the disc, splaying outward (0..1)
//   jet:    the wall jet along the deck, crests included (0..1)
//   across: the buffeting, sideways to the flow (0..1; multiply by `flutter`)
// `flutter` is the per-plant buffeting oscillation (-1..1); `seed` a per-plant 0..1.
void rotor_wash_at(vec2 world_xz, float seed, out vec2 press, out vec2 jet, out vec2 across,
		out float flutter) {
	press = vec2(0.0);
	jet = vec2(0.0);
	across = vec2(0.0);
	flutter = sin(TIME * TAU * rollover_hz((WASH_FLUTTER_W + seed * 9.0) / TAU) + seed * 37.0);
	for (int i = 0; i < wash_count; i++) {
		vec2 dir;
		float d;
		float core;
		float jet_k;
		if (!rotor_wash_slot(wash[i], world_xz, dir, d, core, jet_k)) {
			continue;
		}
		float w = wash[i].w;
		// Crests riding outward; phase in METRES so neighbours move together.
		float ring = 0.5 + 0.5 * sin(d * WASH_RING_K - TIME * TAU * rollover_hz(WASH_RING_W / TAU) + seed * 0.8);
		press += dir * (w * core);
		jet += dir * (w * jet_k * (0.55 + 0.45 * ring));
		across += vec2(-dir.y, dir.x) * (w * max(core, jet_k));
	}
}

#endif
