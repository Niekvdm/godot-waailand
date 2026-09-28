#[compute]
#version 450
// Copyright (c) 2026 Digitzone
// SPDX-License-Identifier: MIT

// The air field's per-frame step (GrassAirField), one lane per texel of the toroidal window:
//   1. the equilibrium lean of a wind-response-1 plant in the air here: the wind (grass_wind.gdshaderinc: the
//      gust, the swirled direction, the tuning read as air speed) plus a rotor's wall jet WITHOUT its crests
//      (grass_downwash.gdshaderinc's envelope at the crests' mean) as one flow, saturating (wind_lean_angle), plus
//      the column's press under the disc (grass_wash_air). The TIME-driven motion stays out: the shaders keep it
//      exact. KEEP IN STEP with those files: test_grass_air_field pins the shared constants;
//   2. a texel whose world cell just entered the window starts at that equilibrium, at rest;
//   3. the spring (GrassAirField.spring_step, mirrored): the lean and its rate toward the equilibrium, softer and
//      over-damped while a MATTED patch (held flat a while) is being released; never folded past the ground.

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(set = 0, binding = 0, rgba16f) uniform restrict image2D state;    // lean.xy, rate.xy
layout(set = 0, binding = 1, rgba16f) uniform restrict image2D eq_img;   // this frame's equilibrium.xy, matting
layout(set = 0, binding = 2, std430) restrict readonly buffer Params { vec4 v[]; } P;
layout(set = 0, binding = 3) uniform sampler2D gust_tex;
// P.v[0] = (origin.xy, prev_origin.xy) world texel indices
// P.v[1] = (texel_m, size_px, dt, wash_count)
// P.v[2] = (wind_dir.xy, gust_scale, swirl_rad)
// P.v[3] = (wind_scroll.xy, wind_scroll2.xy)
// P.v[4] = (wind_scroll_sw.xy, lean_base, lean_gust)
// P.v[6], P.v[7] = the wash slots (x, z, footprint m, intensity 0..1)

const float LEAN_PER_MS = 0.075;
const float LEAN_MAX = 1.35;
const float LEAN_SAT_POW = 4.0;
const float WASH_REACH = 4.0;
const float WASH_V_FULL = 25.0;
const float WASH_V_FLAT = 18.0;
const float WASH_CORE_LEAN = 1.3;
const float CREST_MEAN = 0.775;          // grass_downwash's crests, 0.55 + 0.45 x ring, over a ring's cycle
const float FREQ_HZ = 1.2;
const float ZETA = 0.35;
const float LAID_STIFFNESS = 0.03;
const float LAID_ZETA = 1.2;
const float LAID_FROM = 0.8;
const float LAID_FULL = 1.15;
const float MAT_RISE_S = 0.5;
const float MAT_FALL_S = 4.0;
const float CAP = 1.45;
const float MAX_SUBSTEP = 1.0 / 120.0;
const float TAU = 6.28318530718;

ivec2 pmod(ivec2 a, int n) {
	return a - n * ivec2(floor(vec2(a) / float(n)));
}

float gust(vec2 xz) {
	float gs = P.v[2].z;
	float a = textureLod(gust_tex, xz * gs - P.v[3].xy, 0.0).r;
	float b = textureLod(gust_tex, xz * gs * 2.7 - P.v[3].zw + vec2(0.37, 0.11), 0.0).r;
	return clamp(a * 0.7 + b * 0.3, 0.0, 1.0);
}

vec2 dir_at(vec2 xz) {
	float n = textureLod(gust_tex, xz * P.v[2].z * 0.23 - P.v[4].xy + vec2(0.61, 0.29), 0.0).r;
	float a = (n - 0.5) * 2.0 * P.v[2].w;
	vec2 wd = P.v[2].xy;
	return vec2(wd.x * cos(a) - wd.y * sin(a), wd.x * sin(a) + wd.y * cos(a));
}

