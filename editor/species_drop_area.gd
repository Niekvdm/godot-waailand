# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name GrassSpeciesDropArea
extends PanelContainer
## Where the Species dialog takes a drop: the slot grid (a species or a pack, onto its free space) and the library (a
## slot dragged out). It takes the drag kinds it lists and calls `on_drop` with the whole drag data, wearing `hover`
## while a drag it takes is over it. Its children must be MOUSE_FILTER_IGNORE or PASS: Godot stops looking for a drop
## target at a STOP control.

var kinds := PackedStringArray()
var on_drop := Callable()          # (data: Dictionary) -> void
var _normal: StyleBox = null
var _hover: StyleBox = null


func setup(p_kinds: PackedStringArray, p_on_drop: Callable, p_normal: StyleBox, p_hover: StyleBox) \
		-> GrassSpeciesDropArea:
	kinds = p_kinds
	on_drop = p_on_drop
	_normal = p_normal
	_hover = p_hover
	if _normal != null:
		add_theme_stylebox_override("panel", _normal)
	return self


func _can_drop_data(_at: Vector2, p_data: Variant) -> bool:
	var ok: bool = p_data is Dictionary and kinds.has(String(p_data.get("kind", "")))
	_highlight(ok)
	return ok


func _drop_data(_at: Vector2, p_data: Variant) -> void:
	_highlight(false)
	if on_drop.is_valid():
		on_drop.call(p_data)


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT or what == NOTIFICATION_DRAG_END:
		_highlight(false)


func _highlight(on: bool) -> void:
	if _hover != null and _normal != null:
		add_theme_stylebox_override("panel", _hover if on else _normal)
