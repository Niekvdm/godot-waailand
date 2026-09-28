// Copyright (c) 2026 Digitzone
// SPDX-License-Identifier: MIT
shader_type spatial;
// A decoration (a flower, a plume, a spike) from its kind's mesh (HIGH or LOW, built by the kind's
// mesh builder) and its instance (deco_place.glsl):
//   transform  root + yaw x uniform scale s
//   COLOR      pack2(seed, 0), pack2(lay dir), pack2(crush, push), pack2(morph, 0)
//   CUSTOM     s, grow, the painted palette entry + 1 (0: the field's own stripes), 0
// Mesh: UV = (part, along the part); CUSTOM0 = (LOW position, HIGH wind weight), CUSTOM1 =
// (LOW normal, LOW wind weight), in model space. The blades' rules hold: no light(), no ALPHA,
// Godot flips NORMAL for back faces itself, TIME written HERE in vertex() for motion vectors.
render_mode cull_disabled, world_vertex_coords, depth_draw_opaque;
#include "res://addons/waailand/grass_wind.gdshaderinc"
#include "res://addons/waailand/grass_wash.gdshaderinc"   // the two-slot downwash (a game can share it with its other surfaces)
#include "res://addons/waailand/grass_palette.gdshaderinc"

uniform vec3 pal[6];                  // today's palette (linear; DecorationStreams.set_day)
uniform float pal_n = 1.0;
uniform vec2 pal_cell = vec2(1000.0);
uniform float kind_salt = 0.0;
uniform vec3 stem_col = vec3(0.1, 0.2, 0.05);
uniform vec4 centre_col = vec4(0.0);  // a > 0: throats/anthers, and the lily's gold band
uniform float backlight = 0.5;
uniform float flutter = 0.0;          // plumes: extra fast flutter of the head
uniform float wind_response = 1.0;
uniform float crush_angle = 1.2;
uniform float hinge_response = 1.0;   // the root hinge (rotor wash, trail crush and push): 0 = rigid (corals)
uniform float specular_val = 0.3;
uniform vec3 sss_color : source_color = vec3(1.0, 0.75, 0.1);
uniform vec3 sun_travel_dir = vec3(0.0, -1.0, 0.0);
uniform int debug_view = 0;           // 1: morph as colour

varying vec2 v_part;
varying float v_morph;
varying flat float v_pal;

vec2 unpack2(float v) {
	float a = floor(v / 1024.0);
	return vec2(a, v - a * 1024.0) / 1023.0;
}

vec3 rotate_about(vec3 v, vec3 axis, float ang) {
	float c = cos(ang);
	float s = sin(ang);
	return v * c + cross(axis, v) * s + axis * dot(axis, v) * (1.0 - c);
}

