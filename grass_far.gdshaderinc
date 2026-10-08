// Copyright (c) 2026 Digitzone
// SPDX-License-Identifier: MIT
// THE GRASS FAR FIELD IN THE TERRAIN: canopy light + carpet grain. The terrain shader includes this
// after grass_wind.gdshaderinc, behind `grass_far_enabled` (off: the terrain renders exactly as it
// would without it; GrassBlades switches it on through GrassFarField).
//
// THE RULE: no colour and no noise of its own. Past the blades the terrain texture keeps its colour;
// this multiplies the terrain's albedo by a scalar and adds a grey BACKLIGHT (the engine multiplies it by
// the albedo). What it adds is the blade carpet itself, measured: tuned against the real blades drawn out
// to 350 m.
//   - CANOPY LIGHT: forward-scatter glow toward the sun, a narrow backscatter hotspot, a little grazing
//     sheen, and the gust field as bands stretched across the wind, travelling down it.
//   - CARPET GRAIN: the baked tile (GrassFarGrain: the carpet's luminance over bare ground, per type)
//     sampled ~2 mips SHARPER than the pixel (the blades there alias to pixel-wide flecks), the darkest
//     of three samples along the view over the ground a blade's side hides (height / tan elevation),
//     sparse grass as FEWER flecks, the four corners' types blended; the grain fades over
//     far_grain_fade, the carpet's mean brightness (a view-dependent canopy gap fraction) over
//     far_carpet_fade.
// Where the grass map grows AND the terrain rule allows (grass_allow), from the blades' fade outward.
// THE PAINT OVERLAY (the editor's view strip, GrassOverlay) replaces all of it while grass_overlay > 0: what the grass
// map holds, drawn on the terrain at every distance (grass_overlay_apply).

uniform bool grass_far_enabled = false;
uniform highp sampler2DArray grass_maps : repeat_disable;   // GrassMaps (a layer per map), GrassMapCodec: R density x 128, G override + 1, B height, A force
// GrassMaps.slot_table (GrassFarField.slot_texture): x = the terrain layer, r = 1 + the layer of grass_maps holding its
// region's map, 0 where it has none (NEUTRAL, nothing fetched). Unset (black): every region reads NEUTRAL.
uniform highp sampler2D grass_map_slots : hint_default_black, filter_nearest, repeat_disable;
uniform float grass_allow[32];                // the terrain rule by texture id (GrassTerrainGrowth)
uniform vec2 far_ramp = vec2(100.0, 120.0);   // the blades' fade: radius - edge_fade_m .. radius (m)
uniform vec3 sun_travel_dir = vec3(0.0, -1.0, 0.0);
// canopy light
uniform float far_glow_k = 0.6;               // forward scatter toward the sun (BACKLIGHT)
uniform float far_glow_pow = 3.0;
uniform float far_hot_k = 0.12;               // backscatter hotspot (the sun behind the viewer), narrow
uniform float far_hot_pow = 12.0;
uniform float far_sheen_k = 0.12;             // grazing views see the lit blade sides, not the gaps
uniform float far_gust_k = 0.08;              // gust bands, +- this fraction
uniform float far_gust_stretch = 0.3;         // < 1: bands long across the wind, travelling down it
// carpet grain (GrassFarGrain's bake; off without a current bake)
uniform bool far_grain_on = false;
uniform highp sampler2DArray far_grain_tex : filter_linear_mipmap_anisotropic, repeat_enable;   // L = carpet / bare ground, / 2 (anisotropic: the LOD it was tuned with)
uniform float far_grain_m = 16.0;             // the tile's size on the ground (m)
uniform float far_grain_std[288];             // type x 9 + lod (32 types): the tile's std at each mip
uniform float far_grain_mean[32];             // the tile's mean: the carpet's brightness over bare ground
uniform float far_type_h[32];                 // blade height per type (m)
uniform vec4 far_slot[32];                    // per texture id: its mix's grain mean, lod-0 std, blade height, dominant type
uniform float far_sea_level = -1e9;           // below it the far field adds nothing
uniform float far_grain_k = 1.5;              // grain contrast x the bake's own
uniform float far_grain_bias = 2.0;           // mips sharper than the pixel: flecks, not a mottle
uniform float far_smear_k = 1.5;              // x height / tan(elevation): the ground a blade's side hides
uniform float far_smear_max = 2.5;            // m (at 4, tall sparse types go solid dark)
uniform float far_smear_mix = 0.6;            // the side view's share against the centre sample
uniform float far_grain_std_cap = 0.12;       // no type's grain stronger (stronger grain draws the patch outlines)
uniform float far_type_spread = 0.6;          // how much of each type's own brightness survives
uniform float far_mean_all = 0.93;            // the carpet brightness the types are pulled toward
uniform float far_grain_b = 0.5;              // canopy gap fraction: blade brightness / bare ground
uniform float far_grain_lai = 1.0;            // x the canopy depth the top-down bake implies
uniform float far_grain_gamma = 0.6;          // the gap fraction's path: P0^(lai / sin^gamma)
uniform float far_grain_fade = 400.0;         // m past the blades over which the grain gives way
uniform bool far_all_grounds = false;        // the editor preview: every ground grows (GrassEditorPreview.all_grounds)
uniform float far_carpet_fade = 1500.0;       // m past the blades over which the carpet's brightness gives way
// the paint overlay (GrassOverlay; the editor preview only)
uniform int grass_overlay = 0;                // GrassOverlay.Mode: 0 off, 1 what's painted, 2 density, 3 height
uniform vec3 grass_overlay_hue[32];           // each slot's tint (GrassOverlay.hues_linear)
uniform vec3 grass_overlay_key[4];            // removed, forced, less, more (GrassOverlay.key_linear)

