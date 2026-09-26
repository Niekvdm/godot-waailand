// Copyright (c) 2026 Digitzone
// SPDX-License-Identifier: MIT
// The colour handoff (a field of red flowers stays red far away): the flower colour a kind's
// decorations no longer draw at distance d is carried by its host type's blades, and past the
// blades by the terrain. REQUIRES grass_palette.gdshaderinc. Set by
// DecorationStreams.apply_handoff whenever the date changes.

uniform vec4 hand_hosts[64];    // type t (GrassTypes.SLOTS 32), slots 2t and 2t+1: (kind, coverage x season grow, d_full, radius); coverage 0 = none
uniform vec4 hand_curve[32];    // kind (DecoKinds.MAX_KINDS 32): (k_edge, fade m, palette cell x, palette cell z)
uniform float hand_n[32];       // kind: palette entries
uniform float hand_salt[32];    // kind: its palette salt (DecoKinds.palette_salt), as its decorations use
uniform vec3 hand_pal[192];     // kind k: entries 6k..6k+5, today's flower colour (linear)
uniform float hand_gain = 1.0;      // blade calibration (matched to the decorations' own colour)
uniform float hand_far_gain = 1.5;  // terrain calibration: the far gain that matches the blades' handoff
                                    // (the match is not linear in the gain)

// The share of a kind's full coverage its decorations still draw at distance d: the kernel's
// keep curve, forwards: 1 to d_full, down to k_edge at R - fade, then to 0 at R.
float hand_keep(vec4 host, vec4 curve, float d) {
	float r1 = host.w - curve.y;
	float k = mix(1.0, curve.x, smoothstep(host.z, r1, d));
	return k * (1.0 - smoothstep(r1, host.w, d));
}

// The flower colour missing at distance d over type ty at xz: rgb, and how much (0..1).
// `pcol`: the blade's painted flower color (palette entry + 1; 0: the field's own stripes, as the flower picks).
vec4 hand_tint(int ty, vec2 xz, float d, float pcol) {
	vec3 rgb = vec3(0.0);
	float a = 0.0;
	for (int s = 0; s < 2; s++) {
		vec4 host = hand_hosts[ty * 2 + s];
		if (host.y <= 0.0) {
			continue;
		}
		int k = int(host.x);
		vec4 curve = hand_curve[k];
		float miss = host.y * (1.0 - hand_keep(host, curve, d));
		float pi = pcol > 0.5 ? mod(pcol - 1.0, hand_n[k]) : palette_index(xz, curve.zw, hand_n[k], hand_salt[k]);
		rgb += hand_pal[k * 6 + int(pi)] * miss;
		a += miss;
	}
	return a > 1e-5 ? vec4(rgb / a, min(a, 1.0)) : vec4(0.0);
}
