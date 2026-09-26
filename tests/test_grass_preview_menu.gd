# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
class_name TestGrassPreviewMenu
extends GrassSuite
## The 3D editor's "Grass" menu: it shows and sets GrassEditorPreview and
## tells the plugin to keep each change.


static func run() -> Dictionary:
	return await GrassSuite.run_suite(TestGrassPreviewMenu.new(), "grass_preview_menu")


func test_the_menu_drives_the_preview() -> void:
	var keep_day := GrassEditorPreview.day
	var keep_vis := GrassEditorPreview.visible
	GrassEditorPreview.day = GrassEditorPreview.DEFAULT_DAY
	GrassEditorPreview.visible = true
	var m := GrassPreviewMenu.new()
	var fired := [0]
	m.changed.connect(func(): fired[0] += 1)
	var p := m.get_popup()
	assert_true(p.is_item_checked(p.get_item_index(GrassPreviewMenu.ID_SHOW)), "shows the grass by default")
	assert_true(p.is_item_checked(p.get_item_index(GrassPreviewMenu.ID_DAY0 + 3)), "15 April is the default date")
	m._on_id(GrassPreviewMenu.ID_DAY0 + 8)
	assert_near(GrassEditorPreview.day, 257.0, 1e-6, "picking 15 September sets the date")
	assert_true(p.is_item_checked(p.get_item_index(GrassPreviewMenu.ID_DAY0 + 8))
		and not p.is_item_checked(p.get_item_index(GrassPreviewMenu.ID_DAY0 + 3)), "and moves the check")
	m._on_id(GrassPreviewMenu.ID_SHOW)
	assert_true(not GrassEditorPreview.visible, "the check hides the grass")
	assert_eq(fired[0], 2, "each change tells the plugin")
	m._on_id(9999)
	assert_eq(fired[0], 2, "an unknown id changes nothing")
	m.free()
	GrassEditorPreview.day = keep_day
	GrassEditorPreview.visible = keep_vis


## "Grow on every ground": a check item that flips the preview's
## every-ground switch and tells the plugin to keep it.
func test_the_every_ground_switch() -> void:
	var keep := GrassEditorPreview.all_grounds
	GrassEditorPreview.all_grounds = false
	var m := GrassPreviewMenu.new()
	var fired := [0]
	m.changed.connect(func(): fired[0] += 1)
	var p := m.get_popup()
	assert_true(p.get_item_index(GrassPreviewMenu.ID_ALL_GROUNDS) >= 0
		and not p.is_item_checked(p.get_item_index(GrassPreviewMenu.ID_ALL_GROUNDS)), "the item, off by default")
	m._on_id(GrassPreviewMenu.ID_ALL_GROUNDS)
	assert_true(GrassEditorPreview.all_grounds and p.is_item_checked(p.get_item_index(GrassPreviewMenu.ID_ALL_GROUNDS))
		and fired[0] == 1, "it flips the switch, checks itself and tells the plugin")
	m.free()
	GrassEditorPreview.all_grounds = keep


## "Paint overlay": the overlay can be switched off (and on, in its last mode) outside the Grass workspace, whose view
## strip holds its modes.
func test_the_overlay_switch() -> void:
	var keep := [GrassEditorPreview.overlay, GrassEditorPreview.overlay_mode]
	GrassEditorPreview.overlay = GrassOverlay.Mode.OFF
	GrassEditorPreview.overlay_mode = GrassOverlay.Mode.HEIGHT
	var m := GrassPreviewMenu.new()
	var fired := [0]
	m.changed.connect(func(): fired[0] += 1)
	var p := m.get_popup()
	var i := p.get_item_index(GrassPreviewMenu.ID_OVERLAY)
	assert_true(i >= 0 and not p.is_item_checked(i), "the item, off by default")
	m._on_id(GrassPreviewMenu.ID_OVERLAY)
	assert_true(GrassEditorPreview.overlay == GrassOverlay.Mode.HEIGHT and p.is_item_checked(i) and fired[0] == 1,
		"on in its last mode, checked, the plugin told")
	m._on_id(GrassPreviewMenu.ID_OVERLAY)
	assert_eq(GrassEditorPreview.overlay, GrassOverlay.Mode.OFF, "and off")
	m.free()
	GrassEditorPreview.overlay = keep[0]
	GrassEditorPreview.overlay_mode = keep[1]
