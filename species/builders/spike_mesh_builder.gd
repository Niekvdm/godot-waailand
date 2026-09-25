# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name SpikeMeshBuilder
extends GrassDecorationMeshBuilder
## A slender flower spike (deco/spike_mesh.gd).

## The stem's height (m) below the spike.
@export var stem_h := 0.3
## The spike's length (m).
@export var spike_len := 0.15
## The spike's width (m).
@export var spike_w := 0.01
## Crossed strips in the spike (it reads as a cylinder from any side).
@export var facets := 3


## This builder as {builder, args}: DecoKinds builds and caches its meshes by it.
func recipe() -> Dictionary:
	return {"builder": "spike", "args": [stem_h, spike_len, spike_w, facets]}