const vec4 GRASS_MAP_NEUTRAL = vec4(128.0 / 255.0, 0.0, 128.0 / 255.0, 1.0);   // GrassMaps.NEUTRAL: x1, the ground decides

// The grass map texel at a terrain lookup i (i.z the terrain layer, >= 0), through the slot table.
vec4 grass_map_texel(ivec3 i) {
	int l = int(texelFetch(grass_map_slots, ivec2(clamp(i.z, 0, 1023), 0), 0).r + 0.5) - 1;
	return l < 0 ? GRASS_MAP_NEUTRAL : texelFetch(grass_maps, ivec3(i.xy, l), 0);
}

// A corner's terrain rule, base and overlay blended: x = its own grass (0 on a "painted only" surface, where
// GrassTerrainGrowth writes -a), y = what a painted override needs (|a|).
vec2 far_corner_allow(ivec3 i) {
	uint c = floatBitsToUint(texelFetch(_control_maps, i, 0).r);
	float ab = grass_allow[int(c >> 27u & 0x1Fu)];
	float ao = grass_allow[int(c >> 22u & 0x1Fu)];
	float bl = float(c >> 14u & 0xFFu) * (1.0 / 255.0);
	return vec2(mix(max(ab, 0.0), max(ao, 0.0), bl), mix(abs(ab), abs(ao), bl));
}

// A corner's far-field params (grain mean, lod-0 std, blade height, the type whose grain layer is
// sampled): a painted override's type's own (GrassMapCodec: G = override + 1), else its texture slots'
// mixes (far_slot), base and overlay weighted by the growth each contributes, as place_at picks them.
vec4 far_corner_params(ivec3 i, vec4 gt) {
	float o = floor(gt.g * 255.0 + 0.5) - 1.0;
	if (o >= 0.0) {
		int t = int(min(o, 31.0));
		return vec4(far_grain_mean[t], far_grain_std[t * 9], far_type_h[t], float(t));
	}
	uint c = floatBitsToUint(texelFetch(_control_maps, i, 0).r);
	int sb = int(c >> 27u & 0x1Fu);
	int so = int(c >> 22u & 0x1Fu);
	float bl = float(c >> 14u & 0xFFu) * (1.0 / 255.0);
	bool fk = gt.a < 0.5 || far_all_grounds;       // forced: a painted-only surface lends its mix (|a|)
	float gb = (1.0 - bl) * (fk ? abs(grass_allow[sb]) : max(grass_allow[sb], 0.0));
	float go = bl * (fk ? abs(grass_allow[so]) : max(grass_allow[so], 0.0));
	float k = go / max(gb + go, 1e-6);
	vec4 p = mix(far_slot[sb], far_slot[so], k);
	p.w = k > 0.5 ? far_slot[so].w : far_slot[sb].w;
	return p;
}

