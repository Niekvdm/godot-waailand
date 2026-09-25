# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name LilyMeshBuilder
extends GrassDecorationMeshBuilder
## Lily trumpets on a leafy stem (deco/lily_mesh.gd).

## The stem's height (m).
@export var stem_h := 0.5
## Trumpets at the top of the stem.
@export var flowers := 3
## A tepal's length (m).
@export var tepal_len := 0.035
## A tepal's width (m).
@export var tepal_w := 0.012
## 0 faces the trumpets up; about 0.85 turns them out sideways.
@export var nod := 0.0


## This builder as {builder, args}: DecoKinds builds and caches its meshes by it.
func recipe() -> Dictionary:
	return {"builder": "lily", "args": [stem_h, flowers, tepal_len, tepal_w, nod]}
