# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name GrassPaintProvider
extends RefCounted
## The grass tool of the Terrain3D Extended overlay (1.2, tool providers level 2): the Grass workspace, painting the
## grass maps itself (provider API v3: GrassBrush on GrassMaps). Ten tools in three groups with ctrl inverting
## (GrassPaintTool's modes), Pick behind the bar's eyedropper, Replace's From in the bar's source chip; the species
## library by pack; the panel's header (Ground | Water, an empty layer's banner), ⋯ (Species…, Ground rules…) and the
## tool's section (its options, its mode, Apply, Only where); the view strip (GrassViewStrip); one undo action a
## stroke; a preset part. The Waailand plugin registers it.

signal preview_changed            # the plugin keeps GrassEditorPreview in the project metadata
signal tool_done(tool_id: String)  # a one-shot tool (Pick) finished: the overlay returns to the tool before
signal ground_rules_requested     # "Ground rules…": the plugin opens the open map's dialog
signal species_requested          # "Species…": the plugin opens the Species dialog (the project's active species)
signal library_changed            # the layer switched: the bar reads library() again (Terrain3D Extended 1.1)

## The layer the Grass tools paint: the ground's grass, or what floats on water.
enum Layer { GROUND, WATER }
## Density and Height: thicker or taller, thinner or shorter, back to ×1.
enum Adjust { MORE, LESS, RESET }
## What Smooth evens.
enum Smooth { DENSITY, HEIGHT }

const SpeciesCard := preload("res://addons/waailand/editor/grass_species_card.gd")

const ICON_DIR := "res://addons/waailand/editor/icons"
## The Terrain3D Extended tool-providers level these tools need (1.2: the bar's chip, the panel's header and ⋯, the
## view strip).
const NEEDS_LEVEL := 2
## The Grass workspace's tools, in their groups; ctrl inverts as Terrain3D's do.
const TOOLS := [
	{"id": "grass.species", "title": "Paint", "icon": "grass_species", "group": "paint",
		"description": "Paints the chosen species. Ctrl: erase back to the ground's own."},
	{"id": "grass.replace", "title": "Replace", "icon": "grass_replace", "group": "paint", "source_item": true,
		"description": "Swaps one painted species (From, in the bar) for the chosen one."},
	{"id": "grass.erase", "title": "Erase", "icon": "grass_erase", "group": "paint",
		"description": "Takes the painted species away: the ground's own grows again. Ctrl: paints the chosen species."},
	{"id": "grass.density", "title": "Density", "icon": "grass_density", "group": "shape",
		"description": "Thickens or thins the grass. Ctrl: the other way."},
	{"id": "grass.height", "title": "Height", "icon": "grass_height", "group": "shape",
		"description": "Makes the grass taller or shorter. Ctrl: the other way."},
	{"id": "grass.smooth", "title": "Smooth", "icon": "grass_smooth", "group": "shape",
		"description": "Evens out the density or the height."},
	{"id": "grass.force", "title": "Force", "icon": "grass_force", "group": "rules",
		"description": "Grass grows here whatever the ground (live roads excepted). Ctrl: back to the ground's rules."},
	{"id": "grass.remove", "title": "Remove", "icon": "grass_remove", "group": "rules",
		"description": "No grass at all, the ground's own included. Ctrl: back to ×1."},
	{"id": "grass.reset", "title": "Reset", "icon": "grass_reset", "group": "rules",
		"description": "Back to the ground's own rule: species, density, height and force."},
	{"id": "grass.pick", "title": "Pick", "icon": "grass_pick", "uses_size": false, "uses_strength": false, "hidden": true,
		"description": "Click the ground: the species it grows becomes the brush's, then back to the tool before."},
]
const NO_WATER_NOTE := "no water here"