// x = cover (R/128 x 1.3 clamped, times the terrain rule), y = the grain type of the corner growing the
// most; p0..p3 the four corners' params (far_corner_params), kd their weights for far_type_params
// (bilinear x the growth there). 0 where a corner's region is not loaded.
vec2 far_layer(ivec3 i0, ivec3 i1, ivec3 i2, ivec3 i3, vec4 w, out vec4 p0, out vec4 p1, out vec4 p2,
		out vec4 p3, out vec4 kd) {
	p0 = vec4(0.0); p1 = vec4(0.0); p2 = vec4(0.0); p3 = vec4(0.0); kd = vec4(0.0);
	if (i0.z < 0 || i1.z < 0 || i2.z < 0 || i3.z < 0) {
		return vec2(0.0);
	}
	vec4 g0 = grass_map_texel(i0);
	vec4 g1 = grass_map_texel(i1);
	vec4 g2 = grass_map_texel(i2);
	vec4 g3 = grass_map_texel(i3);
	vec2 c0 = far_corner_allow(i0);
	vec2 c1 = far_corner_allow(i1);
	vec2 c2 = far_corner_allow(i2);
	vec2 c3 = far_corner_allow(i3);
	vec4 a = vec4(c0.x, c1.x, c2.x, c3.x);
	// A painted override plants at its painted density wherever the ground allows grass (place_at's rule).
	vec4 kept = vec4(lessThan(vec4(g0.g, g1.g, g2.g, g3.g), vec4(254.5 / 255.0)));   // G 255: removed, nothing grows
	vec4 painted = step(vec4(0.5 / 255.0), vec4(g0.g, g1.g, g2.g, g3.g)) * step(vec4(1e-6), vec4(c0.y, c1.y, c2.y, c3.y));
	vec4 forced = far_all_grounds ? vec4(1.0) : vec4(lessThan(vec4(g0.a, g1.a, g2.a, g3.a), vec4(0.5)));   // A < 128
	a = mix(a, vec4(1.0), max(painted, forced)) * kept;
	kd = w * vec4(g0.r, g1.r, g2.r, g3.r) * (255.0 / 128.0) * a;      // each corner's growth (R/128 x allowance)
	p0 = far_corner_params(i0, g0);
	p1 = far_corner_params(i1, g1);
	p2 = far_corner_params(i2, g2);
	p3 = far_corner_params(i3, g3);
	float ty = p3.w;                    // the grain layer: the corner that grows the most (not the nearest:
	float best = kd.w;                  // beside a strip that grows nothing, that corner's "mix" is no grass)
	if (kd.x > best) { best = kd.x; ty = p0.w; }
	if (kd.y > best) { best = kd.y; ty = p1.w; }
	if (kd.z > best) { best = kd.z; ty = p2.w; }
	float dens = (g0.r * w.x + g1.r * w.y + g2.r * w.z + g3.r * w.w) * (255.0 / 128.0);   // R/128
	float allow = dot(a, w);
	return vec2(clamp(dens * 1.3, 0.0, 1.0) * allow, ty);
}

// The corners' params weighted by their growth: x = mean (carpet over bare ground), y = lod-0 grain std,
// z = blade height (the nearest corner's type alone would draw the type map's blocky outline).
vec3 far_type_params(vec4 p0, vec4 p1, vec4 p2, vec4 p3, vec4 kd) {
	vec4 k = kd + 1e-4;
	return (p0.xyz * k.x + p1.xyz * k.y + p2.xyz * k.z + p3.xyz * k.w) / (k.x + k.y + k.z + k.w);
}

