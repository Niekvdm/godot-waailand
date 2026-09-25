#[compute]
#version 450
// Copyright (c) 2026 Digitzone
// SPDX-License-Identifier: MIT

// The interaction field's per-frame pass, one lane per texel:
//   1. a texel whose WORLD cell just entered the toroidal window is cleared;
//   2. crush decays linearly: b = max(b - decay*dt, 0) (Jahrmann & Wimmer 2017's shape);
//      the transient push is cleared;
//   3. stamps (capsules in xz) write crush + lay direction, or push.

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(set = 0, binding = 0, rgba16f) uniform restrict image2D field;
layout(set = 0, binding = 1, std430) restrict readonly buffer Stamps { vec4 v[]; } S;
// S.v[0] = (origin.x, origin.y, prev_origin.x, prev_origin.y) world texel indices
// S.v[1] = (texel_m, size_px, decay_dt, n_stamps)
// per stamp k, base 2 + 3k: (a.xyz, radius), (b.xyz, kind), (dir.xy, strength, 0)

ivec2 pmod(ivec2 a, int n) {
	return a - n * ivec2(floor(vec2(a) / float(n)));
}

void main() {
	int n = int(S.v[1].y);
	ivec2 idx = ivec2(gl_GlobalInvocationID.xy);
	if (idx.x >= n || idx.y >= n) {
		return;
	}
	ivec2 origin = ivec2(S.v[0].xy);
	ivec2 prev = ivec2(S.v[0].zw);
	ivec2 w = origin + pmod(idx - origin, n);            // this texel's world cell
	vec4 v = imageLoad(field, idx);
	if (any(lessThan(w, prev)) || any(greaterThanEqual(w, prev + ivec2(n)))) {
		v = vec4(0.0);                                  // entered the window this frame
	}
	v.b = max(v.b - S.v[1].z, 0.0);
	v.a = 0.0;
	if (v.b <= 0.0) {
		v.rg = vec2(0.0);
	}
	vec2 p = (vec2(w) + 0.5) * S.v[1].x;
	int ns = int(S.v[1].w);
	for (int k = 0; k < ns; k++) {
		vec4 a = S.v[2 + 3 * k];
		vec4 b = S.v[3 + 3 * k];
		vec4 m = S.v[4 + 3 * k];
		vec2 ab = b.xz - a.xz;
		float h = clamp(dot(p - a.xz, ab) / max(dot(ab, ab), 1e-8), 0.0, 1.0);
		vec2 closest = a.xz + ab * h;
		float d = distance(p, closest);
		if (d >= a.w) {
			continue;
		}
		float s = m.z * (1.0 - smoothstep(a.w * 0.7, a.w, d));
		if (b.w < 0.5) {
			// crush: persistent, laid along the direction of travel
			if (s > v.b) {
				v.rg = m.xy;
			}
			v.b = max(v.b, s);
		} else {
			// push: transient, away from the body's centre line (only where not crushed)
			v.a = max(v.a, s);
			if (v.b < 0.05 && d > 1e-4) {
				v.rg = (p - closest) / d;
			}
		}
	}
	imageStore(field, idx, v);
}
