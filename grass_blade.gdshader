// Copyright (c) 2026 Digitzone
// SPDX-License-Identifier: MIT
shader_type spatial;
// The grass blade. Every blade is built HERE from its instance:
//   transform  root + side axis S (X) + facing F (Z), up = Y
//   COLOR      pack2(clump hash, clump dist) + (painted color & 15) x 2^20, pack2(clump facing, away angle) +
//              (painted color >> 4) x 2^20 (the flower color the handoff tints with; 0: the field's stripes),
//              pack2(lay dir), pack2(crush, push)          (pack2: exact integers, see blade_place.glsl)
//   CUSTOM     height, width (both already x sqrt(grow)), type x 2^20 + pack2(morph, seed),
//              pack2(ground n.xz)
// Shape and look are PER TYPE (GrassTypes): type_shape / type_look indexed by the
// type in CUSTOM.z; colour from a Texture2DArray (layer 2 x type, accent at +1).
// Rules: no custom light() (it kills BACKLIGHT and direct specular); no ALPHA (transparent
// queue, no motion vectors); Godot flips NORMAL for back faces itself under cull_disabled
// (DO_SIDE_CHECK), so never flip again; motion that needs motion vectors reads TIME inside
// vertex() (see grass_wind.gdshaderinc).
// The look: wide curved blades, a dark saturated base to a yellow tip on a quartic, dark roots
// in ALBEDO, a view-dependent golden glow toward the sun, colour and normal converging with
// distance. The lighting stays in Godot's STANDARD model: the glow is BACKLIGHT scaled by how
// directly the camera faces the sun, so it is still per light, coloured by the light and shadowed.
render_mode cull_disabled, world_vertex_coords, depth_draw_opaque;
#include "res://addons/waailand/grass_wind.gdshaderinc"
#include "res://addons/waailand/grass_wash.gdshaderinc"   // the two-slot downwash (a game can share it with its other surfaces)
#include "res://addons/waailand/grass_air.gdshaderinc"    // the grass's memory of the air (GrassAirField)
#include "res://addons/waailand/grass_palette.gdshaderinc"
#include "res://addons/waailand/grass_handoff.gdshaderinc"
#include "res://addons/waailand/grass_ground.gdshaderinc"   // the terrain's colour under the blade

uniform sampler2DArray colour_tex : source_color, filter_linear, repeat_disable;   // GrassColour: layer 2i base, 2i+1 accent
uniform vec4 type_shape[32];   // GrassTypes c: tilt rad, bend, taper_pow, profile (0 blade .. 1 leaf)
uniform vec4 type_look[32];    // GrassTypes d: midrib, wind_response, specular, accent
uniform float type_ground[32];     // GrassTypes ground_colour: 0 = the type's colour .. 1 = the ground's
uniform float type_mean_luma[32];     // GrassColour.mean_luma: the type's mean linear luminance
uniform float type_height[32];     // GrassTypes height (m): the sway's frequency, never the live, growing height
uniform float lo_u1 = 0.39;           // LOW mesh levels (BladeMesh.levels(3, GAMMA))
uniform float lo_u2 = 0.71;
uniform float px_per_m = 700.0;       // screen px per metre at 1 m from the MAIN camera
uniform float min_px = 1.0;
uniform float thicken = 1.0;
uniform float roundness_deg = 22.0;
uniform float normal_converge_m = 59.0;  // the e-folding distance (m) of the normals' convergence
uniform float r_edge = 25.0;
uniform float edge_fade = 5.0;
uniform float rough_far = 0.95;
uniform float tip_roughness = 0.55;    // rough enough to tame a silver sheen under a noon sun
uniform vec3 sss_color : source_color = vec3(1.0, 0.75, 0.1);   // the colour of the sunlight through a blade
uniform float sss_strength = 2.0;
uniform float sss_floor = 0.12;          // some translucency even side-on (never black)
uniform vec3 sun_travel_dir = vec3(0.0, -1.0, 0.0);   // world direction the sunlight travels
uniform float root_dark = 0.7;           // ALBEDO *= mix(root_dark, 1, t^2). Lower darkens the roots; 0.1
                                         // (near-black) reads far too dark under a bright sky
uniform float normal_up = 0.5;           // lighting normal bent toward UP: near-vertical blades under a high
                                         // sun catch little light otherwise
