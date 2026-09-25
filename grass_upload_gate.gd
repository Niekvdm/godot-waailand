# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name GrassUploadGate
extends RefCounted
## Whether a table the CPU keeps must go (again) to the GPU. A change bumps the generation; the render
## thread confirms the generation it actually uploaded, and until it does every frame sends the latest.
## A frame whose render-thread half returns before its upload (no device yet, the ground not bound) must
## not lose the change, and with a render thread an upload still in flight when the table changes again
## must not mark the newer change done. Pure: no GPU, unit-tested.

var _gen := 1          # bumped by every change; a new gate wants its first upload
var _done := 0         # the generation the GPU last received (written by the render thread)


## The table changed.
func mark() -> void:
	_gen += 1


## The current generation (a consumer on the main thread compares it with the one it last applied).
func latest() -> int:
	return _gen


## The generation to send this frame, or 0 when the GPU already holds the latest.
func pending() -> int:
	return 0 if _done == _gen else _gen


## Render thread: generation `g` is on the GPU.
func uploaded(g: int) -> void:
	_done = maxi(_done, g)
