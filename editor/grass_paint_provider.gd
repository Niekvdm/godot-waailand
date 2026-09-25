# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name GrassPaintProvider
extends RefCounted
## The grass tool of the Terrain3D Extended overlay: the Grass workspace, painting the grass maps itself (provider
## API v3: GrassBrush on GrassMaps). Ten tools with ctrl inverting (GrassPaintTool's modes), the slope and elevation limits
## and the region fill, one undo action a stroke, the species
## library with pictures and cards, its panel section, a preset part. The Waailand plugin registers it.

signal preview_changed            # the plugin keeps GrassEditorPreview in the project metadata
signal tool_done(tool_id: String)  # a one-shot tool (Pick) finished: the overlay returns to the tool before
signal ground_rules_requested     # "Ground rules…": the plugin opens the open map's dialog

const SpeciesCard := preload("res://addons/waailand/editor/grass_species_card.gd")

const ICON_DIR := "res://addons/waailand/editor/icons"
## The Grass workspace's tools: Terrain3D's ctrl-inverts convention replaces the ten modes.
const TOOLS := [
	{"id": "grass.species", "title": "Species", "icon": "grass_species"},
	{"id": "grass.erase", "title": "Erase", "icon": "grass_erase"},
	{"id": "grass.remove", "title": "Remove", "icon": "grass_remove"},
	{"id": "grass.density", "title": "Density", "icon": "grass_density"},
	{"id": "grass.height", "title": "Height", "icon": "grass_height"},
	{"id": "grass.smooth", "title": "Smooth", "icon": "grass_smooth"},
	{"id": "grass.force", "title": "Force", "icon": "grass_force"},
	{"id": "grass.replace", "title": "Replace", "icon": "grass_replace"},
	{"id": "grass.reset", "title": "Reset", "icon": "grass_reset"},
	{"id": "grass.pick", "title": "Pick", "icon": "grass_pick", "uses_size": false, "uses_strength": false},
]
const PICK_HINT := "Click the ground: the species it grows becomes the brush's, then back to the tool before."
const REPLACE_HINT := "Swaps that painted species for the one chosen in the library."
const RESET_HINT := "Back to the ground's own rule: species, density, height and force."
const REMOVE_HINT := "No grass at all, the ground's own included. Ctrl: back to ×1."
const FORCE_HINT := "Grass grows here whatever the ground (live roads excepted). Ctrl: the ground's rules."
const MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
const SEASONS := [["Winter", 0], ["Spring", 3], ["Summer", 6], ["Autumn", 9]]   # GrassPreviewMenu.DAYS index: the 15th

var paint := GrassPaintTool.new()
var types: GrassTypes
var _ui: Node = null
var _pictures := {}               # species name -> [tile, card] textures (loaded once; null when missing)
var _kinds: DecoKinds = null      # the hover card's flowers and ground, loaded with the first library
var _growth: GrassTerrainGrowth = null
var active_tool := ""             # the Grass tool the overlay activated ("" until one is)
var reset_density := false        # grass.density paints x1
var reset_height := false         # grass.height paints x1
var smooth_height := false        # grass.smooth evens the height (else the density)
var limit_slope := false          # every painting tool: only where the ground's slope is in slope_range (degrees)
var slope_range := Vector2(0.0, 30.0)
var limit_height := false         # ... and its elevation in height_range (m)
var height_range := Vector2(0.0, 100.0)
var fill_region := false          # a click paints the whole region under the cursor
var _day_label: Label             # the panel's date row (a chip moves it)
var _day_slider: HSlider
var map_date := Callable()        # () -> float: the open map's fixed date (-1: the clock); the plugin sets it


func _init(p_types: GrassTypes = null) -> void:
	types = p_types if p_types != null else GrassTypes.new()


## The brush data for the activated tool, ctrl (`p_invert`) inverting it.
func brush_data(p_invert := false) -> Dictionary:
	if active_tool != "":
		paint.mode = mode_for(active_tool, p_invert)
	var d := paint.brush_data(types)
	if active_tool == "grass.pick":
		return d
	if limit_slope:
		d["slope"] = slope_range
	if limit_height:
		d["height"] = height_range
	if fill_region:
		d["fill_region"] = true
	return d


func decal_color() -> Color:
	return paint.decal_color(types)


## [tile, card] textures of a species, loaded once per provider (nulls when not rendered).
func _pictures_of(nm: String) -> Array:
	if not _pictures.has(nm):
		_pictures[nm] = [GrassSpeciesPreview.tile_texture(nm), GrassSpeciesPreview.card_texture(nm)]
	return _pictures[nm]


