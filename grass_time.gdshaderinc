// Copyright (c) 2026 Digitzone
// SPDX-License-Identifier: MIT
// TIME rolls over (rendering/limits/time/time_rollover_secs, 3600 s by default): at the wrap, sin(TIME x TAU x f)
// jumps unless f fits a whole number of cycles into the rollover, and every plant's sway and buffeting jumped once
// an hour. rollover_hz moves a frequency to the nearest one that does (by under 1 / (2 x rollover) Hz, far below
// what anyone sees). The wind (grass_wind.gdshaderinc) and the downwash (grass_downwash.gdshaderinc) both include
// this; GrassWindState sends the project's rollover.

#ifndef GRASS_TIME_INC
#define GRASS_TIME_INC

uniform float waailand_time_rollover = 3600.0;

float rollover_hz(float hz) {
	return round(hz * waailand_time_rollover) / waailand_time_rollover;
}

#endif