uniform float downhill_bend = 0.25;
uniform float away_bend = 0.20;
uniform float crush_angle = 1.35;
uniform float push_angle = 0.8;
// The sea (GrassBlades.set_sea: the level and the swell): under water the swell's surge moves the plant
// instead of the wind. GrassSurge holds the same maths.
uniform bool sea_on = false;
uniform float sea_level = 0.0;
uniform vec2 swell_dir = vec2(0.0, 1.0);
uniform float swell_h = 0.0;           // crest to trough, m
uniform float swell_k = 0.037;         // rad/m
uniform float swell_omega = 0.602;     // rad/s
uniform float swell_phase = 0.0;       // -omega x the ocean's wave clock
uniform int debug_view = 0;
// Weather (GrassBlades.set_weather)
uniform float weather_wetness : hint_range(0.0, 1.0) = 0.0;
uniform float snow_coverage : hint_range(0.0, 1.0) = 0.0;
uniform float snow_bury : hint_range(0.0, 1.0) = 0.85;
uniform float snow_frost : hint_range(0.0, 1.0) = 0.55;
uniform vec3 snow_tint : source_color = vec3(0.86, 0.89, 0.94);
uniform float wet_darken : hint_range(0.0, 1.0) = 0.30;

// Every varying takes a whole interpolator slot, whatever its size, and an Intel iGPU has 29 including Godot's
// own: the eight per-vertex floats travel as two vec4s (interpolation is per component, so the result is the same
// as eight floats). At 30 slots the shader fails to compile there and the grass is invisible.
varying vec4 v_blade;     // x lateral offset from the centreline, metres (affine: see fragment); y local blade
                          // width, metres (affine); z t along the blade; w u across it
varying vec4 v_where;     // x distance to the camera, y distance to the clump centre, z morph, w crush
#define v_lat v_blade.x
#define v_wid v_blade.y
#define v_t v_blade.z
#define v_u v_blade.w
#define v_dist v_where.x
#define v_cdist v_where.y
#define v_morph v_where.z
#define v_crush v_where.w
varying vec3 v_side;
varying vec3 v_clump_n;
varying vec3 v_ground_n;
varying flat vec4 v_look;   // the type's colour layer, accent, specular, midrib (one slot)
varying flat vec4 v_tint;
varying flat vec4 v_ground;   // rgb the terrain's colour at the root, a the type's weight toward it

vec2 unpack2(float v) {
	float a = floor(v / 1024.0);
	return vec2(a, v - a * 1024.0) / 1023.0;
}

vec3 rotate_about(vec3 v, vec3 axis, float ang) {
	float c = cos(ang);
	float s = sin(ang);
	return v * c + cross(axis, v) * s + axis * dot(axis, v) * (1.0 - c);
}

vec3 bez(vec3 p0, vec3 p1, vec3 p2, vec3 p3, float t) {
	float u = 1.0 - t;
	return u * u * u * p0 + 3.0 * u * u * t * p1 + 3.0 * u * t * t * p2 + t * t * t * p3;
}

vec3 dbez(vec3 p0, vec3 p1, vec3 p2, vec3 p3, float t) {
	float u = 1.0 - t;
	return 3.0 * u * u * (p1 - p0) + 6.0 * u * t * (p2 - p1) + 3.0 * t * t * (p3 - p2);
}

// Width along the blade: a tapered blade (1 - t^p, full at the root) or, at profile 1, a leaf
// (1 - |2t - 1|^p: narrow at both ends, widest mid-way, like a chrysanthemum leaf).
float width_at(float w, float t, vec4 shp) {
	float blade = 1.0 - pow(t, shp.z);
	float leaf = 1.0 - pow(abs(2.0 * t - 1.0), shp.z);
	return w * mix(blade, leaf, shp.w);
}

// A type's colour: its base layer with its seasonal accent layer blended in (GrassColour).
vec3 blade_colour(float u, float v, float layer, float accent) {
	vec3 a = texture(colour_tex, vec3(u, v, layer)).rgb;
	vec3 b = texture(colour_tex, vec3(u, v, layer + 1.0)).rgb;
	return mix(a, b, accent);
}

// The type's colour moved toward the ground's by the type's weight, keeping its base→tip gradient:
// the ground colour scaled by this texel's luminance over the type's mean.
vec3 ground_shift(vec3 c) {
	if (v_ground.a <= 0.0) {
		return c;
	}
	float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
	vec3 g = v_ground.rgb * l / max(type_mean_luma[int(v_look.x * 0.5 + 0.5)], 1e-4);
	return mix(c, g, v_ground.a);
}

