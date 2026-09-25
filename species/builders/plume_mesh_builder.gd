# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name PlumeMeshBuilder
extends GrassDecorationMeshBuilder
## A plume of strands (deco/plume_mesh.gd): silver grass heads, reed tassels. Lengths are in host heights: 1 is the
## top of the host tussock.

## Racemes in the plume.
@export var strands := 12
## The plume's length above the tussock (host heights).
@export var head_len := 0.28
## How far the strands spread (host heights).
@export var spread := 0.12
## How far the strands droop at their ends (host heights).
@export var droop := 0.1
## A strand's width at its base (host heights).
@export var strand_w := 0.006
## LOW keeps every lo_every-th strand, widened.
@export var lo_every := 3


## This builder as {builder, args}: DecoKinds builds and caches its meshes by it.
func recipe() -> Dictionary:
	return {"builder": "plume", "args": [strands, head_len, spread, droop, strand_w, lo_every]}