## A species' tile picture (null when not rendered): the Ground rules dialog's.
func picture_of(nm: String) -> Texture2D:
	return _pictures_of(nm)[0]


## The hover card's flowers and ground, loaded once.
func _load_kinds() -> void:
	if _kinds == null:
		_kinds = DecoKinds.new(DecoKinds.FROM_CONFIG, types)
		_growth = GrassTerrainGrowth.new()


func set_spray(on: bool) -> void:
	paint.spray = on
	_refresh()


func set_preview_day(v: float) -> void:
	GrassEditorPreview.day = v
	preview_changed.emit()


func set_preview_visible(on: bool) -> void:
	GrassEditorPreview.visible = on
	preview_changed.emit()


func set_preview_all_grounds(on: bool) -> void:
	GrassEditorPreview.all_grounds = on
	preview_changed.emit()


## A day chosen by a chip: the preview, the slider and its label follow.
func _set_day(p_day: float) -> void:
	set_preview_day(p_day)
	if _day_slider != null and is_instance_valid(_day_slider):
		_day_slider.set_value_no_signal(p_day)
		_day_label.text = GrassSeason.label(p_day)


## The species' flowering date (GrassSpeciesPreview.bloom_day); -1 without flowers.
func _bloom_day(p_slot: int) -> float:
	_load_kinds()
	return GrassSpeciesPreview.bloom_day(_kinds, p_slot)


## The overlay re-reads the brush data and the decal.
func _refresh() -> void:
	if _ui != null and is_instance_valid(_ui):
		_ui.call("_on_setting_changed")
		_ui.call("update_decal")


var blades_of := Callable()       # () -> the edited scene's GrassBlades (the plugin): its grass_maps and terrain
var _undo: Object = null          # the plugin's EditorUndoRedoManager
var _brush := GrassBrush.new()
var _stroke := {}                 # the stroke's brush, and its op
var _before := {}                 # location -> Image: the regions this stroke changed, as they were


func set_undo(p_ur: Object) -> void:
	_undo = p_ur


## Provider API v3: a stroke. Pick reads the texel instead and hands
## back to the tool before.
func stroke_begin(p_hit: Vector3, p_brush: Dictionary) -> void:
	var b: Object = blades_of.call() if blades_of.is_valid() else null
	if b == null:
		return
	var maps: GrassMaps = b.get("grass_maps")
	if active_tool == "grass.pick":
		paint.apply_pick(maps.pixel(p_hit))
		_refresh()
		tool_done.emit("grass.pick")
		return
	var terrain: Object = b.get("terrain")
	_brush.maps = maps
	_brush.data = terrain.get("data") if terrain != null else null
	_brush.begin()
	_before.clear()
	_brush.on_first_change = func(loc: Vector2i) -> void:
		_before[loc] = maps.image(loc).duplicate()
		maps.mark_dirty(loc)           # dirty now: a stroke whose release never comes still saves
	_stroke = {"brush": p_brush, "op": brush_data(bool(p_brush.get("invert", false))), "blades": b}
	_brush.dab(p_hit, p_brush, _stroke["op"])


func stroke_to(p_hit: Vector3) -> void:
	if _brush.maps != null and not _stroke.is_empty():
		_brush.dab(p_hit, _stroke["brush"], _stroke["op"])


## One undo action for the stroke: each touched region's dirty rect, before and after (already applied).
func stroke_end() -> void:
	var maps := _brush.maps
	if maps != null and not _brush.touched.is_empty():
		var steps := []
		for loc in _brush.touched:
			var r: Rect2i = _brush.touched[loc]
			steps.append([loc, r.position, (_before[loc] as Image).get_region(r), maps.image(loc).get_region(r)])
			maps.mark_dirty(loc)
		if _undo != null:
			# The GrassBlades node is the context: the stroke is undone in its scene's history (scene-scoped Ctrl+Z,
			# the scene shows (*)), not the editor's global one.
			_undo.create_action(String(_stroke["op"].get("label", "Grass")), UndoRedo.MERGE_DISABLE, _stroke.get("blades"))
			for s in steps:
				_undo.add_do_method(self, &"_blit", maps, s[0], s[1], s[3])
				_undo.add_undo_method(self, &"_blit", maps, s[0], s[1], s[2])
			_undo.commit_action(false)
	_before.clear()
	_stroke = {}
	_brush.maps = null