var paint := GrassPaintTool.new()
var layer := Layer.GROUND
var _picked := {Layer.GROUND: -1, Layer.WATER: -1}   # each layer's species while the other is selected
var _no_water := false            # the Water layer's last projected hit found no water (the brush chip's note)
var _packs := {}                  # species name -> [pack title, source] (the picker's groups), read once
var types: GrassTypes
var _ui: Node = null
var _pictures := {}               # species name -> [tile, card] textures (loaded once; null when missing)
var _kinds: DecoKinds = null      # the hover card's flowers and ground, loaded with the first library
var _growth: GrassTerrainGrowth = null
var active_tool := ""             # the Grass tool the overlay activated ("" until one is)
var density_mode := Adjust.MORE   # grass.density
var height_mode := Adjust.MORE    # grass.height
var smooth_channel := Smooth.DENSITY   # grass.smooth
var limit_slope := false          # every painting tool: only where the ground's slope is in slope_range (degrees)
var slope_range := Vector2(0.0, 30.0)
var limit_height := false         # ... and its elevation in height_range (m)
var height_range := Vector2(0.0, 100.0)
var fill_region := false          # a click paints the whole region under the cursor
var map_date := Callable()        # () -> float: the open map's fixed date (-1: the clock); the plugin sets it
var _strip: GrassViewStrip = null # the view strip (build_view), while the overlay shows it


func _init(p_types: GrassTypes = null) -> void:
	types = p_types if p_types != null else GrassTypes.new()


## A tool_providers.gd script's level: its LEVEL, else 1 (Terrain3D Extended 1.1 and older); 0 for none.
static func overlay_level(p_providers: Script) -> int:
	return int(p_providers.get_script_constant_map().get("LEVEL", 1)) if p_providers != null else 0


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
	_strip_refresh()


func set_preview_visible(on: bool) -> void:
	GrassEditorPreview.visible = on
	preview_changed.emit()
	_strip_refresh()


func set_preview_all_grounds(on: bool) -> void:
	GrassEditorPreview.all_grounds = on
	preview_changed.emit()
	_strip_refresh()


## Provider API (Terrain3D Extended 1.2): the view strip at the top of the 3D view.
func build_view(box: HBoxContainer, kit: Object, accent: Color) -> void:
	_strip = GrassViewStrip.new()
	_strip.setup(self, kit, accent)
	box.add_child(_strip)


## The open map's fixed date (its Ground rules), or -1 while the clock runs.
func fixed_date() -> float:
	return float(map_date.call()) if map_date.is_valid() else -1.0


## The selected species' flowering date (GrassSpeciesPreview.bloom_day); -1 without flowers.
func bloom_day() -> float:
	return _bloom_day(paint.species)


## The selected species' flowering windows, one per flower kind: (bloom, bloom_end) in days; the whole year for a kind
## out every day.
func bloom_windows() -> Array:
	_load_kinds()
	var out := []
	for k in _kinds.kinds:
		if int(k["host"]) != paint.species:
			continue
		var keys: Vector4 = k["bloom"]
		out.append(Vector2(0.0, GrassSeason.YEAR) if keys.x < 0.0 else Vector2(keys.y, keys.z))
	return out


func _strip_refresh() -> void:
	if _strip != null and is_instance_valid(_strip):
		_strip.refresh()


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
	var maps := maps_of(b)
	if active_tool == "grass.pick":
		paint.apply_pick(maps.pixel(p_hit))
		_refresh()
		tool_done.emit("grass.pick")
		return
	var terrain: Object = b.get("terrain")
	_brush.maps = maps
	_brush.data = terrain.get("data") if terrain != null else null
	_brush.texel_ok = (func(pos: Vector3) -> bool: return not is_nan(float(b.call("water_surface", pos)))) \
		if layer == Layer.WATER else Callable()
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
		"library_tool": "grass.species", "pick_tool": "grass.pick", "panel_library": false, "icon_dir": ICON_DIR,
		"api": 3, "paints_itself": true}


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
			match density_mode:
				Adjust.RESET:
					return GrassPaintTool.Mode.DENSITY_RESET
				Adjust.LESS:
					return GrassPaintTool.Mode.DENSITY_UP if p_invert else GrassPaintTool.Mode.DENSITY_DOWN
			return GrassPaintTool.Mode.DENSITY_DOWN if p_invert else GrassPaintTool.Mode.DENSITY_UP
		"grass.height":
			match height_mode:
				Adjust.RESET:
					return GrassPaintTool.Mode.HEIGHT_RESET
				Adjust.LESS:
					return GrassPaintTool.Mode.TALLER if p_invert else GrassPaintTool.Mode.SHORTER
			return GrassPaintTool.Mode.SHORTER if p_invert else GrassPaintTool.Mode.TALLER
		"grass.smooth":
			if smooth_channel == Smooth.HEIGHT:
				return GrassPaintTool.Mode.SMOOTH_HEIGHT
			return GrassPaintTool.Mode.SMOOTH_DENSITY
		"grass.remove":
			return GrassPaintTool.Mode.RESTORE if p_invert else GrassPaintTool.Mode.REMOVE
		"grass.force":
			return GrassPaintTool.Mode.UNFORCE if p_invert else GrassPaintTool.Mode.FORCE
		"grass.replace":
			return GrassPaintTool.Mode.REPLACE
		"grass.reset":
			return GrassPaintTool.Mode.RESET
	return paint.mode


