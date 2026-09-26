# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name GrassSpeciesTile
extends Button
## A species in the Species dialog: its picture, its name along the bottom, the flower kinds it brings at the name's
## right (library tiles), its layer as a corner fold (teal underwater, blue floating, light blue wet ground); in the
## slots its number, the fallback's green frame, a missing species' red frame, an empty slot's dashed one. A library
## tile drags {kind "waailand_species", id} and is dimmed with a dot when active; a slot drags {kind "waailand_slot",
## slot, id} and takes a species or a pack dropped on it (`on_drop`). `ring` frames a tile (the library's "Show in the
## library", a slot a drop was refused on). A double-click is `activated`, a right-click `menu_requested`; hovering
## shows `card`.

signal activated
signal menu_requested(at: Vector2)     # at: the click, in screen coordinates

const FOLD := {"under": Color("2bb3a3"), "float": Color("4fa3e0"), "wet": Color("9cc8ee")}
const FLOWER := Color("ffd54a")
const FRAME := Color(1.0, 1.0, 1.0, 0.1)
const EMPTY := Color(1.0, 1.0, 1.0, 0.18)
const CAPTION := Color(0.0, 0.0, 0.0, 0.62)
const MISSING := Color("ff8a80")
const LIBRARY_PX := 78
const SLOT_PX := 40

var id: StringName = &""
var slot := -1                    # a slot tile's number; -1: a library tile
var layer := "ground"             # GrassActiveSet.layer_of
var kinds := 0
var active := false               # a library tile whose species is active
var fallback := false             # the fallback's slot
var missing := false              # a slot whose species is not installed
var ring := Color(0, 0, 0, 0)     # a frame over the tile (none: transparent)
var accent := Color("8bc34a")
var on_drop := Callable()         # (data: Dictionary) -> void: what a slot does with a drop
var card := Callable()            # () -> Control: the hover card
var _px := LIBRARY_PX


## A library tile (`p_slot` -1) or a slot tile. `p_picture` null: a plain colour.
static func make(p_id: StringName, p_picture: Texture2D, p_caption: String, p_slot := -1, p_layer := "ground",
		p_kinds := 0) -> GrassSpeciesTile:
	var t := GrassSpeciesTile.new()
	t.id = p_id
	t.slot = p_slot
	t.layer = p_layer
	t.kinds = p_kinds
	t._px = SLOT_PX if p_slot >= 0 else LIBRARY_PX
	t.custom_minimum_size = Vector2(t._px, t._px)
	t.focus_mode = Control.FOCUS_NONE
	t.mouse_filter = Control.MOUSE_FILTER_PASS
	t.tooltip_text = p_caption if p_id != &"" else "Slot %d: empty" % p_slot
	t.name = ("Slot%d" % p_slot) if p_slot >= 0 else "Species_" + String(p_id)
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(0, 0, 0, 0.25) if p_id == &"" else Color(0, 0, 0, 0)
	frame.set_corner_radius_all(6 if p_slot < 0 else 5)
	for s in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		t.add_theme_stylebox_override(s, frame)
	if p_id != &"":
		var pic: Control
		if p_picture != null:
			var tr := TextureRect.new()
			tr.texture = p_picture
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			pic = tr
		else:
			var cr := ColorRect.new()
			cr.color = Color(0.3, 0.35, 0.3)
			pic = cr
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		t.add_child(pic)
		t.add_child(t._caption(p_caption))
	if p_slot >= 0:
		var n := Label.new()
		n.text = str(p_slot)
		n.mouse_filter = Control.MOUSE_FILTER_IGNORE
		n.add_theme_font_size_override("font_size", 8)
		n.add_theme_color_override("font_color", Color(1, 1, 1, 0.35 if p_id == &"" else 0.95))
		n.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
		n.position = Vector2(3, 0) if p_id == &"" else Vector2(t._px - 14, 0)
		t.add_child(n)
	var over := _Overlay.new()
	over.tile = t
	over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	over.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	t.add_child(over)
	return t


func _caption(p_text: String) -> Control:
	var bar := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = CAPTION
	sb.content_margin_left = 3.0
	sb.content_margin_right = 3.0
	bar.add_theme_stylebox_override("panel", sb)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.anchor_left = 0.0
	bar.anchor_right = 1.0
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_top = -13.0 if slot < 0 else -11.0
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 2)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.text = p_text
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", 9 if slot < 0 else 8)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(l)
	if slot < 0 and kinds > 0:
		var f := _Flower.new()
		f.custom_minimum_size = Vector2(9, 9)
		f.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		f.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(f)
		var k := Label.new()
		k.text = str(kinds)
		k.add_theme_font_size_override("font_size", 9)
		k.add_theme_color_override("font_color", FLOWER)
		k.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(k)
	bar.add_child(h)
	return bar


