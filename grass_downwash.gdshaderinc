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
// jet then runs out along the deck, strongest just past the footprint rim and
// spent by WASH_REACH footprints, with ripple crests riding outward on the
// vortices it sheds and a fast buffeting on top.

#ifndef GRASS_DOWNWASH_INC
#define GRASS_DOWNWASH_INC

const int MAX_WASH = 2;
uniform vec4 wash[MAX_WASH];
uniform int wash_count = 0;

const float WASH_REACH = 3.2;        // footprints (F ~ 1.15 R): outwash spent at ~3.7 rotor radii
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
	// Wall jet: rises out of the stagnation core, peaks past the rim, dies out.
	jet_k = smoothstep(0.2, 1.0, rho) * (1.0 - smoothstep(1.35, WASH_REACH, rho));
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
	flutter = sin(TIME * (WASH_FLUTTER_W + seed * 9.0) + seed * 37.0);
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
		float ring = 0.5 + 0.5 * sin(d * WASH_RING_K - TIME * WASH_RING_W + seed * 0.8);
		press += dir * (w * core);
		jet += dir * (w * jet_k * (0.55 + 0.45 * ring));
		across += vec2(-dir.y, dir.x) * (w * max(core, jet_k));
	}
}

#endif