## The species as the library: each with its picture (its colour when there is none), a hover card and its pack (the
## picker's group); per layer its own key (favourites, order, recents), the footer and its action (Species…).
func library() -> Dictionary:
	_load_kinds()
	var items := []
	for e in _layer_palette():
		var nm := String(e["name"])
		var slot: int = e["slot"]
		var pics := _pictures_of(nm)
		var card_tex: Texture2D = pics[1]
		var facts := GrassSpeciesPreview.facts(types, _kinds, _growth, slot)
		var where: Array = _pack_of(nm)
		items.append({"id": slot, "name": nm.capitalize(),
			"picture": pics[0] if pics[0] != null else _swatch(e["colour"]),
			"card": func() -> Control: return SpeciesCard.make_card(card_tex, facts),
			"group": where[0], "group_note": where[1]})
	var water := layer == Layer.WATER
	return {"id": "species", "key": "grass.species.water" if water else "grass.species", "placeholder": "Search species",
		"tool": "grass.species", "items": items, "footer_action": "species",
		"footer": "%d active · %s layer" % [items.size(), "Water" if water else "Ground"]}


## A species' pack and where the pack comes from ([title, source]; ["", ""] when no installed pack has it).
func _pack_of(p_name: String) -> Array:
	if _packs.is_empty():
		for s in GrassBladesConfig.current().installed_sources():
			for pack in s["packs"]:
				for sp in (pack as GrassSpeciesPack).species:
					if sp != null and not _packs.has(String(sp.id)):
						_packs[String(sp.id)] = [String((pack as GrassSpeciesPack).name).capitalize(), String(s["name"])]
	return _packs.get(p_name, ["", ""])


func library_selected() -> int:
	return paint.species


func library_select(p_id: int) -> void:
	paint.species = p_id
	_refresh()
	_strip_refresh()


## The project's active species changed (the Species dialog): the library, the hover cards and the pictures follow;
## each layer keeps its selection while its species is still active; the bar is told.
func reload_species() -> void:
	var was := {}
	for l in [Layer.GROUND, Layer.WATER]:
		var slot: int = paint.species if l == layer else _picked[l]
		was[l] = String(types.rows[slot].get("name", "")) if slot >= 0 and slot < types.rows.size() else ""
	types = GrassTypes.new()
	_kinds = null
	_growth = null
	_pictures.clear()
	_packs.clear()
	for l in was:
		var now := types.names().find(was[l]) if was[l] != "" else -1
		if l == layer:
			var lib := _layer_palette()
			paint.species = now if now >= 0 else (int(lib[0]["slot"]) if not lib.is_empty() else 0)
		else:
			_picked[l] = now
	library_changed.emit()
	_refresh()
	_strip_refresh()


## Switches the layer the tools paint: the library shows its species (the bar is told), the selection is the one it
## had.
func set_layer(p_layer: Layer) -> void:
	if p_layer == layer:
		return
	_picked[layer] = paint.species
	layer = p_layer
	_no_water = false
	var lib := _layer_palette()
	var want: int = _picked[layer]
	if not lib.any(func(e): return int(e["slot"]) == want):
		want = int(lib[0]["slot"]) if not lib.is_empty() else 0
	paint.species = want
	library_changed.emit()
	_refresh()
	_strip_refresh()


## The palette of the selected layer's species (GrassPaintTool.palette).
func _layer_palette() -> Array:
	var want := GrassTypes.LAYER_SURFACE if layer == Layer.WATER else GrassTypes.LAYER_GROUND
	return GrassPaintTool.palette(types).filter(func(e): return int(e["layer"]) == want)


## The maps the selected layer paints on blades `b`: the grass maps, or the water maps.
func maps_of(b: Object) -> GrassMaps:
	return b.get("water_maps" if layer == Layer.WATER else "grass_maps")