// Keep a texel's fleck with probability `cover` (the tile was baked at full density): sparse grass is
// fewer flecks, each as dark as in a full carpet.
float far_keep(vec2 q, float tf, float level, float cover) {
	vec2 cell = floor(q * (512.0 / exp2(level)));
	return step(fract(sin(dot(cell + tf * 17.0 + level * 3.1, vec2(12.9898, 78.233))) * 43758.5453), cover);
}

// One grain sample (carpet / bare ground). The keep test blends between the two mips it straddles: a
// hash of ONE level would jump at every integer lod and draw a line across the field at that distance.
float far_fleck(vec2 q, float tf, float lod, float cover) {
	float g = textureLod(far_grain_tex, vec3(q, tf), lod).r * 2.0;
	float fl = floor(lod);
	return mix(1.0, g, mix(far_keep(q, tf, fl, cover), far_keep(q, tf, fl + 1.0, cover), fract(lod)));
}

// Gust bands: the gust field stretched across the wind (the scroll runs along it).
float far_gust_band(vec2 xz) {
	vec2 d = wind_dir;
	vec2 n = vec2(-d.y, d.x);
	vec2 p = vec2(dot(xz, d), dot(xz, n) * far_gust_stretch);
	return wind_gust(p.x * d + p.y * n);
}

// Stripes across t (in stripe periods): 1 on a stripe (half the period), 0 between; their mean once they get finer
// than a pixel.
float grass_overlay_stripe(float t) {
	float aa = fwidth(t);
	float s = 1.0 - smoothstep(0.5 - aa, 0.5 + aa, abs(fract(t) - 0.5) * 2.0);
	return mix(s, 0.5, clamp(aa * 2.0 - 1.0, 0.0, 1.0));
}

// The paint overlay (GrassOverlay): the texel of the nearest corner (i0..i3 by the bilinear weights w) over the terrain's
// albedo. What's painted: a painted species' tint, removed red and hatched, forced with orange stripes, a painted
// flower color with white dots. Density / height: blue below x1, warm above, stronger further from it; removed hatched
// dark. The patterns are worked out first: their derivatives need every pixel of the quad.
vec3 grass_overlay_apply(ivec3 i0, ivec3 i1, ivec3 i2, ivec3 i3, vec4 w, vec3 wpos, vec3 alb) {
	float hatch = grass_overlay_stripe((wpos.x + wpos.z) * 1.25);       // 0.8 m apart
	float stripes = grass_overlay_stripe((wpos.x - wpos.z) * 1.25);
	vec2 dq = fract(wpos.xz * 2.0) - 0.5;                               // a dot every 0.5 m
	float dots = 1.0 - smoothstep(0.14, 0.14 + fwidth(wpos.x * 2.0) + 1e-4, length(dq));
	ivec3 i = i0;
	float best = w.x;
	if (w.y > best) { best = w.y; i = i1; }
	if (w.z > best) { best = w.z; i = i2; }
	if (w.w > best) { i = i3; }
	if (i.z < 0) {
		return alb;
	}
	ivec4 b = ivec4(floor(grass_map_texel(i) * 255.0 + 0.5));
	vec3 col = alb;
	if (grass_overlay == 1) {
		if (b.g == 255) {
			col = mix(alb, mix(grass_overlay_key[0], grass_overlay_key[0] * 0.3, hatch), 0.75);
		} else if (b.g > 0) {
			col = mix(alb, grass_overlay_hue[min(b.g - 1, 31)], 0.75);
		}
		if (b.a < 128) {
			col = mix(col, grass_overlay_key[1], 0.85 * stripes);
		}
		int ce = b.a & 127;
		if (ce > 0 && ce < 127) {
			col = mix(col, vec3(1.0), 0.9 * dots);
		}
		return col;
	}
	int v = grass_overlay == 2 ? b.r : b.b;
	if (v != 128) {
		float d = float(v - 128) / 128.0;
		col = mix(alb, d < 0.0 ? grass_overlay_key[2] : grass_overlay_key[3], mix(0.3, 0.85, min(abs(d), 1.0)));
	}
	if (b.g == 255) {
		col = mix(col, vec3(0.02), 0.6 * hatch);
	}
	return col;
}

