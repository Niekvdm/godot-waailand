#[compute]
#version 450
// Copyright (c) 2026 Digitzone
// SPDX-License-Identifier: MIT

// Per-frame blade placement. One workgroup is one tile of 16x16 grid cells. Every lane is one
// candidate blade, and a blade IS its world grid cell, so placement is a pure function of world
// position: moving the camera never reshuffles a blade. Everything that depends on the camera
// (existence through the LOD and edge thresholds, size, morph) is decided HERE, once, and carried
// in the instance, so the vertex shader and every shadow pass read it and cannot disagree.
//
// Write-out is stateless: atomic append into the bins (grouped through shared memory, one
// global atomic per workgroup per bin), then blade_finalize.glsl copies the counts into
// the indirect draw commands. No scan/compact, no persistent blade buffer.

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

#include "grass_place_common.glsli"

layout(set = 0, binding = 4, std430) restrict buffer Counters { uint n[4]; } C;
layout(set = 0, binding = 5, std430) restrict writeonly buffer DstHi { vec4 d[]; } dst_hi;
layout(set = 0, binding = 6, std430) restrict writeonly buffer DstLo { vec4 d[]; } dst_lo;
layout(set = 0, binding = 7, std430) restrict writeonly buffer DstSh { vec4 d[]; } dst_sh;

layout(push_constant, std430) uniform Push {
	ivec2 tile0;     // world tile index of the dispatch's first workgroup
	int tiles;       // workgroups per side
	int layer;       // 0 the ground layer; 1 the surface layer (a second dispatch over the same tiles)
} pc;

// The camera distance at which a blade of rank/density q crosses the threshold
// t(d) = keep(d) * edge(d). keep falls 1 -> K_LO over [D_MORPH, D_SWITCH], then
// K_LO -> K_FAR over [DF0, DF1] (the far carpet);
// the edge fade closes it at R. Closed form per segment because the ramps do not overlap
// (GrassBlades clamps them and disables the far ramp when it does not fit). q >= 1 never
// exists; K_FAR == K_LO collapses the far segment.
float threshold_distance(float q) {
	if (q >= 1.0) {
		return -1e9;
	}
	if (q > K_LO) {
		return D_MORPH + inv_smooth((1.0 - q) / (1.0 - K_LO)) * (D_SWITCH - D_MORPH);
	}
	if (q > K_FAR) {
		return DF0 + inv_smooth((K_LO - q) / (K_LO - K_FAR)) * (DF1 - DF0);
	}
	return (R_MAX - EDGE_FADE) + inv_smooth(1.0 - q / K_FAR) * EDGE_FADE;
}

void write_instance(uint bin, uint idx, vec4 r0, vec4 r1, vec4 r2, vec4 col, vec4 cus) {
	uint o = idx * 5u;
	if (bin == 0u) {
		dst_hi.d[o] = r0; dst_hi.d[o + 1u] = r1; dst_hi.d[o + 2u] = r2;
		dst_hi.d[o + 3u] = col; dst_hi.d[o + 4u] = cus;
	} else if (bin == 1u) {
		dst_lo.d[o] = r0; dst_lo.d[o + 1u] = r1; dst_lo.d[o + 2u] = r2;
		dst_lo.d[o + 3u] = col; dst_lo.d[o + 4u] = cus;
	} else {
		dst_sh.d[o] = r0; dst_sh.d[o + 1u] = r1; dst_sh.d[o + 2u] = r2;
		dst_sh.d[o + 3u] = col; dst_sh.d[o + 4u] = cus;
	}
}

shared bool s_skip;
shared uint s_n[3];
shared uint s_base[3];