// Rotate a control point about the root, toward `b` (xz), by `ang`.
vec3 bend_point(vec3 p, vec3 root, vec2 b, float ang) {
	float l = length(b);
	if (l < 1e-4 || ang < 1e-5) {
		return p;
	}
	vec3 axis = normalize(cross(vec3(0.0, 1.0, 0.0), vec3(b.x, 0.0, b.y) / l));
	return root + rotate_about(p - root, axis, ang);
}

void vertex() {
	vec3 root = MODEL_MATRIX[3].xyz;
	vec3 S = normalize(MODEL_MATRIX[0].xyz);
	vec3 F = normalize(MODEL_MATRIX[2].xyz);
	vec3 U = vec3(0.0, 1.0, 0.0);
	float H = INSTANCE_CUSTOM.x * (1.0 - snow_coverage * snow_bury);   // snow buries the blade
	float W = INSTANCE_CUSTOM.y;
	// CUSTOM.z = (type & 15) x 2^20 + pack2(morph, seed), CUSTOM.w = (type >> 4) x 2^20 + pack2(n.xz):
	// exact integers below 2^24 (see blade_place.glsl).
	float ty_lo = floor(INSTANCE_CUSTOM.z / 1048576.0);
	float ty_hi = floor(INSTANCE_CUSTOM.w / 1048576.0);
	float ty_f = ty_lo + 16.0 * ty_hi;
	int ty = int(ty_f);
	vec2 ms = unpack2(INSTANCE_CUSTOM.z - ty_lo * 1048576.0);
	vec4 shp = type_shape[ty];
	vec4 look = type_look[ty];
	float resp = look.y;   // wind response (GrassTypes d.y): short grass dances, tall grass heaves
	float morph = ms.x;
	float seed = ms.y;
	vec2 nxz = unpack2(INSTANCE_CUSTOM.w - ty_hi * 1048576.0) * 2.0 - 1.0;
	vec3 gn = vec3(nxz.x, sqrt(max(1.0 - dot(nxz, nxz), 0.0)), nxz.y);
	float pc_lo = floor(COLOR.x / 1048576.0);
	float pc_hi = floor(COLOR.y / 1048576.0);
	float pcol = pc_lo + pc_hi * 16.0;          // the painted flower color's palette entry + 1 (0: Auto)
	vec2 ud = unpack2(COLOR.x - pc_lo * 1048576.0);
	vec2 fa = unpack2(COLOR.y - pc_hi * 1048576.0) * TAU;
	vec2 lay = unpack2(COLOR.z) * 2.0 - 1.0;
	vec2 cp = unpack2(COLOR.w);
	float crush = cp.x;
	float push = cp.y;

	// Static bend: downhill, away from the clump centre, as CURVATURE along the blade.
	vec2 bend = gn.xz * downhill_bend + vec2(cos(fa.y), sin(fa.y)) * away_bend * ud.y;
	// Trampling and a rotor's wash lay the blade over about its ROOT, a rigid hinge. Spread along the blade
	// as curvature (a third, two thirds, all of the angle) they would leave an arc standing at its base,
	// which reads as far too timid under a rotor.
	vec2 hinge = vec2(0.0);
	float ll = length(lay);
	if (ll > 1e-3) {
		hinge += lay / ll * (crush * crush_angle + push * push_angle);
	}
	// Wind. TIME is written HERE, inside vertex(), and passed down: that is
	// what gives the sway correct motion vectors. Crushed grass barely moves in the wind.
	float free_ = 1.0 - crush;
	vec2 b1;
	vec2 b2;
	vec2 b3;
	float hb = 0.0;          // how far a heavy flow has moved the lean to the root (0 a breeze .. 1 a hinge)
	vec2 flow_dir = vec2(0.0);   // where the air flows (unit, xz); zero under water
	float up_k = 0.0;        // how much of the rest tilt and curl pointing INTO the flow it blows away, 0..1
	float depth = sea_on ? sea_level - root.y : -1e4;
	if (depth > 0.3) {
		// Under water the sea moves the plant, not the air: the swell's orbital velocity at the bottom
		// (linear wave theory, u_b = H omega / (2 sinh(k h))) bends it along the swell, in phase with the
		// passing wave; the tip lags. No comb, no gust lean, no rotor wash, no TIME sway.
		float ub = swell_h * swell_omega / (2.0 * sinh(swell_k * max(depth, 0.5)));
		float amp = clamp(ub / 0.6, 0.0, 1.2) * resp * free_;
		float ph = swell_k * dot(root.xz, swell_dir) + swell_phase + seed * 0.6;
		v_wash = 0.0;
		b1 = (bend + swell_dir * amp * sin(ph)) / 3.0;
		b2 = (bend + swell_dir * amp * sin(ph - 0.25)) * (2.0 / 3.0);
		b3 = bend + swell_dir * amp * sin(ph - 0.5);
	} else {
		// THE AIR (grass_wind.gdshaderinc): the natural wind and a rotor's wall jet (grass_wash_air) are ONE flow
		// u (m/s). The blade leans with its speed by its species' wind response, saturating; its face turns into
		// it (the comb); the sway and the wash's buffeting ride on top. The wash used to be a separate hinge laid
		// over the wind's bend: the faces stayed combed to the wind, so blades fell over edge-on, and upwind of a
		// rotor the wind curved a blade one way while the wash hinged it the other.
		float g0 = wind_gust(root.xz);               // once: the comb reads the plain gust (not each passing wave)
		float g = clamp(g0 + HONAMI_GAIN * wind_honami(root.xz, TIME), 0.0, 1.0);   // the lean and the sway ride the fine gusts
		vec2 wdir = wind_dir_at(root.xz);
		vec2 jet_u;
		vec2 press;
		float wash_s;
		vec2 wash_d;
		grass_wash_air(root.xz, seed, jet_u, press, wash_s, wash_d);
		vec2 u = wdir * wind_air_speed(g) + jet_u;
		float us = length(u);
		vec2 udir = us > 1e-4 ? u / us : wdir;
		// COMB: turn the blade's face into the flow so it bends along its own face, and the field reads as
		// combed (a rotor's jet combs it outward), not as tufts bending sideways.
		//
		// The turn is a continuous ROTATION toward the flow's AXIS, never a lerp toward +/-udir
		// (wind_comb_turn in grass_wind.gdshaderinc). The lerp snapped blades to a different angle as
		// the gust veered (2026-09-27): the `dot >= 0 ? wdir : -wdir` target flip at face-perpendicular
		// wind, and `normalize(mix(...) + vec2(1e-5, 0))` collapsing to world +X for face-antiparallel
		// blades. Folding to the axis alone kept the first flip (2026-09-28): a curved blade is NOT
		// symmetric under F -> -F (its bend flips with the face), so the turn tapers to zero at the
		// perpendicular instead. It also fades where the flow stills (the wind meeting a jet head-on):
		// the flow's direction is undefined there.
		vec2 f2 = F.xz;
		float fl2 = length(f2);
		f2 = fl2 > 1e-6 ? f2 / fl2 : vec2(1.0, 0.0);
		float cs = dot(f2, udir);
		float sn = f2.x * udir.y - f2.y * udir.x;
		float ang = atan(sn, cs);                    // signed angle f2 -> udir, (-pi, pi]
		// A rigid species (wind response 0) does not turn; from 0.33 up the comb is whole.
		float cmb = clamp(wind_comb_at(g0) + smoothstep(2.0, 10.0, length(jet_u)), 0.0, 1.0) * smoothstep(0.3, 1.5, us)
				* clamp(resp * 3.0, 0.0, 1.0);
		float turn = wind_comb_turn(ang, cmb * free_);
		float ct = cos(turn);
		float st = sin(turn);
		vec2 f2r = vec2(f2.x * ct - f2.y * st, f2.x * st + f2.y * ct);
		F = vec3(f2r.x, 0.0, f2r.y);
		S = vec3(f2r.y, 0.0, -f2r.x);
		// The lean moves toward the ROOT as the load grows: a breeze curves a blade along its length, a gale or a
		// wall jet folds it at the base (a load along a cantilever bends it most at the root). hb 0: a third, two
		// thirds and all of the angle at the control points; hb 1: all of it at each, a hinge.
		// Plus the grass's MEMORY of the air (air_dev, GrassAirField): the lag behind a rising gust, the rebound when
		// it falls away, a patch a rotor held flat creeping back up. Zero in a steady air.
		vec2 lean_v = (wind_lean_vec(u, resp) + air_dev(root.xz) * resp) * free_;
		hb = smoothstep(0.45, 1.2, length(lean_v));
		flow_dir = udir;
		up_k = smoothstep(0.3, 0.9, length(lean_v));
		// The column under the disc presses the blade down about its root; the stiffest species less.
		float rw = clamp(resp * 1.5, 0.0, 1.0);
		hinge += press * rw;
		v_wash = wash_s;
		float th = type_height[ty];
		vec2 wperp = vec2(-wdir.y, wdir.x);
		vec2 bperp = vec2(-wash_d.y, wash_d.x);
		float sr = free_ * resp;
		float br = wash_s * rw * free_;
		vec2 s1 = wind_sway2(root.xz, g, th, seed, 1.0, TIME);
		vec2 s2 = wind_sway2(root.xz, g, th, seed, 2.0, TIME);
		vec2 s3 = wind_sway2(root.xz, g, th, seed, 3.0, TIME);
		vec2 q1 = grass_wash_buffet(seed, 1.0, TIME) * br;
		vec2 q2 = grass_wash_buffet(seed, 2.0, TIME) * br;
		vec2 q3 = grass_wash_buffet(seed, 3.0, TIME) * br;
		b1 = (bend + (wdir * s1.x + wperp * s1.y) * sr + wash_d * q1.x + bperp * q1.y) / 3.0
				+ lean_v * mix(1.0 / 3.0, 1.0, hb);
		b2 = (bend + (wdir * s2.x + wperp * s2.y) * sr + wash_d * q2.x + bperp * q2.y) * (2.0 / 3.0)
				+ lean_v * mix(2.0 / 3.0, 1.0, hb);
		b3 = bend + (wdir * s3.x + wperp * s3.y) * sr + wash_d * q3.x + bperp * q3.y + lean_v;
	}

	// Control points in the blade plane (tilt places the tip, bend lifts the midpoint). A strong flow blows away
	// the part of the rest tilt and of the curl that points INTO it (up_k): the comb turns a face to the flow's
	// axis, so half the blades face upwind, and a blade tilted into a wall jet was only turned back upright (a
	// responsive grass in a rotor's jet ring kept 0.8 of its height, tall spikes standing in the stream).
	// Continuous: only the upwind component goes, by a factor that grows with the load.
	float tilt = shp.x * (0.5 + seed);
	vec2 tv = F.xz * sin(tilt);
	tv -= flow_dir * (min(dot(tv, flow_dir), 0.0) * up_k);
	vec3 tip_dir = normalize(U * cos(tilt) + vec3(tv.x, 0.0, tv.y));
	vec2 cv = F.xz * (H * shp.y * (0.3 + 0.4 * seed));
	cv -= flow_dir * (min(dot(cv, flow_dir), 0.0) * up_k);
	vec3 p0 = root;
	vec3 p1 = root + U * (H / 3.0);
	vec3 p2 = root + U * (H * 0.66) + vec3(cv.x, 0.0, cv.y);
	vec3 p3 = root + tip_dir * H;
	// Rotation about the root keeps each control point's distance: the blade does not stretch. b1..b3 are each
	// point's rotation (direction and angle), already spread along the blade.
	p1 = bend_point(p1, root, b1, min(length(b1), 1.45));
	p2 = bend_point(p2, root, b2, min(length(b2), 1.45));
	p3 = bend_point(p3, root, b3, min(length(b3), 1.45));
	// Then the hinge: every control point about the root by the whole angle (the blade keeps its length).
	float ha = min(length(hinge), 1.45);
	p1 = bend_point(p1, root, hinge, ha);
	p2 = bend_point(p2, root, hinge, ha);
	p3 = bend_point(p3, root, hinge, ha);

	float t = UV.y;
	float side = UV.x - 0.5;
	// HIGH shape at t, and the LOW polyline through the LOW levels (0, lo_u1, lo_u2, 1).
	float a = t < lo_u1 ? 0.0 : (t < lo_u2 ? lo_u1 : lo_u2);
	float b = t < lo_u1 ? lo_u1 : (t < lo_u2 ? lo_u2 : 1.0);
	float s = clamp((t - a) / (b - a), 0.0, 1.0);
	vec3 e_t = bez(p0, p1, p2, p3, t) + S * width_at(W, t, shp) * side;
	vec3 e_a = bez(p0, p1, p2, p3, a) + S * width_at(W, a, shp) * side;
	vec3 e_b = bez(p0, p1, p2, p3, b) + S * width_at(W, b, shp) * side;
	vec3 pos = mix(e_t, mix(e_a, e_b, s), morph);
	// Normal = cross(dB/dt, S): the mesh's front face (BladeMesh test pins the winding).
	vec3 n_t = normalize(cross(dbez(p0, p1, p2, p3, t), S));
	vec3 n_a = normalize(cross(dbez(p0, p1, p2, p3, a), S));
	vec3 n_b = normalize(cross(dbez(p0, p1, p2, p3, b), S));
	vec3 n = normalize(mix(n_t, normalize(mix(n_a, n_b, s)), morph));
	float w_here = mix(width_at(W, t, shp), mix(width_at(W, a, shp), width_at(W, b, shp), s), morph);

	// Edge-on thickening against the MAIN camera; the shadow pass thickens with it.
	vec3 cam = MAIN_CAM_INV_VIEW_MATRIX[3].xyz;
	vec3 cam_right = MAIN_CAM_INV_VIEW_MATRIX[0].xyz;
	vec3 V = normalize(cam - pos);
	float dist = length(cam - root);
	// The flower colour this type's decorations no longer draw here, per blade (grass_handoff.gdshaderinc).
	v_tint = hand_tint(ty, root.xz, dist, pcol);
	v_tint.a *= hand_gain;
	float w_proj = w_here * sqrt(max(1.0 - dot(S, V) * dot(S, V), 0.0));
	float min_w = min_px * dist / px_per_m * (w_here / max(W, 1e-5));
	float extra = max(min_w - w_proj, 0.0) * thicken;
	pos += cam_right * (side * 2.0) * sign(dot(S, cam_right) + 1e-6) * extra * 0.5;

	VERTEX = pos;
	NORMAL = n;
	v_lat = side * w_here;
	v_wid = w_here;
	// The tangent morphs WITH the shape and is orthogonal to the normal, so tangent-space
	// shading sees the same frame on HIGH at morph 1 as on LOW.
	vec3 tan_m = mix(dbez(p0, p1, p2, p3, t), mix(dbez(p0, p1, p2, p3, a), dbez(p0, p1, p2, p3, b), s), morph);
	TANGENT = normalize(tan_m - n * dot(n, tan_m));
	BINORMAL = S;
	v_side = S;
	v_t = t;
	v_u = ud.x;
	v_cdist = ud.y;
	v_dist = dist;
	v_morph = morph;
	v_crush = crush;
	v_ground_n = gn;
	v_look.x = ty_f * 2.0;
	v_ground = ground_colour_at(root.xz);
	v_ground.a = v_ground.a < 0.0 ? 0.0 : type_ground[int(ty_f)];
	v_look.y = look.w;
	v_look.z = look.z;
	v_look.w = look.x;
	v_clump_n = normalize(gn + vec3(cos(fa.x), 0.0, sin(fa.x)) * 0.35);
}

