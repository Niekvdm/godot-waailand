# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name GrassSpeciesPack
extends Resource
## A pack of grass species: the species, the one a forced texel or a road's
## verge grows where the mix can't (the fallback), and what a ground with no rule grows (the default mix). A project
## lists its packs in GrassBladesConfig.packs, or installs one as a pack addon (res://addons/<name>/waailand_pack.tres).

## The pack's name.
@export var name := ""
## Its species, in the order the library lists them.
@export var species: Array[GrassSpecies] = []
## Grows where the ground's mix can't (a forced texel), along live roads' verges, and for a stray index.
@export var fallback_species: StringName = &""
## What a ground with no rule grows: {species id: weight}.
@export var default_mix: Dictionary = {}
## The pictures' ground: a Terrain3DAssets whose texture named like the ground a species grows on most dresses its
## patch. None, or no such texture: a plain soil colour.
@export var picture_ground: Resource
## The picture_ground texture a species that no ground grows stands on. Empty, or no such texture: the plain colour.
@export var picture_default_ground := ""
## The pictures' terrain material (a Terrain3DMaterial, copied for each picture). None: Terrain3D's own.
@export var picture_material: Resource
## The pictures' sky and light: a scene instanced for each picture (its first DirectionalLight3D is the sun). None: a
## neutral sky and sun. A clock in it should be stopped, or the light moves between pictures.
@export var picture_environment: PackedScene