## Terrain3D Extended 1.1 (tool providers API v3, optional): with Water selected a stroke lands where the view ray meets
## the water surface over the hit, not on the bed seen through the water; anywhere else, the hit.
func project_hit(p_from: Vector3, p_dir: Vector3, p_hit: Vector3) -> Vector3:
	if layer != Layer.WATER:
		return p_hit
	var b: Object = blades_of.call() if blades_of.is_valid() else null
	var s := float(b.call("water_surface", p_hit)) if b != null else NAN
	_no_water = is_nan(s)
	if is_nan(s) or absf(p_dir.y) < 1e-4:
		return p_hit
	var t := (s - p_from.y) / p_dir.y
	if t <= 0.0:
		return p_hit
	var q := p_from + p_dir * t
	var s2 := float(b.call("water_surface", q))
	return Vector3(q.x, s2 if not is_nan(s2) else s, q.z)


## Provider API (Terrain3D Extended 1.2): Replace's From, the bar's source chip.
func source_selected() -> int:
	return paint.replace_from


func source_select(p_id: int) -> void:
	paint.replace_from = p_id
	_refresh()


## Provider API (Terrain3D Extended 1.2): the panel's ⋯.
func workspace_actions() -> Array:
	return [{"id": "species", "title": "Species…", "tooltip": "Which installed species are active (the 32 slots)"},
		{"id": "ground_rules", "title": "Ground rules…", "tooltip": "What grows on this map's surfaces, and when"}]


func workspace_action(p_id: String) -> void:
	match p_id:
		"species":
			species_requested.emit()
		"ground_rules":
			ground_rules_requested.emit()


## Provider API (Terrain3D Extended 1.2): the brush chip's note, the Water layer off water.
func cursor_note() -> String:
	return NO_WATER_NOTE if layer == Layer.WATER and _no_water else ""


## Provider API (Terrain3D Extended 1.2): the row under the panel's header, every tool: the layer, and a banner when it
## has no active species.
func build_header(box: VBoxContainer, kit: Object, accent: Color) -> void:
	var seg: HBoxContainer = kit.segmented(["Ground", "Water"], 1 if layer == Layer.WATER else 0, accent,
		func(i: int) -> void: set_layer(Layer.WATER if i == 1 else Layer.GROUND))
	(seg.get_node("Seg0") as Button).tooltip_text = "The grass on the ground"
	(seg.get_node("Seg1") as Button).tooltip_text = "What floats on water (water sources and the sea)"
	box.add_child(seg)
	if _layer_palette().is_empty():
		var b: PanelContainer = kit.banner(_none_active_text(), "Species…" if _installed_on_layer() > 0 else "", accent)
		(b.find_child("Action", true, false) as Button).pressed.connect(func() -> void: species_requested.emit())
		box.add_child(b)


## The panel section for a Grass tool (Terrain3D Extended draws the header, the description, and the brush's shape and
## falloff above it): the tool's brush options, its mode, Apply and Only where. Pick has none.
func build_settings(box: VBoxContainer, p_tool: String, kit: Object, accent: Color) -> void:
	match p_tool:
		"grass.species":
			box.add_child(_toggle(kit, "Spray edge", paint.spray, accent, set_spray))
			box.add_child(_toggle(kit, "Also force growth", paint.force, accent, func(on: bool) -> void:
				paint.force = on
				_refresh()))
		"grass.erase", "grass.remove", "grass.force":
			box.add_child(_toggle(kit, "Spray edge", paint.spray, accent, set_spray))
		"grass.density":
			_mode(box, kit, accent, "Density", ["Thicker", "Thinner", "Back to ×1"], density_mode, func(i: int) -> void:
				density_mode = i as Adjust)
		"grass.height":
			_mode(box, kit, accent, "Height", ["Taller", "Shorter", "Back to ×1"], height_mode, func(i: int) -> void:
				height_mode = i as Adjust)
		"grass.smooth":
			_mode(box, kit, accent, "Smooth", ["Density", "Height"], smooth_channel, func(i: int) -> void:
				smooth_channel = i as Smooth)
		"grass.pick":
			return
	box.add_child(kit.section("Apply"))
	box.add_child(kit.segmented(["Under the brush", "Whole region"], 1 if fill_region else 0, accent,
		func(i: int) -> void:
			fill_region = i == 1
			_refresh()))
	box.add_child(kit.section("Only where"))
	box.add_child(_range(kit, accent, "Slope", 0.0, 90.0, "°", limit_slope, slope_range,
		func(on: bool, r: Vector2) -> void:
			limit_slope = on
			slope_range = r))
	box.add_child(_range(kit, accent, "Elevation", -100.0, 1000.0, " m", limit_height, height_range,
		func(on: bool, r: Vector2) -> void:
			limit_height = on
			height_range = r))


