# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name GrassPackSet
extends Resource
## A pack addon's index: the packs one addon ships. Waailand finds it at res://addons/<name>/waailand_packs.tres
## without the project listing it (GrassBladesConfig.resolved_packs). One pack or many, each its own GrassSpeciesPack
## file in its own folder, so each keeps its own pictures.

## The set's name.
@export var name := ""
## The packs, in the order they are used.
@export var packs: Array[GrassSpeciesPack] = []
