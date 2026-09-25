# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name GroundRulesDialog
extends Control
## The Ground rules dialog: centred and modal over the editor, it edits the open map's rules (GrassGroundRules) in two
## tabs, Rules (the map's surfaces, the rules, the selected rule) and Seasons (the timeline). Every change is one undo step: the model is snapshotted, changed, written and the map's grass
## reloaded (`save`), then the view is rebuilt from the model. Built in code with the overlay's components (`kit`);
## the Waailand plugin opens it (context_for), tests drive it headless.

signal closed

const UNDO_MAX := 100
const SIZE := Vector2(1100, 680)
const BACKDROP := Color(0.0, 0.0, 0.0, 0.45)
const DIM := Color(1.0, 1.0, 1.0, 0.55)
const ERROR := Color("ff8a80")
const PANEL_ALPHA := 0.94
## The Terrain3D Extended overlay's modal group (tool_providers.gd MODAL_GROUP): while the dialog is in it, the
## overlay hides and the terrain takes no 3D input, so a click on the dialog never paints the terrain underneath.
const UX_MODAL_GROUP := &"terrain_3d_ux_modal"

var rules: GrassGroundRules = null
var surfaces: Array = []          # {name, picture: Texture2D or null}: the map's textures, in id order
var types: GrassTypes
var kinds: DecoKinds
var kit: Object                   # the overlay's UxComponents
var accent := Color("8bc34a")
var picture := Callable()         # species name -> Texture2D (null: its colour)
var save := Callable()            # (GrassGroundRules) -> Error: write the file, reload the map's grass
var start := Callable()           # () -> GrassGroundRules: Start from defaults
var map_name := ""
var path := ""
var tab := "rules"                # "rules" | "seasons"
var selected := 0                 # the Rules tab's rule (-1: Everything else)
var surface_filter := "all"       # "all" | "unassigned"
var season_open := ""             # the Seasons tab's open row
var show_all_species := false
var error := ""
var _undo: Array = []
var _redo: Array = []
var _panel: PanelContainer
var _content: VBoxContainer
var _rebuilding := false


func setup(p: Dictionary) -> void:
	rules = p.get("rules")
	surfaces = p.get("surfaces", [])
	types = p["types"]
	kinds = p["kinds"]
	kit = p["kit"]
	accent = p.get("accent", accent)
	picture = p.get("picture", Callable())
	save = p.get("save", Callable())
	start = p.get("start", Callable())
	map_name = p.get("map", "")
	path = p.get("path", "")
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	var back := ColorRect.new()
	back.color = BACKDROP
	back.mouse_filter = MOUSE_FILTER_IGNORE
	back.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(back)
	var center := CenterContainer.new()
	center.mouse_filter = MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(center)
	_panel = kit.glass_panel()
	var sb := (_panel.get_theme_stylebox("panel") as StyleBoxFlat).duplicate() as StyleBoxFlat
	sb.bg_color.a = PANEL_ALPHA
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.custom_minimum_size = SIZE
	center.add_child(_panel)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 8)
	_panel.add_child(_content)
	rebuild()


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE:
		add_to_group(UX_MODAL_GROUP)
		# Top level: the whole window whatever the parent lays out, so the panel is centred on the screen and the
		# backdrop takes every click.
		top_level = true
		set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	elif what == NOTIFICATION_RESIZED and _panel != null and is_inside_tree():
		_panel.custom_minimum_size = SIZE.min(get_viewport_rect().size - Vector2(40.0, 40.0))


## Rebuilds the view from the model (the dialog is small: each change rebuilds it). Scroll positions are kept.
func rebuild() -> void:
	_rebuilding = true
	var scrolls := {}
	for sc in _content.find_children("*", "ScrollContainer", true, false):
		scrolls[String(sc.name)] = (sc as ScrollContainer).scroll_vertical
	for c in _content.get_children():
		_content.remove_child(c)
		c.queue_free()
	_content.add_child(_header())
	if error != "":
		var e := Label.new()
		e.name = "Error"
		e.text = error
		e.add_theme_color_override("font_color", ERROR)
		_content.add_child(e)
	if rules != null and not rules.errors.is_empty():
		var w := hint("The file had problems (dropped): %s" % "; ".join(rules.errors.slice(0, 3)))
		w.name = "Warnings"
		w.add_theme_color_override("font_color", ERROR)
		_content.add_child(w)
	var body: Control
	if map_name == "":
		body = _message("This map has no grass (no GrassBlades node).")
	elif path == "":
		body = _message("The grass config names no grounds_dir: set it in waailand_config.tres to give maps their own rules.")
	elif rules == null:
		body = _start_view()
	else:
		body = _tab_body()
	body.size_flags_vertical = SIZE_EXPAND_FILL
	_content.add_child(body)
	for sc in _content.find_children("*", "ScrollContainer", true, false):
		if scrolls.has(String(sc.name)):
			(sc as ScrollContainer).set_deferred("scroll_vertical", scrolls[String(sc.name)])
	_rebuilding = false


