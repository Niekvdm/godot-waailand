# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name GrassHash
extends RefCounted
## CPU mirror of the placement hash (grass_place_common.glsli: pcg3d, rnd3) and of the palette
## index (grass_palette.gdshaderinc), for tests and tools. BIT-IDENTICAL to the GLSL: unsigned
## 32-bit wrap-around, done in 64-bit ints with the products split so none overflows.

const M := 0xFFFFFFFF


static func _mul(a: int, b: int) -> int:
	return ((a * (b & 0xFFFF)) + (((a * (b >> 16)) & 0xFFFF) << 16)) & M


static func pcg3d(x: int, y: int, z: int) -> Array:
	x = (_mul(x & M, 1664525) + 1013904223) & M
	y = (_mul(y & M, 1664525) + 1013904223) & M
	z = (_mul(z & M, 1664525) + 1013904223) & M
	x = (x + _mul(y, z)) & M
	y = (y + _mul(z, x)) & M
	z = (z + _mul(x, y)) & M
	x ^= x >> 16
	y ^= y >> 16
	z ^= z >> 16
	x = (x + _mul(y, z)) & M
	y = (y + _mul(z, x)) & M
	z = (z + _mul(x, y)) & M
	return [x, y, z]


static func rnd3(cell: Vector2i, stream: int) -> Vector3:
	var h := pcg3d(cell.x, cell.y, stream)
	return Vector3(h[0] >> 8, h[1] >> 8, h[2] >> 8) / 16777216.0


## The palette entry at xz: one per `cell` rectangle (stream 9 + salt), identical to
## grass_palette.gdshaderinc, which the decorations, the blade handoff and the far field use.
static func palette_index(xz: Vector2, cell: Vector2, n: int, salt: int) -> int:
	var c := Vector2i(floori(xz.x / cell.x), floori(xz.y / cell.y))
	var h := pcg3d(c.x, c.y, 9 + salt)
	return mini(int(floor(float(h[0] >> 8) / 16777216.0 * n)), n - 1)