func _blit(p_maps: GrassMaps, p_loc: Vector2i, p_at: Vector2i, p_crop: Image) -> void:
	p_maps.image(p_loc).blit_rect(p_crop, Rect2i(Vector2i.ZERO, p_crop.get_size()), p_at)
	p_maps.update_layer(p_loc)
	p_maps.mark_dirty(p_loc)


# --- the Grass workspace (provider API v3: it paints itself) ---

func workspace() -> Dictionary:
	return {"id": "grass", "title": "Grass", "icon": "ws_grass", "order": 3, "library": "species",
		"library_tool": "grass.species", "icon_dir": ICON_DIR, "api": 3, "paints_itself": true}


func tools() -> Array:
	return TOOLS.duplicate(true)


## The overlay switched to one of the Grass tools (Pick reads the texel of the next stroke's click).
func activate(p_tool: String, ui: Node) -> void:
	active_tool = p_tool
	_ui = ui
	paint.mode = mode_for(p_tool, false)


## The paint mode a Grass tool stands for, ctrl (`p_invert`) inverting it; Pick keeps the brush as it was.
func mode_for(p_tool: String, p_invert: bool) -> GrassPaintTool.Mode:
	match p_tool:
		"grass.species":
			return GrassPaintTool.Mode.ERASE if p_invert else GrassPaintTool.Mode.SPECIES
		"grass.erase":
			return GrassPaintTool.Mode.SPECIES if p_invert else GrassPaintTool.Mode.ERASE
		"grass.density":
			if reset_density:
				return GrassPaintTool.Mode.DENSITY_RESET
			return GrassPaintTool.Mode.DENSITY_DOWN if p_invert else GrassPaintTool.Mode.DENSITY_UP
		"grass.height":
			if reset_height:
				return GrassPaintTool.Mode.HEIGHT_RESET
			return GrassPaintTool.Mode.SHORTER if p_invert else GrassPaintTool.Mode.TALLER
		"grass.smooth":
			return GrassPaintTool.Mode.SMOOTH_HEIGHT if smooth_height else GrassPaintTool.Mode.SMOOTH_DENSITY
		"grass.remove":
			return GrassPaintTool.Mode.RESTORE if p_invert else GrassPaintTool.Mode.REMOVE
		"grass.force":
			return GrassPaintTool.Mode.UNFORCE if p_invert else GrassPaintTool.Mode.FORCE
		"grass.replace":
			return GrassPaintTool.Mode.REPLACE
		"grass.reset":
			return GrassPaintTool.Mode.RESET
	return paint.mode


## The species as the panel's library: each with its picture (its colour when there is none) and a hover card.
func library() -> Dictionary:
	_load_kinds()
	var items := []
	for e in GrassPaintTool.palette(types):
		var nm := String(e["name"])
		var slot: int = e["slot"]
		var pics := _pictures_of(nm)
		var card_tex: Texture2D = pics[1]
		var facts := GrassSpeciesPreview.facts(types, _kinds, _growth, slot)
		items.append({"id": slot, "name": nm.capitalize(),
			"picture": pics[0] if pics[0] != null else _swatch(e["colour"]),
			"card": func() -> Control: return SpeciesCard.make_card(card_tex, facts)})
	return {"id": "species", "placeholder": "Search species", "tool": "grass.species", "items": items}


func library_selected() -> int:
	return paint.species


func library_select(p_id: int) -> void:
	paint.species = p_id
	_refresh()


