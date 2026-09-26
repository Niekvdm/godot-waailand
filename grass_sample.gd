# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name GrassSample
extends RefCounted
## What grows at a point on the ground (GrassBlades.sample).

## The species the blades pick there; &"" when nothing grows.
var species: StringName = &""
## 0: nothing grows; 1: the species at its full density (the grass map may double it).
var density := 0.0
## Its blade height today (m), before each blade's own jitter.
var height_m := 0.0
## The blades' colour today, mid-blade, with the seasonal accent blended in (sRGB).
var colour := Color(0.0, 0.0, 0.0, 0.0)
## The flower kind the species hosts that is in bloom today; &"" when none.
var flower: StringName = &""
## That flower's palette colour at this point (sRGB); alpha 0 when there is none.
var flower_colour := Color(0.0, 0.0, 0.0, 0.0)
## The grass map forces this texel's grass (it grows whatever the ground).
var forced := false
## On a live road's surface.
var on_road := false
## The region's grass map is still loading for the queries: the point reads as unpainted until it arrives.
var pending := false
## The water surface the species floats on (GrassBlades.sample_water; NAN from the ground layer's sample).
var surface_m := NAN
## The grass map removed the grass here (the Paint tool with Ctrl): nothing grows, the ground's own included.
var removed := false
## The species comes from the grass map (painted), not from the ground's own mix.
var painted := false
## The painted flower color's palette entry; -1 for Auto (the field's own stripes).
var color_entry := -1
