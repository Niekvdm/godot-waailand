# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name LycorisMeshBuilder
extends GrassDecorationMeshBuilder
## A spider lily's umbel of curled tepals and long stamens (deco/lycoris_mesh.gd).

## The bare scape's height (m).
@export var scape_h := 0.4
## Flowers in the umbel.
@export var flowers := 5
## A tepal's length (m).
@export var tepal_len := 0.045
## A stamen's length (m).
@export var stamen_len := 0.075


## This builder as {builder, args}: DecoKinds builds and caches its meshes by it.
func recipe() -> Dictionary:
	return {"builder": "lycoris", "args": [scape_h, flowers, tepal_len, stamen_len]}
