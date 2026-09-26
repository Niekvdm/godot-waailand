#[compute]
#version 450
// Copyright (c) 2026 Digitzone
// SPDX-License-Identifier: MIT

// Per-frame decoration placement, one dispatch per kind in season.
// Candidates are world cells: GRID kinds on their own spacing, CLUMP kinds on the host type's
// Voronoi clump cells (the first plume stands exactly at the clump's site, where the blades
// gather). A candidate lives where the gathered type is the kind's host and its rank passes
// the kind's density x the placement density (and its patch); LOD is a per-instance threshold
// distance with the grow ramp (the blades' no-pop rule), and HIGH or LOW by distance, with a
// morph before the switch. Stateless write-out, like blade_place.glsl.

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

#include "grass_place_common.glsli"

layout(set = 0, binding = 4, std430) restrict buffer Counters { uint n[4]; } C;
layout(set = 0, binding = 5, std430) restrict writeonly buffer DstHi { vec4 d[]; } dst_hi;
layout(set = 0, binding = 6, std430) restrict writeonly buffer DstLo { vec4 d[]; } dst_lo;
layout(set = 0, binding = 7, std430) restrict readonly buffer Kinds { vec4 v[]; } K;

layout(push_constant, std430) uniform Push {
	ivec2 tile0;
	int tiles;
	int kind;
} pc;

// Kind params, mirrored by DecoKinds.params_bytes(): keep the two in step.
#define KV(i)        K.v[pc.kind * 5 + (i)]
#define HOST         int(KV(0).x)
#define MODE         int(KV(0).y)
#define SPACING      KV(0).z
#define DENSITY      KV(0).w
#define RADIUS       KV(1).x
#define D_FULL       KV(1).y
#define K_EDGE       KV(1).z
#define FADE_M       KV(1).w
#define D_SWITCH_K   KV(2).x
#define SCALE_MIN    KV(2).y
#define SCALE_MAX    KV(2).z
#define SEASON_GROW  KV(2).w
#define HEIGHT_REL   KV(3).x
#define PATCH_M      KV(3).y
#define PATCH_SHARE  KV(3).z
#define CAP_HI_K     uint(KV(4).x)
#define CAP_LO_K     uint(KV(4).y)
#define SALT         uint(KV(4).z)

// keep(d): 1 to D_FULL, down to K_EDGE at R - FADE_M, then to 0 at R. Inverted per segment
// (GrassHandoff's hand_keep is the same curve, forwards).
float deco_threshold(float q) {
	if (q >= 1.0) {
		return -1e9;
	}
	float r1 = RADIUS - FADE_M;
	if (q > K_EDGE) {
		return D_FULL + inv_smooth((1.0 - q) / (1.0 - K_EDGE)) * (r1 - D_FULL);
	}
	return r1 + inv_smooth(1.0 - q / K_EDGE) * FADE_M;
}

void write_instance(uint bin, uint idx, vec4 r0, vec4 r1, vec4 r2, vec4 col, vec4 cus) {
	uint o = idx * 5u;
	if (bin == 0u) {
		dst_hi.d[o] = r0; dst_hi.d[o + 1u] = r1; dst_hi.d[o + 2u] = r2;
		dst_hi.d[o + 3u] = col; dst_hi.d[o + 4u] = cus;
	} else {
		dst_lo.d[o] = r0; dst_lo.d[o + 1u] = r1; dst_lo.d[o + 2u] = r2;
		dst_lo.d[o + 3u] = col; dst_lo.d[o + 4u] = cus;
	}
}

shared bool s_skip;
shared uint s_n[2];
shared uint s_base[2];

