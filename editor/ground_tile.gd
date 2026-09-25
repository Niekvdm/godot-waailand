# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name GroundTile
extends Button
## A surface or a species tile in the Ground rules dialog: its picture (a surface's albedo drawn without its alpha,
## where Terrain3D packs height) or its colour, the name along the bottom
## and a dot in its rule's colour. Dragging it carries {kind, id} to a GroundDropTarget; a click is `pressed`.

const OPAQUE := "shader_type canvas_item;\nvoid fragment() {\n\tCOLOR = vec4(texture(TEXTURE, UV).rgb, 1.0);\n}\n"
const FRAME := Color(1.0, 1.0, 1.0, 0.1)
const CAPTION := Color(0.0, 0.0, 0.0, 0.6)
const DOT_EDGE := Color(0.0, 0.0, 0.0, 0.6)

static var _opaque: ShaderMaterial = null

var drag_kind := ""          # "ground_surface" | "ground_species"
var drag_id := ""


static func make(p_kind: String, p_id: String, p_picture: Texture2D, p_caption: String, p_px: int,
		p_dot := Color(0, 0, 0, 0), p_opaque := false, p_fallback := Color(0.3, 0.35, 0.3)) -> GroundTile:
	var b := GroundTile.new()
	b.drag_kind = p_kind
	b.drag_id = p_id
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	b.custom_minimum_size = Vector2(p_px, p_px)
	b.tooltip_text = p_caption
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(0, 0, 0, 0)
	frame.set_corner_radius_all(6)
	frame.set_border_width_all(1)
	frame.border_color = FRAME
	for s in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(s, frame)
	var pic: Control
	if p_picture != null:
		var tr := TextureRect.new()
		tr.texture = p_picture
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		if p_opaque:
			tr.material = opaque_material()
		pic = tr
	else:
		var cr := ColorRect.new()
		cr.color = p_fallback
		pic = cr
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.add_child(pic)
	if p_px >= 40:
		var cap := Label.new()
		cap.text = p_caption
		cap.clip_text = true
		cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cap.add_theme_font_size_override("font_size", 9)
		var sb := StyleBoxFlat.new()
		sb.bg_color = CAPTION
		sb.content_margin_left = 3.0
		cap.add_theme_stylebox_override("normal", sb)
		cap.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		b.add_child(cap)
	if p_dot.a > 0.0:
		var dot := Panel.new()
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ds := StyleBoxFlat.new()
		ds.bg_color = p_dot
		ds.set_corner_radius_all(4)
		ds.set_border_width_all(1)
		ds.border_color = DOT_EDGE
		dot.add_theme_stylebox_override("panel", ds)
		dot.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		dot.offset_left = -11.0
		dot.offset_top = 3.0
		dot.offset_right = -3.0
		dot.offset_bottom = 11.0
		b.add_child(dot)
	return b


static func opaque_material() -> ShaderMaterial:
	if _opaque == null:
		var sh := Shader.new()
		sh.code = OPAQUE
		_opaque = ShaderMaterial.new()
		_opaque.shader = sh
	return _opaque


func _get_drag_data(_at: Vector2) -> Variant:
	if drag_kind == "" or disabled:
		return null
	if is_inside_tree():
		var ghost := Label.new()
		ghost.text = tooltip_text
		set_drag_preview(ghost)
	return {"kind": drag_kind, "id": drag_id}
