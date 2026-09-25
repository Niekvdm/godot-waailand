# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name GroundDropTarget
extends PanelContainer
## Where a GroundTile can be dropped in the Ground rules dialog: it takes one drag `kind` and calls `on_drop` with the
## tile's id, wearing `hover` while a tile it takes is over it. A click emits `pressed` (a rule row selects its rule).
## Its children must be MOUSE_FILTER_IGNORE (or PASS): Godot stops looking for a drop target at a STOP control.

signal pressed

var kind := ""                     # "" takes nothing: a clickable panel
var on_drop := Callable()
var _normal: StyleBox = null
var _hover: StyleBox = null


func setup(p_kind: String, p_on_drop: Callable, p_normal: StyleBox, p_hover: StyleBox) -> GroundDropTarget:
	kind = p_kind
	on_drop = p_on_drop
	_normal = p_normal
	_hover = p_hover
	if _normal != null:
		add_theme_stylebox_override("panel", _normal)
	return self


func _can_drop_data(_at: Vector2, p_data: Variant) -> bool:
	var ok: bool = kind != "" and p_data is Dictionary and p_data.get("kind") == kind
	_highlight(ok)
	return ok


func _drop_data(_at: Vector2, p_data: Variant) -> void:
	_highlight(false)
	if on_drop.is_valid():
		on_drop.call(String(p_data["id"]))


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT or what == NOTIFICATION_DRAG_END:
		_highlight(false)


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
		pressed.emit()
		accept_event()


func _highlight(on: bool) -> void:
	if _hover != null and _normal != null:
		add_theme_stylebox_override("panel", _hover if on else _normal)