void main() {
	ivec2 tile = pc.tile0 + ivec2(gl_WorkGroupID.xy);
	uint lid = gl_LocalInvocationIndex;
	float cs = MODE == 1 ? T.v[HOST * 4].w : SPACING;      // candidate cell size

	if (lid == 0u) {
		s_n[0] = 0u; s_n[1] = 0u;
		float tsize = 16.0 * cs;
		vec2 c2 = (vec2(tile) + 0.5) * tsize;
		float th = ground_h(c2);
		vec3 c = vec3(c2.x, isnan(th) ? CAM.y : th, c2.y);
		float tr = tsize * 0.7072 + 3.0;
		bool skip = distance(c, CAM) - tr > RADIUS + 0.5 * GROW_M;
		if (!skip && (FLAGS & FLAG_FRUSTUM) != 0u) {
			skip = !in_frustum(c, tr + SHADOW_MARGIN);
		}
		s_skip = skip;
	}
	barrier();
	if (s_skip) {
		return;
	}

	ivec2 cell = tile * 16 + ivec2(gl_LocalInvocationID.xy);
	int count = MODE == 1 ? int(SPACING) : 1;
	bool surf = TYPE_LAYER(HOST) == 1;       // a floating host: its kinds root at the water's surface
	uint nlive = 0u;
	uint lbin[3];
	uint lslot[3];
	vec4 L0[3];
	vec4 L1[3];
	vec4 L2[3];
	vec4 LC[3];
	vec4 LU[3];
	for (int j = 0; j < 3; j++) {
		if (j >= count) {
			break;
		}
		uint sj = SALT + uint(j) * 4u;
		vec3 h1 = rnd3(cell, sj + 1u);     // jitter.xy, rank
		vec3 h2 = rnd3(cell, sj + 2u);     // yaw, scale, seed
		vec3 h3 = rnd3(cell, sj + 3u);     // type pick
		vec2 pos;
		if (MODE == 1) {
			vec2 site = (vec2(cell) + rnd3(cell, 7u).xy) * cs;   // blade_place's clump site
			pos = j == 0 ? site : site + (h1.xy - 0.5) * cs * 0.3;
		} else {
			pos = (vec2(cell) + h1.xy) * cs;
		}
		vec4 pl;
		int hty;
		vec4 wt = vec4(WATER_NONE);
		bool ok = surf ? surface_at(pos, h3.x, pl, hty, wt) : place_at(pos, h3.x, pl, hty);
		if (!ok || pl.r <= 0.0 || hty != HOST) {
			continue;
		}
		if (!surf) {
			int rty = hty;
			float rdens = pl.r;
			if (!ground_rule(pos, rty, rdens) || rty != HOST) {   // roads, verges, bed paths
				continue;
			}
		}
		if (PATCH_M > 0.0 && rnd3(ivec2(floor(pos / PATCH_M)), SALT + 15u).x >= PATCH_SHARE) {
			continue;
		}
		float dens = DENSITY * pl.r;
		vec3 root = surf ? vec3(pos.x, wt.x + SURFACE_LIFT + bob(pos, wt, h2.z), pos.y)
			: vec3(pos.x, ground_h(pos) - ROOT_SINK, pos.y);
		if (isnan(root.y)) {
			continue;
		}
		float d = distance(root, CAM);
		float g = clamp((deco_threshold(h1.z / max(dens, 1e-6)) - d) / GROW_M + 0.5, 0.0, 1.0);
		if (g <= 0.0) {
			continue;
		}
		float s = mix(SCALE_MIN, SCALE_MAX, h2.y) * sqrt(g) * SEASON_GROW;
		if (HEIGHT_REL > 0.5) {
			// Unit-height mesh (plumes): the host's blade height at its clump, from the same
			// height factors blade_place.glsl gives the tussock this plume rises from.
			s *= T.v[HOST * 4].x * pl.b * 2.0 * mix(0.75, 1.25, rnd3(cell, 8u).x);
		}
		if ((FLAGS & FLAG_FRUSTUM) != 0u && !in_frustum(root + vec3(0.0, s * 0.6, 0.0), s * 0.8 + 0.3 + SHADOW_MARGIN)) {
			continue;
		}
		uint bin = d < D_SWITCH_K ? 0u : 1u;
		if (FORCE_BIN >= 0) {
			bin = uint(FORCE_BIN);
		}
		float morph = FORCE_MORPH >= 0.0 ? FORCE_MORPH : smoothstep(0.7 * D_SWITCH_K, D_SWITCH_K, d);
		vec4 iv = field_at(pos);
		vec2 lay = length(iv.rg) > 1e-3 ? normalize(iv.rg) : vec2(0.0);
		float yaw = FORCE_YAW >= 0.0 ? FORCE_YAW : h2.x * TAU;
		if (surf && FORCE_YAW < 0.0) {
			yaw += 0.15 * sin(TAU * (0.05 * TIME_S + h2.z));    // a floating leaf turns slowly back and forth
		}
		vec3 F = vec3(cos(yaw), 0.0, sin(yaw));
		vec3 S = vec3(F.z, 0.0, -F.x);                    // S x U = F: a proper rotation
		lbin[nlive] = bin;
		lslot[nlive] = atomicAdd(s_n[bin], 1u);
		L0[nlive] = vec4(S.x * s, 0.0, F.x * s, root.x);
		L1[nlive] = vec4(0.0, s, 0.0, root.y);
		L2[nlive] = vec4(S.z * s, 0.0, F.z * s, root.z);
		LC[nlive] = vec4(pack2(h2.z, 0.0), pack2(lay.x * 0.5 + 0.5, lay.y * 0.5 + 0.5),
			pack2(iv.b, iv.a), pack2(morph, 0.0));
		LU[nlive] = vec4(s, g, 0.0, 0.0);
		nlive++;
	}
	barrier();
	if (lid == 0u) {
		s_base[0] = atomicAdd(C.n[0], s_n[0]);
		s_base[1] = atomicAdd(C.n[1], s_n[1]);
	}
	barrier();
	for (uint j = 0u; j < nlive; j++) {
		uint b = lbin[j];
		uint idx = s_base[b] + lslot[j];
		if (idx < (b == 0u ? CAP_HI_K : CAP_LO_K)) {
			write_instance(b, idx, L0[j], L1[j], L2[j], LC[j], LU[j]);
		} else {
			atomicOr(C.n[3], 1u << b);
		}
	}
}
