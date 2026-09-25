# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name GrassDecorationMeshBuilder
extends Resource
## A decoration's mesh. Extend it to bring your own shape: build() returns
## [HIGH ArrayMesh, LOW ArrayMesh] in DecoMeshBuilder's format (deco/deco_mesh_builder.gd: the UV channel marks
## flower, stem and leaf). The built-in builders also give a recipe(), which DecoKinds builds and caches by.


## The HIGH and LOW meshes.
func build() -> Array:
	var r := recipe()
	return DecoKinds._build_mesh(r) if not r.is_empty() else []


## A built-in builder's recipe, {builder, args}; {} for a custom one.
func recipe() -> Dictionary:
	return {}
