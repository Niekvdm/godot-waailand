# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
extends EditorInspectorPlugin
## A species pack's pictures in the inspector: which are missing or stale, and
## a button that renders them in a separate window (GrassPictureTool). Re-open the pack when the window closes to see
## the list update.


func _can_handle(p_object: Object) -> bool:
	return p_object is GrassSpeciesPack


func _parse_begin(p_object: Object) -> void:
	var pack := p_object as GrassSpeciesPack
	var box := VBoxContainer.new()
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var stale := GrassPictureTool.stale_of(pack)
	label.text = "Pictures: all current." if stale.is_empty() else "Pictures missing or stale: %s." % ", ".join(stale)
	box.add_child(label)
	var b := Button.new()
	b.text = "Render missing and stale pictures"
	b.disabled = stale.is_empty() or pack.resource_path == ""
	if pack.resource_path == "":
		b.tooltip_text = "Save the pack as a file first."
	elif stale.is_empty():
		b.tooltip_text = "Nothing to draw."
	else:
		b.tooltip_text = "Opens a separate window that draws them, then closes."
	b.pressed.connect(func() -> void:
		var pid := GrassPictureTool.launch(pack.resource_path)
		label.text = ("Rendering in a separate window (process %d). Re-open the pack when it closes." % pid) if pid > 0 \
			else "The picture tool did not start.")
	box.add_child(b)
	add_custom_control(box)