## The panel section: the tool's options (spray, force; reset to x1; density or height; the from species; a hint), the
## limits and the fill for a painting tool, the season (months, seasons, In bloom, the fine date), then the preview's
## eye and every-ground switch, drawn with the overlay's components (`kit`).
func build_settings(box: VBoxContainer, p_tool: String, kit: Object, accent: Color) -> void:
	match p_tool:
		"grass.species":
			box.add_child(_toggle(kit, "Spray (a feathered edge)", paint.spray, set_spray))
			box.add_child(_toggle(kit, "Force: grow on any ground", paint.force, func(on: bool) -> void:
				paint.force = on
				_refresh()))
		"grass.erase":
			box.add_child(_toggle(kit, "Spray (a feathered edge)", paint.spray, set_spray))
		"grass.remove", "grass.force":
			box.add_child(_toggle(kit, "Spray (a feathered edge)", paint.spray, set_spray))
			box.add_child(_hint(REMOVE_HINT if p_tool == "grass.remove" else FORCE_HINT))
		"grass.replace":
			box.add_child(_from_row())
			box.add_child(_hint(REPLACE_HINT))
		"grass.reset":
			box.add_child(_hint(RESET_HINT))
		"grass.density":
			box.add_child(_toggle(kit, "Reset to ×1", reset_density, func(on: bool) -> void:
				reset_density = on
				_refresh()))
		"grass.height":
			box.add_child(_toggle(kit, "Reset to ×1", reset_height, func(on: bool) -> void:
				reset_height = on
				_refresh()))
		"grass.smooth":
			var row := HBoxContainer.new()
			var group := ButtonGroup.new()
			for pair in [["Density", false], ["Height", true]]:
				var b: Button = kit.toggle_chip(pair[0], smooth_height == pair[1], accent)
				b.button_group = group
				var h: bool = pair[1]
				b.pressed.connect(func() -> void:
					smooth_height = h
					_refresh())
				row.add_child(b)
			box.add_child(row)
		"grass.pick":
			box.add_child(_hint(PICK_HINT))
	if p_tool != "grass.pick":
		_limits(box, kit, accent)
	var gr: Button = kit.chip("Ground rules…", false, accent)
	gr.tooltip_text = "What grows on this map's surfaces, and its species' seasons"
	gr.pressed.connect(func() -> void: ground_rules_requested.emit())
	box.add_child(gr)
	_season(box, kit, accent)
	box.add_child(kit.section("Preview"))
	box.add_child(_toggle(kit, "Show grass", GrassEditorPreview.visible, set_preview_visible))
	box.add_child(_toggle(kit, "Grow on every ground (preview)", GrassEditorPreview.all_grounds, set_preview_all_grounds))


## The preview's season: twelve month chips (each the 15th), four seasons, In bloom
## (the selected species' flowering date; disabled without flowers), then the fine slider with the date.
func _season(box: VBoxContainer, kit: Object, accent: Color) -> void:
	box.add_child(kit.section("Season"))
	var months := HFlowContainer.new()
	months.add_theme_constant_override("h_separation", 2)
	months.add_theme_constant_override("v_separation", 2)
	for i in 12:
		var mb: Button = kit.chip(MONTHS[i], false, accent)
		var dm: float = GrassPreviewMenu.DAYS[i]
		mb.tooltip_text = GrassSeason.label(dm)
		mb.pressed.connect(func() -> void: _set_day(dm))
		months.add_child(mb)
	box.add_child(months)
	var seasons := HFlowContainer.new()
	seasons.add_theme_constant_override("h_separation", 2)
	seasons.add_theme_constant_override("v_separation", 2)
	for sn in SEASONS:
		var sb: Button = kit.chip(sn[0], false, accent)
		var ds: float = GrassPreviewMenu.DAYS[sn[1]]
		sb.tooltip_text = GrassSeason.label(ds)
		sb.pressed.connect(func() -> void: _set_day(ds))
		seasons.add_child(sb)
	var bloom_day := _bloom_day(paint.species)
	var bloom: Button = kit.chip("In bloom", false, accent)
	bloom.disabled = bloom_day < 0.0
	bloom.tooltip_text = ("The selected species in flower (%s)" % GrassSeason.label(bloom_day)) if bloom_day >= 0.0 \
		else "The selected species has no flowers"
	bloom.pressed.connect(func() -> void: _set_day(bloom_day))
	seasons.add_child(bloom)
	box.add_child(seasons)
	var day: VBoxContainer = kit.slider_row("Date", 0.0, 364.0, 1.0, GrassEditorPreview.day, "", accent)
	_day_label = day.get_node("Head/Value")
	_day_slider = day.get_node("Slider")
	_day_label.text = GrassSeason.label(GrassEditorPreview.day)
	var lab := _day_label
	_day_slider.value_changed.connect(func(v: float) -> void:
		set_preview_day(v)
		lab.text = GrassSeason.label(v))
	box.add_child(day)
	var fixed: float = map_date.call() if map_date.is_valid() else -1.0
	if fixed >= 0.0:
		box.add_child(_hint("Date fixed by the map: %s (Ground rules)." % GrassSeason.label(fixed)))
		for c in [months, seasons]:
			for b in (c as Node).get_children():
				(b as Button).disabled = true
		_day_slider.editable = false
		_day_label.text = GrassSeason.label(fixed)


## Replace's "From": the palette's species, the one it swaps from selected.
func _from_row() -> Control:
	var row := HBoxContainer.new()
	var lab := Label.new()
	lab.text = "From"
	lab.add_theme_font_size_override("font_size", 11)
	row.add_child(lab)
	var ob := OptionButton.new()
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ob.focus_mode = Control.FOCUS_NONE
	for e in GrassPaintTool.palette(types):
		ob.add_item(String(e["name"]).capitalize(), int(e["slot"]))
	var at := ob.get_item_index(paint.replace_from)
	if at >= 0:
		ob.select(at)
	ob.item_selected.connect(func(i: int) -> void:
		paint.replace_from = ob.get_item_id(i)
		_refresh())
	row.add_child(ob)
	return row


