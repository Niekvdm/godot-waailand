#[compute]
#version 450
// Copyright (c) 2026 Digitzone
// SPDX-License-Identifier: MIT

// One lane: copies this frame's per-bin counts (clamped to capacity) into word 1 of each
// indirect draw command, the only word Godot leaves to us (it fills in the index count at
// set_mesh time); publishes the stats for readback; zeroes the counters for the next frame.

layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) restrict buffer Counters { uint n[4]; } C;
layout(set = 0, binding = 1, std430) restrict buffer CmdHi { uint c[]; } cmd_hi;
layout(set = 0, binding = 2, std430) restrict buffer CmdLo { uint c[]; } cmd_lo;
layout(set = 0, binding = 3, std430) restrict buffer CmdSh { uint c[]; } cmd_sh;
layout(set = 0, binding = 4, std430) restrict writeonly buffer Stats { uint s[4]; } S;

layout(push_constant, std430) uniform Push { uint cap_hi; uint cap_lo; uint cap_sh; uint pad; } pc;

void main() {
	uint hi = min(C.n[0], pc.cap_hi);
	uint lo = min(C.n[1], pc.cap_lo);
	uint sh = min(C.n[2], pc.cap_sh);
	cmd_hi.c[1] = hi;
	cmd_lo.c[1] = lo;
	cmd_sh.c[1] = sh;
	S.s[0] = hi;
	S.s[1] = lo;
	S.s[2] = sh;
	S.s[3] = C.n[3];
	C.n[0] = 0u;
	C.n[1] = 0u;
	C.n[2] = 0u;
	C.n[3] = 0u;
}