## Marks after the facts are known (the dialog sets them).
func mark(p_active: bool, p_fallback: bool, p_missing: bool, p_accent: Color, p_ring := Color(0, 0, 0, 0)) \
		-> GrassSpeciesTile:
	active = p_active
	fallback = p_fallback
	missing = p_missing
	accent = p_accent
	ring = p_ring
	if slot < 0 and active:
		modulate.a = 0.4
	return self


func _get_drag_data(_at: Vector2) -> Variant:
	if id == &"":
		return null
	if is_inside_tree():
		var pv := TextureRect.new()
		for c in get_children():
			if c is TextureRect:
				pv.texture = (c as TextureRect).texture
		pv.custom_minimum_size = Vector2(40, 40)
		pv.size = Vector2(40, 40)
		pv.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pv.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		set_drag_preview(pv)
	if slot >= 0:
		return {"kind": "waailand_slot", "slot": slot, "id": String(id)}
	return {"kind": "waailand_species", "id": String(id)}


func _can_drop_data(_at: Vector2, p_data: Variant) -> bool:
	return slot >= 0 and p_data is Dictionary and String(p_data.get("kind", "")) in ["waailand_species", "waailand_pack"]


func _drop_data(_at: Vector2, p_data: Variant) -> void:
	if on_drop.is_valid():
		on_drop.call(p_data)


func _gui_input(ev: InputEvent) -> void:
	var mb := ev as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	if mb.button_index == MOUSE_BUTTON_LEFT and mb.double_click and slot < 0 and id != &"":
		activated.emit()
		accept_event()
	elif mb.button_index == MOUSE_BUTTON_RIGHT and slot >= 0:
		menu_requested.emit(get_screen_position() + mb.position)     # screen: the editor's popups are windows
		accept_event()


func _make_custom_tooltip(_for_text: String) -> Object:
	return card.call() if card.is_valid() and id != &"" else null


## The fold, the dot and the frames, over the picture.
class _Overlay:
	extends Control
	var tile: GrassSpeciesTile

	func _draw() -> void:
		var s := size
		if tile.id == &"":
			_dashed(Rect2(Vector2(0.5, 0.5), s - Vector2.ONE), EMPTY, 1.0)
			if tile.ring.a > 0.0:
				draw_rect(Rect2(Vector2.ONE, s - Vector2(2, 2)), tile.ring, false, 2.0)
			return
		draw_rect(Rect2(Vector2.ZERO, s), FRAME, false, 1.0)
		if FOLD.has(tile.layer):
			var f := 14.0 if tile.slot < 0 else 10.0
			draw_colored_polygon(PackedVector2Array([Vector2.ZERO, Vector2(f, 0.0), Vector2(0.0, f)]), FOLD[tile.layer])
		if tile.slot < 0 and tile.active:
			draw_circle(Vector2(s.x - 6.0, 6.0), 3.5, tile.accent)
		if tile.fallback:
			draw_rect(Rect2(Vector2.ONE, s - Vector2(2, 2)), tile.accent, false, 2.0)
		if tile.ring.a > 0.0:
			draw_rect(Rect2(Vector2.ONE, s - Vector2(2, 2)), tile.ring, false, 2.0)
		if tile.missing:
			_dashed(Rect2(Vector2.ONE, s - Vector2(2, 2)), MISSING, 2.0)

	func _dashed(r: Rect2, c: Color, w: float) -> void:
		for e in [[r.position, Vector2(r.end.x, r.position.y)], [Vector2(r.end.x, r.position.y), r.end],
				[r.end, Vector2(r.position.x, r.end.y)], [Vector2(r.position.x, r.end.y), r.position]]:
			draw_dashed_line(e[0], e[1], c, w, 3.0)


## The flower icon: five petals round a heart.
class _Flower:
	extends Control

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.24
		for i in 5:
			var a := -PI * 0.5 + TAU * i / 5.0
			draw_circle(c + Vector2(cos(a), sin(a)) * r * 1.2, r, FLOWER)
		draw_circle(c, r * 0.7, Color(0.13, 0.13, 0.13))