## The limits (slope and elevation, each a toggle and its min–max rows, shown while on) and the region fill.
func _limits(box: VBoxContainer, kit: Object, accent: Color) -> void:
	box.add_child(kit.section("Limits"))
	var slope := _range_rows(kit, accent, "Slope", 0.0, 90.0, "°", func() -> Vector2: return slope_range,
		func(r: Vector2) -> void:
			slope_range = r
			_refresh())
	slope.visible = limit_slope
	box.add_child(_toggle(kit, "Limit to slope", limit_slope, func(on: bool) -> void:
		limit_slope = on
		slope.visible = on
		_refresh()))
	box.add_child(slope)
	var elev := _range_rows(kit, accent, "Elevation", -100.0, 1000.0, " m", func() -> Vector2: return height_range,
		func(r: Vector2) -> void:
			height_range = r
			_refresh())
	elev.visible = limit_height
	box.add_child(_toggle(kit, "Limit to elevation", limit_height, func(on: bool) -> void:
		limit_height = on
		elev.visible = on
		_refresh()))
	box.add_child(elev)
	box.add_child(_toggle(kit, "Fill: a click paints the whole region", fill_region, func(on: bool) -> void:
		fill_region = on
		_refresh()))


## A min and a max slider row; moving one past the other drags it along.
static func _range_rows(kit: Object, accent: Color, p_name: String, lo: float, hi: float, suffix: String,
		get_r: Callable, set_r: Callable) -> VBoxContainer:
	var col := VBoxContainer.new()
	var r: Vector2 = get_r.call()
	var mn: VBoxContainer = kit.slider_row("%s min" % p_name, lo, hi, 1.0, r.x, suffix, accent)
	var mx: VBoxContainer = kit.slider_row("%s max" % p_name, lo, hi, 1.0, r.y, suffix, accent)
	var smn: HSlider = mn.get_node("Slider")
	var smx: HSlider = mx.get_node("Slider")
	smn.value_changed.connect(func(v: float) -> void:
		if smx.value < v:
			smx.value = v
		set_r.call(Vector2(v, smx.value)))
	smx.value_changed.connect(func(v: float) -> void:
		if smn.value > v:
			smn.value = v
		set_r.call(Vector2(smn.value, v)))
	col.add_child(mn)
	col.add_child(mx)
	return col


static func _hint(p_text: String) -> Label:
	var hint := Label.new()
	hint.text = p_text
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 11)
	return hint


## Its part of a preset: the species, spray and the tools' options, the limits and the fill.
func capture(_tool: String) -> Dictionary:
	return {"species": paint.species, "spray": paint.spray, "reset_density": reset_density,
		"reset_height": reset_height, "smooth_height": smooth_height, "force": paint.force,
		"replace_from": paint.replace_from, "limit_slope": limit_slope, "slope_range": slope_range,
		"limit_height": limit_height, "height_range": height_range, "fill_region": fill_region}


func apply(_tool: String, state: Dictionary) -> void:
	paint.species = int(state.get("species", paint.species))
	paint.spray = bool(state.get("spray", paint.spray))
	reset_density = bool(state.get("reset_density", reset_density))
	reset_height = bool(state.get("reset_height", reset_height))
	smooth_height = bool(state.get("smooth_height", smooth_height))
	paint.force = bool(state.get("force", paint.force))
	paint.replace_from = int(state.get("replace_from", paint.replace_from))
	limit_slope = bool(state.get("limit_slope", limit_slope))
	limit_height = bool(state.get("limit_height", limit_height))
	fill_region = bool(state.get("fill_region", fill_region))
	if state.get("slope_range") is Vector2:
		slope_range = state["slope_range"]
	if state.get("height_range") is Vector2:
		height_range = state["height_range"]
	_refresh()


static func _toggle(kit: Object, p_label: String, p_on: bool, p_fn: Callable) -> Control:
	var row: HBoxContainer = kit.toggle_row(p_label, p_on)
	(row.get_node("Toggle") as CheckBox).toggled.connect(p_fn)
	return row


## A plain colour tile for a species without a picture.
static func _swatch(c: Color) -> Texture2D:
	var img := Image.create_empty(8, 8, false, Image.FORMAT_RGB8)
	img.fill(c)
	return ImageTexture.create_from_image(img)
