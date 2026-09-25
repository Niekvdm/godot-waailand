// Copyright (c) 2026 Digitzone
// SPDX-License-Identifier: MIT
// The palette entry at xz: one per `cell` rectangle, hashed with stream 9 + salt (the kind's
// palette salt, DecoKinds.palette_salt). The decorations, the blade handoff and the far field
// all call this, so a flower bed is one colour up close and far away. GrassHash.palette_index
// is the CPU mirror.

uvec3 pal_pcg3d(uvec3 v) {
	v = v * 1664525u + 1013904223u;
	v.x += v.y * v.z; v.y += v.z * v.x; v.z += v.x * v.y;
	v ^= v >> 16u;
	v.x += v.y * v.z; v.y += v.z * v.x; v.z += v.x * v.y;
	return v;
}

float palette_index(vec2 xz, vec2 cell, float n, float salt) {
	ivec2 c = ivec2(floor(xz / cell));
	uvec3 h = pal_pcg3d(uvec3(uint(c.x), uint(c.y), 9u + uint(salt)));
	return min(floor(float(h.x >> 8u) * (1.0 / 16777216.0) * n), n - 1.0);
}
