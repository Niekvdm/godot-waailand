# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name GrassPreviewMenu
extends MenuButton
## The 3D editor's "Grass" menu: show or hide the grass preview, grow it on every ground, switch the paint overlay (in
## its last mode) and pick the date it shows (the 15th of each month). Writes GrassEditorPreview;
## `changed` tells the plugin to keep it in the project metadata. The Grass workspace's panel adds the season chips
## and a continuous date slider.

signal changed

const ID_SHOW := 0
const ID_ALL_GROUNDS := 1
const ID_OVERLAY := 2
const ID_DAY0 := 100            # + month 0..11
## The 15th of each month as a day of the year (0 = 1 January, 365-day year).
const DAYS := [14.0, 45.0, 73.0, 104.0, 134.0, 165.0, 195.0, 226.0, 257.0, 287.0, 318.0, 348.0]


func _init() -> void:
	text = "Grass"
	tooltip_text = "The grass preview in the editor (Waailand)"
	flat = true
	var p := get_popup()
	p.add_check_item("Show grass", ID_SHOW)
	p.add_check_item("Grow on every ground (preview)", ID_ALL_GROUNDS)
	p.add_check_item("Paint overlay", ID_OVERLAY)
	p.add_separator("Preview date")
	for i in DAYS.size():
		p.add_radio_check_item(GrassSeason.label(DAYS[i]), ID_DAY0 + i)
	p.id_pressed.connect(_on_id)
	sync()


## The menu's checks from GrassEditorPreview.
func sync() -> void:
	var p := get_popup()
	p.set_item_checked(p.get_item_index(ID_SHOW), GrassEditorPreview.visible)
	p.set_item_checked(p.get_item_index(ID_ALL_GROUNDS), GrassEditorPreview.all_grounds)
	p.set_item_checked(p.get_item_index(ID_OVERLAY), GrassEditorPreview.overlay != GrassOverlay.Mode.OFF)
	for i in DAYS.size():
		p.set_item_checked(p.get_item_index(ID_DAY0 + i), is_equal_approx(float(DAYS[i]), GrassEditorPreview.day))


func _on_id(id: int) -> void:
	if id == ID_SHOW:
		GrassEditorPreview.visible = not GrassEditorPreview.visible
	elif id == ID_ALL_GROUNDS:
		GrassEditorPreview.all_grounds = not GrassEditorPreview.all_grounds
	elif id == ID_OVERLAY:
		var off := GrassEditorPreview.overlay != GrassOverlay.Mode.OFF
		GrassEditorPreview.overlay = GrassOverlay.Mode.OFF if off else GrassEditorPreview.overlay_mode
	elif id >= ID_DAY0 and id < ID_DAY0 + DAYS.size():
		GrassEditorPreview.day = float(DAYS[id - ID_DAY0])
	else:
		return
	sync()
	changed.emit()