void vertex() {
	// world_vertex_coords: VERTEX and NORMAL arrive in WORLD space; CUSTOM0/1 are model space.
	vec3 root = MODEL_MATRIX[3].xyz;
	float morph = unpack2(COLOR.w).x;
	float seed = unpack2(COLOR.x).x;
	vec2 lay = unpack2(COLOR.y) * 2.0 - 1.0;
	vec2 cp = unpack2(COLOR.z);
	float crush = cp.x;
	float push = cp.y;
	vec3 pos = mix(VERTEX, (MODEL_MATRIX * vec4(CUSTOM0.xyz, 1.0)).xyz, morph);
	vec3 n = normalize(mix(NORMAL, normalize(MODEL_NORMAL_MATRIX * CUSTOM1.xyz), morph));
	float w = mix(CUSTOM0.w, CUSTOM1.w, morph);     // 0 at the root .. 1 at the top
	float s = INSTANCE_CUSTOM.x;
	// THE AIR (grass_wind.gdshaderinc), as the blades take it: the natural wind and a rotor's wall jet are one flow,
	// and the plant leans with it (0.6 of a blade, by its wind response). The column under a rotor, the crush and
	// the push lay it over about its ROOT, a rigid hinge, as the blades do (spread up the stem, they would leave it
	// standing). hinge_response 0 (corals, floating leaves: no stem to lay over) keeps the rotor out entirely.
	float free_ = 1.0 - crush;
	float g = wind_gust(root.xz);
	vec2 wdir = wind_dir_at(root.xz);
	vec2 jet_u;
	vec2 press;
	float wash_s;
	vec2 wash_d;
	grass_wash_air(root.xz, seed, jet_u, press, wash_s, wash_d);
	vec2 u = wdir * wind_air_speed(g) + jet_u * hinge_response;
	vec2 hinge = press;
	float ll = length(lay);
	if (ll > 1e-3) {
		hinge += lay / ll * (crush * crush_angle + push * 0.6);
	}
	hinge *= hinge_response;
	// The sway along (and a little across) the local wind, weighted up the stem so it curves; plumes flutter faster
	// at the head, as much as the air moves them (still air, still plumes: the flutter ran in a calm); the wash
	// buffets. TIME is written HERE (motion vectors).
	float lag = 1.0 + 2.0 * w;
	vec2 sw = wind_sway2(root.xz, g, 0.5, seed, lag, TIME);   // a fixed height: the scale grows in
	float air = clamp(length(u) / 4.0, 0.0, 2.0);
	float fl = flutter * 0.15 * air * sin(TIME * TAU * rollover_hz(7.0 / TAU) + seed * 20.0 + w * 3.0) * w * w;
	vec2 bf = grass_wash_buffet(seed, lag, TIME) * (wash_s * hinge_response);
	vec2 bend = wind_lean_vec(u, wind_response * 0.6) * free_
			+ (wdir * (sw.x + fl) + vec2(-wdir.y, wdir.x) * sw.y) * (free_ * wind_response)
			+ (wash_d * bf.x + vec2(-wash_d.y, wash_d.x) * bf.y) * free_;
	float bl = length(bend);
	if (bl > 1e-4) {
		vec3 axis = normalize(cross(vec3(0.0, 1.0, 0.0), vec3(bend.x, 0.0, bend.y) / bl));
		float ang = min(bl, 1.4) * w;
		pos = root + rotate_about(pos - root, axis, ang);
		n = rotate_about(n, axis, ang);
	}
	float ha = min(length(hinge), 1.4);
	if (ha > 1e-4) {
		vec3 hax = normalize(cross(vec3(0.0, 1.0, 0.0), vec3(hinge.x, 0.0, hinge.y) / length(hinge)));
		pos = root + rotate_about(pos - root, hax, ha);
		n = rotate_about(n, hax, ha);
	}
	VERTEX = pos;
	NORMAL = n;
	v_part = UV;
	v_morph = morph;
	// A painted color (INSTANCE_CUSTOM.z: palette entry + 1, deco_place.glsl), else the field's own stripes.
	v_pal = INSTANCE_CUSTOM.z > 0.5 ? mod(INSTANCE_CUSTOM.z - 1.0, pal_n) : palette_index(root.xz, pal_cell, pal_n, kind_salt);
}

void fragment() {
	vec3 col;
	if (v_part.x < 0.5) {
		col = stem_col * mix(0.45, 1.0, v_part.y);
	} else if (v_part.x < 1.5) {
		col = pal[int(v_pal)];
		if (centre_col.a > 0.0) {
			col = mix(centre_col.rgb, col, smoothstep(0.1, 0.4, v_part.y));
		}
	} else {
		col = centre_col.rgb;
	}
	if (debug_view == 1) {
		col = mix(vec3(1.0, 0.1, 0.1), vec3(0.1, 0.2, 1.0), v_morph);
	}
	ALBEDO = col;
	ROUGHNESS = 0.7;
	SPECULAR = specular_val;
	// Translucent petals and plumes glow when the camera looks toward the sun (the blades' term).
	vec3 sun_v = normalize((VIEW_MATRIX * vec4(sun_travel_dir, 0.0)).xyz);
	float toward_sun = max(dot(VIEW, sun_v), 0.0);
	BACKLIGHT = mix(col, sss_color, 0.3) * backlight * (0.3 + 0.7 * toward_sun) * step(0.5, v_part.x);
}
