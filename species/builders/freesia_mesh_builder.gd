# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name FreesiaMeshBuilder
extends GrassDecorationMeshBuilder
## Arching spikes of funnel flowers (deco/freesia_mesh.gd).

## The stem's height (m) before it arches over.
@export var stem_h := 0.4
## The arch's length (m).
@export var arch_len := 0.14
## Flowers on each spike's upper side, largest first.
@export var flowers := 6
## The largest flower's radius (m); the others shrink along the arch.
@export var flower_r := 0.035
## Petals per flower.
@export var petals := 5
## Spikes per plant (a real freesia carries two or three).
@export var spikes := 2


## This builder as {builder, args}: DecoKinds builds and caches its meshes by it.
func recipe() -> Dictionary:
	return {"builder": "freesia", "args": [stem_h, arch_len, flowers, flower_r, petals, spikes]}