## A tool's mode: its heading and a segmented control; a pick sets it through `p_set` and refreshes the brush.
func _mode(box: VBoxContainer, kit: Object, accent: Color, p_title: String, p_options: Array, p_selected: int,
		p_set: Callable) -> void:
	box.add_child(kit.section(p_title))
	box.add_child(kit.segmented(p_options, p_selected, accent, func(i: int) -> void:
		p_set.call(i)
		_refresh()))


## A limit: its switch and range (kit.range_row); either change goes through `p_set(on, range)` and refreshes.
func _range(kit: Object, accent: Color, p_name: String, lo: float, hi: float, suffix: String, p_on: bool,
		p_r: Vector2, p_set: Callable) -> Control:
	var row: VBoxContainer = kit.range_row(p_name, lo, hi, 1.0, p_r, suffix, accent, p_on)
	var sw := row.get_node("Head/Toggle") as CheckBox
	var rs: Control = row.get_node("Range")
	sw.toggled.connect(func(on: bool) -> void:
		p_set.call(on, rs.get("value"))
		_refresh())
	rs.connect("value_changed", func(v: Vector2) -> void:
		p_set.call(sw.button_pressed, v)
		_refresh())
	return row


## How many installed species belong to the selected layer.
func _installed_on_layer() -> int:
	var want := GrassTypes.LAYER_SURFACE if layer == Layer.WATER else GrassTypes.LAYER_GROUND
	return GrassSpeciesCatalog.installed_layers().values().filter(func(l): return int(l) == want).size()


## The selected layer has no active species: what the banner says.
func _none_active_text() -> String:
	var n := _installed_on_layer()
	var what := "floating species" if layer == Layer.WATER else "species"
	if n == 0:
		return "No %s is installed: a pack brings some." % what
	return "No %s is active; %d %s installed." % [what, n, "is" if n == 1 else "are"]


## Its part of a preset: the layer, the species, spray and force, the modes, From, the limits and the fill.
func capture(_tool: String) -> Dictionary:
	return {"layer": layer, "species": paint.species, "spray": paint.spray, "density_mode": density_mode,
		"height_mode": height_mode, "smooth_channel": smooth_channel, "force": paint.force,
		"replace_from": paint.replace_from, "limit_slope": limit_slope, "slope_range": slope_range,
		"limit_height": limit_height, "height_range": height_range, "fill_region": fill_region}


## A preset's part; one saved by Waailand 1.4 (reset_density, reset_height, smooth_height) keeps its meaning.
func apply(_tool: String, state: Dictionary) -> void:
	if state.has("layer"):
		var l := int(state["layer"])
		if l != layer:
			_picked[layer] = paint.species
			layer = Layer.WATER if l == Layer.WATER else Layer.GROUND
			library_changed.emit()
	paint.species = int(state.get("species", paint.species))
	paint.spray = bool(state.get("spray", paint.spray))
	if state.has("density_mode"):
		density_mode = int(state["density_mode"]) as Adjust
	elif state.has("reset_density"):
		density_mode = Adjust.RESET if bool(state["reset_density"]) else Adjust.MORE
	if state.has("height_mode"):
		height_mode = int(state["height_mode"]) as Adjust
	elif state.has("reset_height"):
		height_mode = Adjust.RESET if bool(state["reset_height"]) else Adjust.MORE
	if state.has("smooth_channel"):
		smooth_channel = int(state["smooth_channel"]) as Smooth
	elif state.has("smooth_height"):
		smooth_channel = Smooth.HEIGHT if bool(state["smooth_height"]) else Smooth.DENSITY
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
	_strip_refresh()


static func _toggle(kit: Object, p_label: String, p_on: bool, p_accent: Color, p_fn: Callable) -> Control:
	var row: HBoxContainer = kit.toggle_row(p_label, p_on, p_accent)
	(row.get_node("Toggle") as CheckBox).toggled.connect(p_fn)
	return row


## A plain colour tile for a species without a picture.
static func _swatch(c: Color) -> Texture2D:
	var img := Image.create_empty(8, 8, false, Image.FORMAT_RGB8)
	img.fill(c)
	return ImageTexture.create_from_image(img)