func _tab_body() -> Control:
	return GroundRulesSeasonsTab.build(self) if tab == "seasons" else GroundRulesRulesTab.build(self)


func _header() -> Control:
	var h := HBoxContainer.new()
	h.name = "Header"
	h.add_theme_constant_override("separation", 10)
	var title := Label.new()
	title.text = "GROUND RULES"
	title.add_theme_color_override("font_color", accent)
	title.add_theme_font_size_override("font_size", 13)
	h.add_child(title)
	var where := Label.new()
	where.text = ("· %s · %s" % [map_name, path]) if map_name != "" else ""
	where.modulate = DIM
	where.clip_text = true
	where.size_flags_horizontal = SIZE_EXPAND_FILL
	h.add_child(where)
	if rules != null:
		var group := ButtonGroup.new()
		for pair in [["Rules", "rules"], ["Seasons", "seasons"]]:
			var b: Button = kit.toggle_chip(pair[0], tab == pair[1], accent)
			b.name = "Tab" + String(pair[0])
			b.button_group = group
			var id: String = pair[1]
			b.pressed.connect(func() -> void:
				tab = id
				rebuild())
			h.add_child(b)
		if tab == "rules":
			var master: HBoxContainer = kit.toggle_row("Default grass (this map)", rules.default_grass)
			master.name = "Master"
			(master.get_node("Label") as Label).size_flags_horizontal = SIZE_SHRINK_BEGIN
			(master.get_node("Toggle") as CheckBox).toggled.connect(func(on: bool) -> void:
				change(func() -> void: rules.default_grass = on))
			h.add_child(master)
		h.add_child(_button("Undo", "↶", undo, _undo.is_empty()))
		h.add_child(_button("Redo", "↷", redo, _redo.is_empty()))
	h.add_child(_button("Close", "✕", close, false))
	return h


func _button(nm: String, text: String, fn: Callable, off: bool) -> Button:
	var b := Button.new()
	b.name = nm
	b.text = text
	b.tooltip_text = nm
	b.disabled = off
	b.focus_mode = FOCUS_NONE
	b.pressed.connect(fn)
	return b