void main() {
	ivec2 tile = pc.tile0 + ivec2(gl_WorkGroupID.xy);
	uint lid = gl_LocalInvocationIndex;

	// ── Tile early-out: one lane tests, the group follows ──
	if (lid == 0u) {
		s_n[0] = 0u; s_n[1] = 0u; s_n[2] = 0u;
		float tsize = 16.0 * PITCH;
		vec2 c2 = (vec2(tile) + 0.5) * tsize;
		float th = ground_h(c2);
		vec3 c = vec3(c2.x, isnan(th) ? CAM.y : th, c2.y);
		float tr = tsize * 0.7072 + 2.0;
		bool skip = distance(c, CAM) - tr > R_MAX + 0.5 * GROW_M;   // blades live to R + grow/2
		if (!skip && (FLAGS & FLAG_FRUSTUM) != 0u) {
			skip = !in_frustum(c, tr + SHADOW_MARGIN);
		}
		if (!skip && pc.layer == 1 && !SEA_ON) {
			// The surface layer floats only on water: a tile no water source's bin reaches has none.
			float hs = 0.5 * tsize;
			skip = water_bin_empty(c2 + vec2(-hs, -hs)) && water_bin_empty(c2 + vec2(hs, -hs))
				&& water_bin_empty(c2 + vec2(-hs, hs)) && water_bin_empty(c2 + vec2(hs, hs));
		}
		s_skip = skip;
	}
	barrier();
	if (s_skip) {
		return;   // uniform across the group
	}

	// ── The candidate ──
	ivec2 cell = tile * 16 + ivec2(gl_LocalInvocationID.xy);
	vec3 hb = rnd3(cell, 1u);   // jitter.xy, rank
	vec3 hc = rnd3(cell, 2u);   // yaw, height jitter, seed
	vec3 hd = rnd3(cell, 3u);   // type pick, shadow rank, spare
	vec2 pos = (vec2(cell) + hb.xy) * PITCH;
	float rank = hb.z;

	vec4 pl;
	int ty;
	vec4 wt = vec4(WATER_NONE);
	bool surface = pc.layer == 1;
	bool alive = surface ? surface_at(pos, hd.x, pl, ty, wt) : place_at(pos, hd.x, pl, ty);
	float dens = pl.r;
	if (dens <= 0.0) {
		alive = false;
	}
	vec4 ta = T.v[ty * 4 + 0];   // height, height_jitter, width, clump_cell
	vec4 tb = T.v[ty * 4 + 1];   // pull, facing_mix, density, colour layer
	dens *= tb.z;                // the type's own density: tall types grow sparse
	if (dens <= 0.0) {
		alive = false;
	}

	// ── Clump: procedural Voronoi over the 9 nearest jittered points ──
	vec2 centre = pos;
	float cdist = 0.0;
	ivec2 cid = cell;
	if ((FLAGS & FLAG_CLUMPING) != 0u) {
		float cs = ta.w;
		float best = clump_nearest(pos, cs, centre, cid);
		cdist = clamp(sqrt(best) / (cs * 0.75), 0.0, 1.0);
	}
	vec3 hk = rnd3(cid, 8u);    // clump height, clump facing, clump colour
	vec2 away = pos - centre;
	float away_ang = length(away) > 1e-4 ? atan(away.y, away.x) : hc.x * TAU;
	pos = mix(pos, centre, tb.x * 0.5);   // pull toward the clump centre
	// Roads, bed stripes and the terrain rule judge the FINAL root: a root pulled across a road edge,
	// into a bed path or onto ground that grows nothing after passing the rule would break it.
	// (The surface layer has none of them: the final root's water is judged below.)
	int ty0 = ty;
	if (!surface && alive && (!ground_rule(pos, ty, dens) || ground_allowance(pos) <= 0.0)) {
		alive = false;
	}
	if (ty != ty0) {   // the verge rule changed the type: its shape from here on
		ta = T.v[ty * 4 + 0];
		tb = T.v[ty * 4 + 1];
	}

	// ── Ground, distance, LOD thresholds ──
	float gh = ground_h(pos);
	if (isnan(gh)) {
		alive = false;
		gh = CAM.y;
	}
	// The depth too, at the final root: a root pulled across a waterline or a water source's outline would grow a land
	// type in the water, a bed type on the bank, or a floating one on dry ground.
	vec4 wf = water_top(pos);
	if (alive && type_eligibility(ty, wf.x > WATER_NONE ? wf.x - gh : -100.0, wf.z) <= 0.0) {
		alive = false;
	}
	// A floating root rides its surface (bobbing); a ground root sits in the ground.
	vec3 root = surface ? vec3(pos.x, wf.x + SURFACE_LIFT + bob(pos, wf, hc.z), pos.y)
		: vec3(pos.x, gh - ROOT_SINK, pos.y);
	vec3 gn = surface ? vec3(0.0, 1.0, 0.0) : ground_n(pos);
	if (gn.y < MAX_SLOPE_COS) {
		alive = false;
	}
	float d = distance(root, CAM);
	float sm = smoothstep(D_MORPH, D_SWITCH, d);
	float keep = mix(mix(1.0, K_LO, sm), K_FAR, smoothstep(DF0, DF1, d));
	// Size ramp in METRES OF TRAVEL around this blade's own threshold distance: it takes
	// GROW_M of camera travel to grow or shrink, everywhere. (Sizing the ramp from the
	// threshold's slope, |dt/dd| x GROW_M, would collapse it where each smoothstep flattens,
	// exactly at d_switch and at R, and snap every blade still mid-ramp.)
	// Symmetric about the threshold, so expected coverage still follows t(d).
	float db = threshold_distance(rank / max(dens, 1e-6));
	float g = clamp((db - d) / GROW_M + 0.5, 0.0, 1.0);
	if (g <= 0.0) {
		alive = false;
	}
	float sg = sqrt(g);   // scale both dimensions by sqrt(g) -> area follows g
	float H = ta.x * (pl.b * 2.0) * mix(0.75, 1.25, hk.x) * (1.0 - 0.35 * cdist)
		* (1.0 + (hc.y - 0.5) * 2.0 * ta.y);
	// Coverage: count x width stays constant, so the survivors widen as the field thins (capped).
	float W = ta.z * min(pow(keep, -WIDTH_EXP), WIDTH_CAP);
	if (alive && (FLAGS & FLAG_FRUSTUM) != 0u) {
		alive = in_frustum(root + vec3(0.0, H * 0.5, 0.0), H * 0.6 + 0.3 + SHADOW_MARGIN);
	}

	// ── Facing ──
	float yaw = FORCE_YAW >= 0.0 ? FORCE_YAW : hc.x * TAU;
	vec2 own = vec2(cos(yaw), sin(yaw));
	float cf = hk.y * TAU;
	vec2 fd = mix(own, vec2(cos(cf), sin(cf)), FORCE_YAW >= 0.0 ? 0.0 : tb.y);
	fd = length(fd) > 1e-3 ? normalize(fd) : own;

	// ── Bin, morph, shadow ──
	uint bin = d < D_SWITCH ? 0u : 1u;
	if (FORCE_BIN >= 0) {
		bin = uint(FORCE_BIN);
	}
	float morph = FORCE_MORPH >= 0.0 ? FORCE_MORPH : sm;
	bool shadow = alive && (FLAGS & FLAG_SHADOW_BIN) != 0u && d < SHADOW_RADIUS && hd.y < SHADOW_KEEP;

	// ── Interaction field, once per blade ──
	vec4 iv = field_at(pos);
	vec2 lay = length(iv.rg) > 1e-3 ? normalize(iv.rg) : vec2(0.0);

	// ── Append ──
	uint slot = 0u;
	uint sslot = 0u;
	if (alive) {
		slot = atomicAdd(s_n[bin], 1u);
	}
	if (shadow) {
		sslot = atomicAdd(s_n[2], 1u);
	}
	barrier();
	if (lid == 0u) {
		s_base[0] = atomicAdd(C.n[0], s_n[0]);
		s_base[1] = atomicAdd(C.n[1], s_n[1]);
		s_base[2] = atomicAdd(C.n[2], s_n[2]);
	}
	barrier();
	if (!alive) {
		return;
	}

	// Basis columns: X = side S, Y = up, Z = facing F (S x U = F: a proper rotation).
	vec3 F = vec3(fd.x, 0.0, fd.y);
	vec3 S = vec3(fd.y, 0.0, -fd.x);
	vec4 r0 = vec4(S.x, 0.0, F.x, root.x);
	vec4 r1 = vec4(0.0, 1.0, 0.0, root.y);
	vec4 r2 = vec4(S.z, 0.0, F.z, root.z);
	vec4 col = vec4(
		pack2(hk.z, cdist),
		pack2(cf / TAU, fract(away_ang / TAU)),
		pack2(lay.x * 0.5 + 0.5, lay.y * 0.5 + 0.5),
		pack2(iv.b, iv.a));
	// CUSTOM.z: (type & 15) x 2^20 + pack2(morph, seed); CUSTOM.w: (type >> 4) x 2^20 + pack2(ground
	// n.xz). pack2 fills 20 bits and each float is exact below 2^24, so each carries 4 type bits: 256
	// types, morph and seed at full precision.
	vec4 cus = vec4(H * sg, W * sg, pack2(morph, hc.z) + float(ty & 15) * 1048576.0,
		pack2(gn.x * 0.5 + 0.5, gn.z * 0.5 + 0.5) + float(ty >> 4) * 1048576.0);

	uint idx = s_base[bin] + slot;
	if (idx < (bin == 0u ? CAP_HI : CAP_LO)) {
		write_instance(bin, idx, r0, r1, r2, col, cus);
	} else {
		atomicOr(C.n[3], 1u << bin);
	}
	if (shadow) {
		uint si = s_base[2] + sslot;
		if (si < CAP_SH) {
			// Fewer casters, wider: the shadow keeps the field's coverage.
			write_instance(2u, si, r0, r1, r2, col, vec4(cus.x, cus.y / max(SHADOW_KEEP, 0.05), cus.z, cus.w));
		} else {
			atomicOr(C.n[3], 4u);
		}
	}
}