vec2 lean_vec(vec2 u) {
	float s = length(u);
	if (s < 1e-4) {
		return u * LEAN_PER_MS;
	}
	float x = LEAN_PER_MS * s;
	return u * (x / pow(1.0 + pow(x / LEAN_MAX, LEAN_SAT_POW), 1.0 / LEAN_SAT_POW) / s);
}

void main() {
	int n = int(P.v[1].y);
	ivec2 idx = ivec2(gl_GlobalInvocationID.xy);
	if (idx.x >= n || idx.y >= n) {
		return;
	}
	ivec2 origin = ivec2(P.v[0].xy);
	ivec2 prev = ivec2(P.v[0].zw);
	ivec2 w = origin + pmod(idx - origin, n);              // this texel's world cell
	vec2 p = (vec2(w) + 0.5) * P.v[1].x;
	// 1. The equilibrium.
	float g = gust(p);
	vec2 u = dir_at(p) * ((P.v[4].z + P.v[4].w * g * g) / LEAN_PER_MS);
	vec2 press = vec2(0.0);
	int nw = int(P.v[1].w);
	for (int k = 0; k < nw; k++) {
		vec4 ws = P.v[6 + k];
		vec2 away = p - ws.xy;
		float d = length(away);
		float rho = d / max(ws.z, 0.5);
		if (ws.w <= 0.0 || rho >= WASH_REACH) {
			continue;
		}
		vec2 dir = d > 1e-3 ? away / d : vec2(1.0, 0.0);
		float core = 1.0 - smoothstep(0.55, 1.05, rho);
		float jet_k = smoothstep(0.35, 1.5, rho) * (1.0 - smoothstep(1.7, WASH_REACH, rho));
		press += dir * (ws.w * core);
		u += dir * (ws.w * jet_k * CREST_MEAN * WASH_V_FULL);
	}
	float pl = length(press);
	vec2 eq = lean_vec(u);
	if (pl > 1e-4) {
		eq += press * (WASH_CORE_LEAN * min(pl * WASH_V_FULL / WASH_V_FLAT, 1.0) / pl);
	}
	float el = length(eq);
	if (el > 1.45) {
		eq *= 1.45 / el;
	}
	// 2. Entered the window this frame: at its equilibrium, at rest, unmatted.
	vec4 s = imageLoad(state, idx);
	float mat = imageLoad(eq_img, idx).z;
	if (any(lessThan(w, prev)) || any(greaterThanEqual(w, prev + ivec2(n)))) {
		s = vec4(eq, 0.0, 0.0);
		mat = 0.0;
	}
	// 3. The spring.
	float dt = P.v[1].z;
	vec2 lean = s.xy;
	vec2 rate = s.zw;
	if (dt > 0.0) {
		int steps = max(1, int(ceil(dt / MAX_SUBSTEP)));
		float h = dt / float(steps);
		float w0 = TAU * FREQ_HZ;
		for (int i = 0; i < steps; i++) {
			float l = length(lean);
			float target = smoothstep(LAID_FROM, LAID_FULL, l);
			mat += (target - mat) * (1.0 - exp(-h / (target > mat ? MAT_RISE_S : MAT_FALL_S)));
			float kk = w0 * w0;
			float zeta = ZETA;
			if (l > 1e-5) {
				float soft = mat * smoothstep(0.0, 0.2, -dot(eq - lean, lean / l));   // matted, being released
				kk *= pow(LAID_STIFFNESS, soft);          // geometric: the creep lasts while the matting fades
				zeta = mix(ZETA, LAID_ZETA, soft);
			}
			rate += ((eq - lean) * kk - rate * (2.0 * zeta * sqrt(kk))) * h;
			lean += rate * h;
			float ll = length(lean);
			if (ll > CAP) {
				lean *= CAP / ll;
				vec2 outw = lean / CAP;
				rate -= outw * max(dot(rate, outw), 0.0);
			}
		}
	}
	imageStore(state, idx, vec4(lean, rate));
	imageStore(eq_img, idx, vec4(eq, mat, 0.0));
}
