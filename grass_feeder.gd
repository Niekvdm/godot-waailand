# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name GrassFeeder
extends Node
## A node that feeds its parent GrassBlades every frame: override
## _feed(dt) and call the blades' input API (set_wind, set_date, add_push and the rest). It runs just before the blades
## (GrassBlades.FEED_PRIORITY). A project lists feeder scripts in GrassBladesConfig.runtime_inputs (the game) or
## editor_inputs (the game and the editor); a feeder placed under a GrassBlades in a scene replaces the config's copy of
## its script. A feeder that runs in the editor needs @tool on its own script too.

## The GrassBlades this feeds: its parent, found when it enters the tree (or set by hand).
var blades: GrassBlades
var _warned := false


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE:
		_find_blades()


## The parent GrassBlades (blades set by hand are kept when the parent is none); the process priority.
func _find_blades() -> void:
	var p := get_parent() as GrassBlades
	if p != null:
		blades = p
	elif blades == null and not _warned:
		_warned = true
		push_warning("GrassFeeder %s: its parent is not a GrassBlades, so it feeds nothing" % name)
	process_priority = GrassBlades.FEED_PRIORITY


func _process(dt: float) -> void:
	if blades != null and is_instance_valid(blades):
		_feed(dt)


## Override: this frame's inputs, through the blades' input API.
func _feed(_dt: float) -> void:
	pass
