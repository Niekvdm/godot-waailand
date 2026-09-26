# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name GrassViewStrip
extends HBoxContainer
## The Grass workspace's view strip (Terrain3D Extended's strip at the top of the 3D view, provider build_view): the
## eye (show grass), the year (GrassYearTrack: drag, or a month letter), the date, In bloom (every species with flowers
## in bloom, whatever the date), every ground, Inspect (ⓘ: the brush chip reads what grows under the cursor, and why)
## and the paint overlay (GrassOverlay: what the maps hold, on the terrain, the grass hidden; ▾ picks what it shows and
## keys it). It sets what the preview shows (GrassEditorPreview), never what a stroke paints. A map that fixes the date
## (Ground rules) locks the year and says so, with the way to change it.

const LOCK_TEXT := "Fixed by this map · Ground rules…"
const OVERLAY_TIP := "Paint overlay: what is painted where, on the ground (the grass hidden while it shows)"
const OVERLAY_NO := ("Paint overlay: needs the far field in this terrain's shader (Waailand README, \"The far field in "
	+ "your terrain shader\")")
const OVERLAY_SHORT := ["", "Painted", "Density", "Height"]
const KEY_ID := 100                 # the overlay menu's key rows (disabled; the modes are GrassOverlay.Mode)
const EYE_TIP := "Show grass"
const EYE_OVERLAY := "The paint overlay hides the grass: turn it off to see the grass"

var eye: Button
var track: GrassYearTrack
var date: Label
var bloom: Button
var every: Button
var inspect_btn: Button
var overlay_btn: Button
var overlay_menu: MenuButton
var lock: Button
var _p: GrassPaintProvider


func setup(p_provider: GrassPaintProvider, p_kit: Object, p_accent: Color) -> void:
	_p = p_provider
	add_theme_constant_override("separation", 8)
	eye = p_kit.tool_button("view_eye", EYE_TIP, p_accent)
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
	bloom = p_kit.toggle_chip("In bloom", GrassEditorPreview.all_bloom, p_accent)
	bloom.tooltip_text = "Every species with flowers in bloom, whatever the date (the preview only)"
	bloom.toggled.connect(func(on: bool) -> void: _p.set_preview_all_bloom(on))
	add_child(bloom)
	every = p_kit.tool_button("view_every_ground", "Grow on every ground (the preview only)", p_accent)
	every.toggled.connect(func(on: bool) -> void: _p.set_preview_all_grounds(on))
	add_child(every)
	inspect_btn = p_kit.tool_button("view_inspect", "Inspect: the brush chip says what grows under the cursor, and why",
		p_accent)
	inspect_btn.toggled.connect(func(on: bool) -> void: _p.inspect = on)
	add_child(inspect_btn)
	overlay_btn = p_kit.tool_button("view_overlay", OVERLAY_TIP, p_accent)
	overlay_btn.toggled.connect(func(on: bool) -> void:
		_p.set_preview_overlay(GrassEditorPreview.overlay_mode if on else GrassOverlay.Mode.OFF))
	add_child(overlay_btn)
	overlay_menu = MenuButton.new()
	overlay_menu.flat = true
	overlay_menu.focus_mode = Control.FOCUS_NONE
	overlay_menu.tooltip_text = "What the paint overlay shows, and its key"
	overlay_menu.add_theme_font_size_override("font_size", 12)
	overlay_menu.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	overlay_menu.about_to_popup.connect(_fill_overlay_menu)
	overlay_menu.get_popup().id_pressed.connect(func(id: int) -> void: _p.set_preview_overlay(id))
	add_child(overlay_menu)
	for b in [eye, every, inspect_btn, overlay_btn]:     # slim: the In bloom chip's height, a 14 px icon (the bar's tools are 30)
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
## ground, the lock, the overlay (on offer where the terrain's shader draws it).
func refresh() -> void:
	var fixed := _p.fixed_date()
	eye.set_pressed_no_signal(GrassEditorPreview.visible)
	var on := GrassEditorPreview.overlay != GrassOverlay.Mode.OFF
	eye.disabled = on
	eye.tooltip_text = EYE_OVERLAY if on else EYE_TIP
	var ok := _p.overlay_supported()
	overlay_btn.set_pressed_no_signal(on)
	overlay_btn.disabled = not ok and not on          # on stays switchable off
	overlay_btn.tooltip_text = OVERLAY_TIP if ok else OVERLAY_NO
	overlay_menu.disabled = overlay_btn.disabled
	overlay_menu.text = OVERLAY_SHORT[GrassEditorPreview.overlay_mode] + " ▾"
	every.set_pressed_no_signal(GrassEditorPreview.all_grounds)
	inspect_btn.set_pressed_no_signal(_p.inspect)
	track.locked = fixed >= 0.0
	track.dimmed = not GrassEditorPreview.grass_shows()
	track.windows = _p.bloom_windows()
	track.set_day(fixed if fixed >= 0.0 else GrassEditorPreview.day)
	lock.visible = fixed >= 0.0
	date.text = GrassSeason.label(track.day)
	bloom.set_pressed_no_signal(GrassEditorPreview.all_bloom)


## ▾: the overlay's modes (one picked turns it on), then the key for the mode it shows.
func _fill_overlay_menu() -> void:
	var pm := overlay_menu.get_popup()
	pm.clear()
	for m in [GrassOverlay.Mode.PAINTED, GrassOverlay.Mode.DENSITY, GrassOverlay.Mode.HEIGHT]:
		pm.add_radio_check_item(GrassOverlay.MODE_NAMES[m], m)
		pm.set_item_checked(pm.get_item_index(m), GrassEditorPreview.overlay == m)
	pm.add_separator("Key")
	var leg := GrassOverlay.legend(GrassEditorPreview.overlay_mode, _p.types)
	for i in leg.size():
		pm.add_icon_item(_key_swatch(leg[i][0]), leg[i][1], KEY_ID + i)
		pm.set_item_disabled(pm.item_count - 1, true)


static func _key_swatch(c: Color) -> Texture2D:
	var img := Image.create_empty(14, 14, false, Image.FORMAT_RGB8)
	img.fill(c)
	return ImageTexture.create_from_image(img)
