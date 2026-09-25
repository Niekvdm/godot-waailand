# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name GrassColour
extends RefCounted
## The blade colour array, one pair of layers per type slot: layer 2i
## is slot i's base colour, 2i+1 its seasonal accent (GrassTypes). In a layer V runs along the
## blade (row 0 = base, row 63 = tip) and U is the clump's hash. Authored in sRGB; the shaders
## sample with source_color, so lighting sees linear values. Rows come from the species packs
## (GrassTypes).

const W := 16
const H := 64


static func layer(r: Dictionary, accent: bool) -> Image:
	var img := Image.create_empty(W, H, false, Image.FORMAT_RGBA8)
	var ta: Color = r.get("accent_tip_a", r["tip_a"]) if accent else r["tip_a"]
	var tb: Color = r.get("accent_tip_b", r["tip_b"]) if accent else r["tip_b"]
	var p: float = r["tip_pow"]
	for x in W:
		var u := float(x) / (W - 1)
		var base: Color = (r["base_a"] as Color).lerp(r["base_b"], u)
		var tip: Color = ta.lerp(tb, u)
		for y in H:
			var v := float(y) / (H - 1)
			img.set_pixel(x, y, base.lerp(tip, pow(v, p)))
	return img


## A blade's colour at u (across the clump's hash) and v (0 base, 1 tip) with its accent layer blended in by `accent`
## (0..1), as the blade shader samples the array (grass_blade.gdshader blade_colour): sRGB.
static func at(r: Dictionary, u: float, v: float, accent: float) -> Color:
	var w := pow(v, float(r["tip_pow"]))
	var base: Color = (r["base_a"] as Color).lerp(r["base_b"], u)
	var tip: Color = (r["tip_a"] as Color).lerp(r["tip_b"], u)
	var atip: Color = (r.get("accent_tip_a", r["tip_a"]) as Color).lerp(r.get("accent_tip_b", r["tip_b"]), u)
	return base.lerp(tip, w).lerp(base.lerp(atip, w), accent)


static func build(types: GrassTypes) -> Texture2DArray:
	var imgs: Array[Image] = []
	for i in GrassTypes.SLOTS:
		var r := types.row(i)
		imgs.append(layer(r, false))
		imgs.append(layer(r, true))
	var arr := Texture2DArray.new()
	arr.create_from_images(imgs)
	return arr


## Each slot's mean LINEAR luminance over its base layer (all u, v): the blade shader moves a blade's
## colour toward the ground's scaled by luma / this mean, which keeps the type's base→tip gradient.
static func mean_luma(types: GrassTypes) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(GrassTypes.SLOTS)
	for i in GrassTypes.SLOTS:
		var img := layer(types.row(i), false)
		var s := 0.0
		for y in H:
			for x in W:
				var c := img.get_pixel(x, y).srgb_to_linear()
				s += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
		out[i] = s / (W * H)
	return out
