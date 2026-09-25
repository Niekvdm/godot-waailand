# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name IsogikuMeshBuilder
extends GrassDecorationMeshBuilder
## Flat-topped heads on stalks (deco/isogiku_mesh.gd): daisies, umbels.

## Heads per plant.
@export var heads := 5
## The stalks' height (m).
@export var stalk_h := 0.3
## How far the heads spread from the plant's centre (m).
@export var spread := 0.12
## A head's radius (m).
@export var head_r := 0.012
## A head's sides: a low dome with this many.
@export var sides := 6


## This builder as {builder, args}: DecoKinds builds and caches its meshes by it.
func recipe() -> Dictionary:
	return {"builder": "isogiku", "args": [heads, stalk_h, spread, head_r, sides]}
