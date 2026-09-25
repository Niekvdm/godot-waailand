// Copyright (c) 2026 Digitzone
// SPDX-License-Identifier: MIT
// THE TERRAIN'S COLOUR AT A POINT, as the terrain shader textures it: grass blades take the colour
// of the ground they stand on. The control word at the nearest vertex (Terrain3D's get_index_coord and
// decode) → mix(slot mean[base], slot mean[overlay], blend); a slot's mean is the smallest mip of
// Terrain3D's albedo array (source_color: linear, as the terrain shader samples it) times the slot's
// _texture_color_array tint (what Terrain3D multiplies). GrassBlades feeds every uniform by RID.

uniform int ground_region_map[1024];
uniform int ground_region_map_size = 32;
uniform float ground_region_size = 1024.0;
uniform float ground_vertex_spacing = 1.0;
uniform highp sampler2DArray ground_control_maps : repeat_disable;
uniform sampler2DArray ground_albedo : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 ground_tint[32];

vec3 ground_slot_mean(int id) {
	return textureLod(ground_albedo, vec3(0.5, 0.5, float(id)), 14.0).rgb * ground_tint[id].rgb;
}

// rgb = the ground's linear colour at world xz; a = 1, or -1 where no region is loaded.
vec4 ground_colour_at(vec2 xz) {
	vec2 uv = round(xz / ground_vertex_spacing);
	ivec2 pos = ivec2(floor(uv / ground_region_size)) + ground_region_map_size / 2;
	if (any(lessThan(pos, ivec2(0))) || any(greaterThanEqual(pos, ivec2(ground_region_map_size)))) {
		return vec4(0.0, 0.0, 0.0, -1.0);
	}
	int layer = ground_region_map[pos.y * ground_region_map_size + pos.x] - 1;
	if (layer < 0) {
		return vec4(0.0, 0.0, 0.0, -1.0);
	}
	uint c = floatBitsToUint(texelFetch(ground_control_maps, ivec3(ivec2(mod(uv, ground_region_size)), layer), 0).r);
	vec3 col = mix(ground_slot_mean(int(c >> 27u & 0x1Fu)), ground_slot_mean(int(c >> 22u & 0x1Fu)),
		float(c >> 14u & 0xFFu) * (1.0 / 255.0));
	return vec4(col, 1.0);
}
