# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name CoralMeshBuilder
extends GrassDecorationMeshBuilder
## A hard coral colony at unit size (deco/coral_mesh.gd): table, branching or boulder.

## The colony's form: a table (a plate on a stalk), branching (staghorn limbs) or a boulder (a lumpy dome).
@export_enum("table", "branching", "boulder") var form := "table"


## This builder as {builder, args}: DecoKinds builds and caches its meshes by it.
func recipe() -> Dictionary:
	return {"builder": "coral", "args": [form]}