void fragment() {
	// NORMAL already faces the viewer (Godot flips it for back faces). Round it OUTWARD
	// across the width: the side axis sign does not depend on which face we see.
	vec3 side_v = normalize((VIEW_MATRIX * vec4(v_side, 0.0)).xyz);
	// Fraction across the blade from two AFFINE varyings, not UV.x: on a tapering blade the
	// side coordinate x / width(y) is not affine, so interpolating UV.x makes the rounding
	// depend on how the quad was split, and HIGH at morph 1 would shade unlike LOW.
	float across = clamp(v_lat / max(v_wid, 1e-6), -0.5, 0.5) * 2.0;
	float ang = radians(roundness_deg) * across;
	vec3 n = normalize(NORMAL * cos(ang) + side_v * sin(ang));
	// With distance, converge on one normal per clump and lose gloss (a glossy field glitters).
	float conv = 1.0 - exp(-v_dist / normal_converge_m);
	n = normalize(mix(n, normalize((VIEW_MATRIX * vec4(v_clump_n, 0.0)).xyz), conv));
	// Across the outer fade, converge on the ground's normal: blades shade like the ground they sink into.
	float edge = smoothstep(r_edge - edge_fade, r_edge, v_dist);
	n = normalize(mix(n, normalize((VIEW_MATRIX * vec4(v_ground_n, 0.0)).xyz), edge));
	// Near-vertical blades under a high sun catch little light; bend the lighting normal toward
	// world UP, unconditionally: a thin sheet is lit from above whichever face we see. (Bending
	// toward sign(dot(up, n)) x up would flip where n is near horizontal, a discontinuity between
	// HIGH and LOW.) The small up term keeps a face pointing straight down from cancelling to zero.
	vec3 up_v = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	n = normalize(mix(n, up_v, normal_up) + up_v * 1e-3);
	if (debug_view == 2) {
		n = -n;
	}
	NORMAL = n;

	// Colour texture rows are mix(base, tip, v^4) per clump (GrassColour); roots go dark in
	// ALBEDO (it darkens every light, not only ambient: that is where the field's depth comes from).
	vec3 albedo = ground_shift(blade_colour(v_u, v_t, v_look.x, v_look.y));
	albedo = grass_wash_sheen(albedo, v_wash);
	albedo *= mix(1.0, 1.0 - wet_darken, weather_wetness);
	albedo = mix(albedo, snow_tint, snow_coverage * snow_frost);
	albedo *= mix(root_dark, 1.0, v_t * v_t);
	albedo *= 1.0 - 0.25 * v_crush;
	// A pale midrib down the centre line (a silver grass's white vein), gone with distance.
	float rib = v_look.w * (1.0 - smoothstep(0.06, 0.2, abs(across))) * (1.0 - conv);
	albedo = mix(albedo, albedo * 1.8 + vec3(0.05), rib);
	// With distance the field becomes one colour: half-way up the gradient, halved.
	vec3 far_col = ground_shift(blade_colour(v_u, 0.84, v_look.x, v_look.y)) * 0.5;   // 0.84^4 = 0.5
	albedo = mix(albedo, far_col, conv);
	// Flowers sit on the canopy top: tint the upper blade, and all of it once converged.
	float top = mix(smoothstep(0.45, 0.9, v_t), 1.0, conv);
	albedo = mix(albedo, v_tint.rgb, clamp(v_tint.a * top, 0.0, 1.0));
	if (debug_view == 1) {
		albedo = mix(vec3(1.0, 0.1, 0.1), vec3(0.1, 0.2, 1.0), v_morph);
	}
	ALBEDO = albedo;
	// Debug views 3 and 4 compare HIGH at morph 1 with LOW: the lighting normal, the view vector.
	if (debug_view == 3) {     // the lighting normal as colour (world space), unlit
		ALBEDO = vec3(0.0);
		EMISSION = (INV_VIEW_MATRIX * vec4(n, 0.0)).xyz * 0.5 + 0.5;
	}
	if (debug_view == 4) {     // the view vector as colour, unlit
		ALBEDO = vec3(0.0);
		EMISSION = (INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz * 0.5 + 0.5;
	}
	ROUGHNESS = mix(1.0, tip_roughness, 1.0 - pow(1.0 - v_t, 4.0));   // glossier toward the tip
	ROUGHNESS = mix(ROUGHNESS, rough_far, conv);
	ROUGHNESS -= 0.25 * max(v_crush, weather_wetness);   // wet or laid grass is glossier
	SPECULAR = v_look.z * (1.0 - 0.5 * conv);
	// Golden glow when looking toward the sun: max(-V.L, 0) as BACKLIGHT, which Godot multiplies
	// by each light's colour and SHADOW and applies to back-lit faces.
	vec3 sun_v = normalize((VIEW_MATRIX * vec4(sun_travel_dir, 0.0)).xyz);
	float toward_sun = max(dot(VIEW, sun_v), 0.0);
	BACKLIGHT = sss_color * sss_strength * (sss_floor + 0.5 * toward_sun) * smoothstep(0.0, 0.6, v_t);
	if (debug_view == 5) {     // the albedo alone, unlit: no diffuse, specular or glow
		ALBEDO = vec3(0.0);
		EMISSION = albedo;
		SPECULAR = 0.0;
		ROUGHNESS = 1.0;
		BACKLIGHT = vec3(0.0);
	}

	// No ANISOTROPY: merely writing it compiles Godot's anisotropic GGX, whose frame (TANGENT vs
	// BINORMAL = side axis) is not orthonormal once the blade bends out of its plane, and it widens
	// the specular difference between HIGH at morph 1 and LOW. SPECULAR carries the sheen.
}