func _message(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


func _start_view() -> Control:
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(_message("This map uses the shared growth table (%s). Start from it to give the map its own rules: "
		% GrassBladesConfig.current().growth_path + "its grass stays the same until you change them."))
	var b := Button.new()
	b.name = "Start"
	b.text = "Start from defaults"
	b.size_flags_horizontal = SIZE_SHRINK_CENTER
	b.pressed.connect(func() -> void:
		rules = start.call()
		_commit())
	v.add_child(b)
	return v


## One undo step: `fn` changes the model; it is written, the map's grass reloaded and the view rebuilt. Ignored while
## rebuilding (a LineEdit losing focus as the view is torn down).
func change(fn: Callable) -> void:
	if _rebuilding or rules == null:
		return
	_undo.append(rules.snapshot())
	if _undo.size() > UNDO_MAX:
		_undo.pop_front()
	_redo.clear()
	fn.call()
	_commit()


func undo() -> void:
	if _undo.is_empty():
		return
	_redo.append(rules.snapshot())
	rules.restore(_undo.pop_back())
	_commit()


func redo() -> void:
	if _redo.is_empty():
		return
	_undo.append(rules.snapshot())
	rules.restore(_redo.pop_back())
	_commit()


func _commit() -> void:
	var err: int = save.call(rules) if save.is_valid() else OK
	error = "" if err == OK else "Could not write %s: %s" % [path, error_string(err)]
	selected = clampi(selected, -1, rules.rules.size() - 1)
	rebuild()


func close() -> void:
	closed.emit()
	queue_free()


func _input(ev: InputEvent) -> void:
	if not (ev is InputEventKey) or not ev.pressed or ev.echo:
		return
	var k := ev as InputEventKey
	var vp := get_viewport()
	var typing := vp != null and vp.gui_get_focus_owner() is LineEdit
	if k.keycode == KEY_ESCAPE:
		close()
	elif rules != null and not typing and k.ctrl_pressed and k.keycode == KEY_Z:
		if k.shift_pressed:
			redo()
		else:
			undo()
	elif rules != null and not typing and k.ctrl_pressed and k.keycode == KEY_Y:
		redo()
	else:
		return
	if vp != null:
		vp.set_input_as_handled()


# --- helpers the tabs use ---

func surface_names() -> PackedStringArray:
	var out := PackedStringArray()
	for s in surfaces:
		out.append(String(s["name"]))
	return out


func has_surface(nm: String) -> bool:
	return surface_names().has(nm)


func surface_picture(nm: String) -> Texture2D:
	for s in surfaces:
		if String(s["name"]) == nm:
			return s.get("picture")
	return null


## A rule's colour; none for Everything else (-1).
func rule_colour(i: int) -> Color:
	return Color(String(rules.rules[i]["colour"])) if i >= 0 and i < rules.rules.size() else Color(0, 0, 0, 0)


## What rule i grows (-1: Everything else): its own mix, else Everything else's, else the defaults.
func mix_of(i: int) -> Dictionary:
	if i >= 0 and not (rules.rules[i]["species"] as Dictionary).is_empty():
		return rules.rules[i]["species"]
	if not (rules.everything_else["species"] as Dictionary).is_empty():
		return rules.everything_else["species"]
	return GrassTerrainGrowth.pack_default_mix()


func species_picture(sp: String) -> Texture2D:
	return picture.call(sp) if picture.is_valid() else null


func swatch(sp: String) -> Color:
	return GrassPaintTool.swatch(types, types.names().find(sp))


func hint(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.modulate = DIM
	l.add_theme_font_size_override("font_size", 11)
	return l


## A one-line dim note (rows: a word-wrapping label in a row gets no width and wraps each letter).
func note(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.modulate = DIM
	l.add_theme_font_size_override("font_size", 10)
	l.size_flags_vertical = SIZE_SHRINK_CENTER
	return l


static func box(bg: Color, border := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(8)
	if border.a > 0.0:
		sb.set_border_width_all(1)
		sb.border_color = border
	sb.content_margin_left = 8.0
	sb.content_margin_right = 8.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	return sb


## The map's textures for the Surfaces column: {name, picture (the albedo)} in id order.
static func surfaces_of(assets: Resource) -> Array:
	var by_id := {}
	if assets != null:
		for ta in assets.call("get_texture_list"):
			if ta != null:
				by_id[int(ta.get("id"))] = {"name": str(ta.get("name")), "picture": ta.call("get_albedo_texture")}
	var ids := by_id.keys()
	ids.sort()
	return ids.map(func(id): return by_id[id])


## What the plugin opens the dialog with for the edited scene's GrassBlades (null: the map has no grass): its surfaces,
## its rules file (null: none yet), a save that writes it and reloads the grass, Start from defaults (the converter).
static func context_for(blades: GrassBlades, p_types: GrassTypes, p_kit: Object, p_picture: Callable) -> Dictionary:
	var ctx := {"types": p_types, "kinds": DecoKinds.new(DecoKinds.FROM_CONFIG, p_types), "kit": p_kit,
		"picture": p_picture, "rules": null, "surfaces": [], "map": "", "path": ""}
	if blades == null:
		return ctx
	var assets: Resource = blades.terrain.get("assets") if blades.terrain != null else null
	ctx["surfaces"] = surfaces_of(assets)
	var own := blades.owner.scene_file_path.get_file().get_basename() if blades.owner != null else ""
	ctx["map"] = own if own != "" else (String(blades.name) if String(blades.name) != "" else "this map")
	var p := blades.rules_path()
	ctx["path"] = p
	ctx["rules"] = GrassGroundRules.load_file(p)
	ctx["save"] = func(r: GrassGroundRules) -> Error:
		var e := r.save_file(p)
		if e == OK and is_instance_valid(blades):
			blades.reload_rules()
		return e
	var names := GrassGroundRules.surface_names(assets)
	ctx["start"] = func() -> GrassGroundRules:
		var doc = JSON.parse_string(FileAccess.get_file_as_string(GrassBladesConfig.current().growth_path))
		return GrassGroundRules.from_growth_table(doc if doc is Dictionary else {}, names)
	return ctx
