// Copyright (c) 2026 Digitzone
// SPDX-License-Identifier: MIT
// The grass's memory of the air (GrassAirField): how far the lean a patch carries differs from the equilibrium of
// the air it stands in now (a plant of wind response 1). The blades and the flowers add it, by their response, to
// their stateless lean: the lag behind a rising gust, the rebound when it falls away, a patch a rotor laid flat
// creeping back up. Zero in a steady air, and outside the camera's window (it fades out toward the window's edge).
// Its own file, not grass_wind.gdshaderinc: a terrain shader includes the wind (the far field's gusts) and should
// not carry two more samplers.

#ifndef GRASS_AIR_INC
#define GRASS_AIR_INC

uniform sampler2D air_state : filter_linear, repeat_enable;   // GrassAirField: RG the lean (rad), BA its rate
uniform sampler2D air_eq : filter_linear, repeat_enable;      // GrassAirField: RG the air's equilibrium lean
uniform vec4 air_window = vec4(0.0);   // xy the window's centre (world xz), z its side (m), w 1 when live

vec2 air_dev(vec2 xz) {
	if (air_window.w < 0.5) {
		return vec2(0.0);
	}
	vec2 uv = xz / air_window.z;       // toroidal: world cell w sits at texel w mod n, and the samplers repeat
	vec2 dev = texture(air_state, uv).xy - texture(air_eq, uv).xy;
	vec2 off = abs(xz - air_window.xy) / air_window.z;
	return dev * (1.0 - smoothstep(0.38, 0.48, max(off.x, off.y)));
}

#endif