// The terrain's albedo past the blades; `glow` = the BACKLIGHT (grey). i0..i3 / w: the terrain shader's
// four corner lookups and their bilinear weights (before its height blend reassigns them); nrm_v the view-space
// terrain normal; view / view_matrix as in fragment().
vec3 grass_far_apply(ivec3 i0, ivec3 i1, ivec3 i2, ivec3 i3, vec4 w, vec3 wpos, vec3 cam, vec3 view,
		mat4 view_matrix, vec3 nrm_v, vec3 alb, out vec3 glow) {
	glow = vec3(0.0);
	if (grass_overlay > 0) {
		return grass_overlay_apply(i0, i1, i2, i3, w, wpos, alb);
	}
	float dist = length(wpos - cam);
	float ramp = smoothstep(far_ramp.x, far_ramp.y, dist);
	if (ramp <= 0.0) {
		return alb;                 // under the blades: no texture fetch at all
	}
	if (wpos.y < far_sea_level) {
		return alb;                 // under the sea: the water's optics own the look
	}
	vec4 p0, p1, p2, p3, kd;
	vec2 gl = far_layer(i0, i1, i2, i3, w, p0, p1, p2, p3, kd);
	if (gl.x <= 0.0) {
		return alb;
	}
	float c = gl.x * ramp;
	vec3 sun_v = normalize((view_matrix * vec4(sun_travel_dir, 0.0)).xyz);
	float fwd = max(dot(view, sun_v), 0.0);
	float back = max(dot(-view, sun_v), 0.0);
	float sv = max(clamp(dot(nrm_v, view), 0.0, 1.0), 0.03);          // sin of the view elevation
	glow = vec3(far_glow_k * c * pow(fwd, far_glow_pow));
	float gain = 1.0 + far_hot_k * c * pow(back, far_hot_pow);
	gain *= 1.0 + far_sheen_k * c * pow(1.0 - sv, 5.0);
	gain *= 1.0 + far_gust_k * c * (far_gust_band(wpos.xz) - 0.5) * 2.0;
	if (far_grain_on) {
		int ti = int(clamp(floor(gl.y + 0.5), 0.0, 31.0));
		float tf = float(ti);
		float tn = sv / sqrt(max(1.0 - sv * sv, 1e-4));                   // tan of the elevation
		vec2 vg = wpos.xz - cam.xz;
		vg /= max(length(vg), 1e-3);                                      // the view direction on the ground
		vec3 tp = far_type_params(p0, p1, p2, p3, kd);
		float tmean = mix(far_mean_all, tp.x, far_type_spread);
		float L = min(far_smear_k * tp.z / tn, far_smear_max);
		vec2 q = wpos.xz / far_grain_m;
		float lod = max(textureQueryLod(far_grain_tex, q).y - far_grain_bias, 0.0);
		vec2 dq = -vg * (L / far_grain_m);                                // toward the camera: blades in front
		float g0 = far_fleck(q, tf, lod, gl.x);
		float g = mix(g0, min(g0, min(far_fleck(q + dq * 0.5, tf, lod, gl.x), far_fleck(q + dq, tf, lod, gl.x))),
			far_smear_mix);
		float norm = min(1.0, far_grain_std_cap / max(tp.y, 1e-4));
		g = tmean + (g - far_grain_mean[ti]) * norm;                      // capped contrast, blended mean
		g = 1.0 + far_grain_k * (g - 1.0);                                // carpet / bare ground, sampled
		float bb = clamp(far_grain_b, 0.0, 0.95);
		float p0 = clamp((tmean - bb) / (1.0 - bb), 0.0, 1.0);
		float carpet = mix(1.0, bb + (1.0 - bb) * pow(p0, far_grain_lai / pow(sv, far_grain_gamma)), gl.x);
		float near = 1.0 - smoothstep(far_ramp.y, far_ramp.y + far_grain_fade, dist);
		float kb = ramp * (1.0 - smoothstep(far_ramp.y, far_ramp.y + far_carpet_fade, dist));
		gain *= max(1.0 + kb * (mix(carpet, g, near) - 1.0), 0.0);
	}
	return alb * gain;
}
