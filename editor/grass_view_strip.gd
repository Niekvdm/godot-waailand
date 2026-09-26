# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name GrassViewStrip
extends HBoxContainer
## The Grass workspace's view strip (Terrain3D Extended's strip at the top of the 3D view, provider build_view): the
## eye (show grass), the year (GrassYearTrack: drag, or a month letter), the date, In bloom (the selected species in
## flower), every ground, and Inspect (ⓘ: the brush chip reads what grows under the cursor, and why). It sets what the
## preview shows (GrassEditorPreview), never what a stroke paints. A map that fixes the date (Ground rules) locks the
## year and says so, with the way to change it.

const LOCK_TEXT := "Fixed by this map · Ground rules…"

var eye: Button
var track: GrassYearTrack
var date: Label
var bloom: Button
var every: Button
var inspect_btn: Button
var lock: Button
var _p: GrassPaintProvider


func setup(p_provider: GrassPaintProvider, p_kit: Object, p_accent: Color) -> void:
	_p = p_provider
	add_theme_constant_override("separation", 8)
	eye = p_kit.tool_button("view_eye", "Show grass", p_accent)
	eye.toggled.connect(func(on: bool) -> void: _p.set_preview_visible(on))
	add_child(eye)
	track = GrassYearTrack.new()
	track.accent = p_accent
	track.day_changed.connect(func(d: float) -> void: _p.set_preview_day(d))
	add_child(track)
	lock = Button.new()
	lock.text = LOCK_TEXT
	lock.tooltip_text = "This map's Ground rules set its date: open them to change it"
	lock.focus_mode = Control.FOCUS_NONE
	lock.add_theme_font_size_override("font_size", 11)
	var pill := StyleBoxFlat.new()          # a dark pill over the greyed year, so the link reads
	pill.bg_color = Color(0.08, 0.09, 0.08, 0.92)
	pill.set_corner_radius_all(10)
	pill.content_margin_left = 10.0
	pill.content_margin_right = 10.0
	pill.content_margin_top = 2.0
	pill.content_margin_bottom = 2.0
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		lock.add_theme_stylebox_override(st, pill)
	track.add_child(lock)
	lock.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	lock.pressed.connect(func() -> void: _p.ground_rules_requested.emit())
	date = Label.new()
	date.custom_minimum_size = Vector2(52.0, 0.0)
	date.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	date.add_theme_font_size_override("font_size", 13)
	add_child(date)
	bloom = p_kit.chip("In bloom", false, p_accent)
	bloom.pressed.connect(func() -> void:
		var d := _p.bloom_day()
		if d >= 0.0:
			_p.set_preview_day(d))
	add_child(bloom)
	every = p_kit.tool_button("view_every_ground", "Grow on every ground (the preview only)", p_accent)
	every.toggled.connect(func(on: bool) -> void: _p.set_preview_all_grounds(on))
	add_child(every)
	inspect_btn = p_kit.tool_button("view_inspect", "Inspect: the brush chip says what grows under the cursor, and why",
		p_accent)
	inspect_btn.toggled.connect(func(on: bool) -> void: _p.inspect = on)
	add_child(inspect_btn)
	for b in [eye, every, inspect_btn]:     # slim: the In bloom chip's height, a 14 px icon (the bar's tools are 30)
		b.expand_icon = true
		b.custom_minimum_size = Vector2(22.0, 22.0)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		for st in ["normal", "hover", "pressed", "hover_pressed"]:
			(b.get_theme_stylebox(st) as StyleBoxFlat).set_content_margin_all(4.0)
		var off := StyleBoxEmpty.new()      # the theme's disabled box would pad it back up (a button's size is its largest)
		off.set_content_margin_all(4.0)
		b.add_theme_stylebox_override("disabled", off)
	bloom.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	refresh()


## Reads the preview and the provider again: the eye, the day, the date, the flowering windows, In bloom, every
## ground, the lock.
func refresh() -> void:
	var fixed := _p.fixed_date()
	eye.set_pressed_no_signal(GrassEditorPreview.visible)
	every.set_pressed_no_signal(GrassEditorPreview.all_grounds)
	inspect_btn.set_pressed_no_signal(_p.inspect)
	track.locked = fixed >= 0.0
	track.dimmed = not GrassEditorPreview.visible
	track.windows = _p.bloom_windows()
	track.set_day(fixed if fixed >= 0.0 else GrassEditorPreview.day)
	lock.visible = fixed >= 0.0
	date.text = GrassSeason.label(track.day)
	var bd := _p.bloom_day()
	bloom.disabled = bd < 0.0 or fixed >= 0.0
	if bd < 0.0:
		bloom.tooltip_text = "The selected species has no flowers"
	elif fixed >= 0.0:
		bloom.tooltip_text = "This map fixes the date"
	else:
		bloom.tooltip_text = "The selected species in flower (%s)" % GrassSeason.label(bd)
