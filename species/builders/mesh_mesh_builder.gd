# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name MeshMeshBuilder
extends GrassDecorationMeshBuilder
## Any Mesh as a decoration. It must follow DecoMeshBuilder's format (deco/deco_mesh_builder.gd): its UV channel marks
## flower, stem and leaf, which the decoration shader colours. `low` is the LOW mesh; without one HIGH serves both.

## The HIGH mesh, in DecoMeshBuilder's format.
@export var mesh: Mesh
## The LOW mesh; without one, `mesh` serves both.
@export var low: Mesh


## [HIGH, LOW]: `mesh`, and `low` (or `mesh` again).
func build() -> Array:
	if mesh == null:
		return []
	return [mesh, low if low != null else mesh]
