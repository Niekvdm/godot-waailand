# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name GrassSpeciesDialog
extends Control
## The Species dialog: centred and modal over the editor like the Ground rules dialog, it edits the project's active
## species (GrassActiveSet, the slot table): the installed packs as a tree on the left (GrassSpeciesLibrary), the 32
## slots on the right (GrassSpeciesSlots). Every change is one undo step: the set is snapshotted, changed, written and
## the editor's grass reloaded (`save`), then the view is rebuilt from the set. A change the budgets refuse changes
## nothing and says what it needs and what is free. Built in code with the overlay's components (`kit`); the Waailand
## plugin opens it (context_for), tests drive it headless.

signal closed

const UNDO_MAX := 100
const SIZE := Vector2(1080, 680)
const BACKDROP := Color(0.0, 0.0, 0.0, 0.45)
const DIM := Color(1.0, 1.0, 1.0, 0.55)
const ERROR := Color("ff8a80")
const AMBER := Color("ffb74d")
const AMBER_FROM := 29
const PANEL_ALPHA := 0.94
## The Terrain3D Extended overlay's modal group (tool_providers.gd MODAL_GROUP): while the dialog is in it, the
## overlay hides and the terrain takes no 3D input.
const UX_MODAL_GROUP := &"terrain_3d_ux_modal"
## The slot menu's items.
enum Menu { FALLBACK, SHOW, EMPTY }

const SpeciesCard := preload("res://addons/waailand/editor/grass_species_card.gd")

var active: GrassActiveSet
var sources: Array = []           # GrassBladesConfig.installed_sources()
var kit: Object                   # the overlay's UxComponents
var accent := Color("8bc34a")
var picture := Callable()         # species id -> its tile picture (null: a plain tile)
var card_picture := Callable()    # species id -> its card's picture
var save := Callable()            # (GrassActiveSet) -> Error: write the table, reload the editor's grass
var uses := {}                    # where species are named: label -> its document (a growth table, ground rules, ...)
var path := ""
var search := ""
var filter := "all"               # "all" | "ground" | "under" | "float" | "inactive"
var opened := {}                  # a tree row's key -> open
var highlight: StringName = &""   # the species "Show in the library" points at
var error := ""                   # the last refusal, or a write error
var red_slot := -1                # the slot a refused drop aimed at
var pending := {}                 # a replace waiting to be confirmed: {slot, id}
var _undo: Array = []
var _redo: Array = []
var _panel: PanelContainer
var _content: VBoxContainer
var _rebuilding := false
var _menu: PopupMenu = null
var _menu_slot := -1
var _no_growth: GrassTerrainGrowth = null
var _search_queued := false


func setup(p: Dictionary) -> void:
	active = p["active"]
	sources = p.get("sources", [])
	kit = p["kit"]
	accent = p.get("accent", accent)
	picture = p.get("picture", Callable())
	card_picture = p.get("card_picture", Callable())
	save = p.get("save", Callable())
	uses = p.get("uses", {})
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
		top_level = true
		set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	elif what == NOTIFICATION_RESIZED and _panel != null and is_inside_tree():
		_panel.custom_minimum_size = SIZE.min(get_viewport_rect().size - Vector2(40.0, 40.0))


## Rebuilds the view from the set (each change rebuilds it). Scroll positions are kept.
func rebuild() -> void:
	_rebuilding = true
	var scrolls := {}
	for sc in _content.find_children("*", "ScrollContainer", true, false):
		scrolls[String(sc.name)] = (sc as ScrollContainer).scroll_vertical
	for c in _content.get_children():
		_content.remove_child(c)
		c.queue_free()
	_content.add_child(_header())
	var body: Control
	if path == "":
		body = _message("The grass config names no slots_path: set it in waailand_config.tres to choose the active "
			+ "species.")
	elif sources.is_empty():
		body = _message("No species packs are installed.")
	else:
		var cols := HBoxContainer.new()
		cols.name = "Columns"
		cols.add_theme_constant_override("separation", 12)
		var lib := GrassSpeciesLibrary.build(self)
		lib.size_flags_horizontal = SIZE_EXPAND_FILL
		cols.add_child(lib)
		cols.add_child(GrassSpeciesSlots.build(self))
		body = cols
	body.size_flags_vertical = SIZE_EXPAND_FILL
	_content.add_child(body)
	for sc in _content.find_children("*", "ScrollContainer", true, false):
		if scrolls.has(String(sc.name)):
			(sc as ScrollContainer).set_deferred("scroll_vertical", scrolls[String(sc.name)])
	_rebuilding = false


func _header() -> Control:
	var h := HBoxContainer.new()
	h.name = "Header"
	h.add_theme_constant_override("separation", 10)
	var title := Label.new()
	title.text = "SPECIES"
	title.add_theme_color_override("font_color", accent)
	title.add_theme_font_size_override("font_size", 13)
	h.add_child(title)
	var where := Label.new()
	where.text = "· this project · %s" % path if path != "" else ""
	where.modulate = DIM
	where.clip_text = true
	where.size_flags_horizontal = SIZE_EXPAND_FILL
	h.add_child(where)
	h.add_child(_meter("MeterSpecies", "Species", active.used_slots(), GrassActiveSet.SLOTS, "species"))
	h.add_child(_meter("MeterKinds", "Flower kinds", active.used_kinds(), GrassActiveSet.KINDS, "kinds"))
	h.add_child(_button("Undo", "↶", undo, _undo.is_empty()))
	h.add_child(_button("Redo", "↷", redo, _redo.is_empty()))
	h.add_child(_button("Close", "✕", close, false))
	return h


## "Species 12/32": amber from AMBER_FROM, red past the budget or while a refusal names it.
func _meter(nm: String, text: String, n: int, of: int, budget: String) -> Label:
	var l := Label.new()
	l.name = nm
	l.text = "%s %d/%d" % [text, n, of]
	var red := n > of or (error != "" and active.over.split(",").has(budget))
	l.add_theme_color_override("font_color", ERROR if red else (AMBER if n >= AMBER_FROM else Color(1, 1, 1, 0.8)))
	l.add_theme_font_size_override("font_size", 12)
	return l


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
	l.name = "Message"
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


# --- what the hand does ---

## One undo step: `fn` changes the set and returns "" (done) or why not; refused, the set is as it was, the message
## shows and `p_slot` turns red. Done: written, the editor's grass reloaded, the view rebuilt.
func change(fn: Callable, p_slot := -1) -> bool:
	if _rebuilding:
		return false
	var before := active.snapshot()
	var why: String = fn.call()
	if why != "":
		active.restore(before)       # the set as it was; `over` still names the budget
		error = why
		red_slot = p_slot
		rebuild()
		return false
	_undo.append(before)
	if _undo.size() > UNDO_MAX:
		_undo.pop_front()
	_redo.clear()
	_commit()
	return true


func undo() -> void:
	if _undo.is_empty():
		return
	_redo.append(active.snapshot())
	active.restore(_undo.pop_back())
	_commit()


func redo() -> void:
	if _redo.is_empty():
		return
	_undo.append(active.snapshot())
	active.restore(_redo.pop_back())
	_commit()


func _commit() -> void:
	pending = {}
	red_slot = -1
	active.over = ""
	var err: int = save.call(active) if save.is_valid() else OK
	error = "" if err == OK else "Could not write %s: %s" % [path, error_string(err)]
	rebuild()


## A species dropped on slot `slot` (-1: the grid's free space, the first free slot) or double-clicked. A filled slot
## asks first (its paint will grow the new species).
func drop_species(id: StringName, slot := -1) -> void:
	pending = {}
	if slot >= 0 and active.slots[slot] != &"":
		if active.slots[slot] == id:
			return
		var before := active.snapshot()
		var why := active.replace(slot, id)
		active.restore(before)
		if why != "":
			error = why
			red_slot = slot
		else:
			error = ""
			pending = {"slot": slot, "id": id}
		rebuild()
		return
	change(func() -> String: return active.place(id, slot), slot)


## A pack's handle dropped, or its + all: its inactive species fill free slots in order, all or nothing.
func drop_pack(ids: Array, label: String) -> void:
	pending = {}
	change(func() -> String:
		var why := active.fill(ids, label)
		return why + " Drag single species, or free kinds first." if active.over != "" else why)


## What a drop on the slots does with its drag data (a slot tile: `slot`; the free space: -1).
func drop_on(slot: int, data: Dictionary) -> void:
	match String(data.get("kind", "")):
		"waailand_species":
			drop_species(StringName(String(data["id"])), slot)
		"waailand_pack":
			drop_pack(data["ids"], String(data["name"]))


func confirm_replace() -> void:
	if pending.is_empty():
		return
	var p := pending
	change(func() -> String: return active.replace(int(p["slot"]), p["id"]), int(p["slot"]))


func cancel_replace() -> void:
	pending = {}
	rebuild()


## The replace question: what painted grass will do.
func replace_text() -> String:
	if pending.is_empty():
		return ""
	var old := active.slots[int(pending["slot"])]
	return "Replace %s in slot %d with %s? Grass painted as %s on any map will grow as %s." \
		% [old, pending["slot"], pending["id"], old, pending["id"]]


func empty_slot(i: int) -> void:
	if active.slots[i] == &"":
		return
	change(func() -> String:
		active.empty(i)
		return "")


func make_fallback(i: int) -> void:
	change(func() -> String: return active.set_fallback(active.slots[i]), i)


## Opens the slot's species' pack in the library (search and filter cleared) and marks it.
func show_in_library(i: int) -> void:
	var id := active.slots[i]
	if id == &"":
		return
	search = ""
	filter = "all"
	highlight = id
	for s in sources:
		for pack in s["packs"]:
			if (pack as GrassSpeciesPack).species.any(func(sp): return sp != null and sp.id == id):
				opened[source_key(s)] = true
				opened[pack_key(pack)] = true
	rebuild()


## The slot menu at `at` (screen): Make fallback, Show in the library, Empty the slot.
func open_slot_menu(i: int, at: Vector2) -> void:
	if active.slots[i] == &"":
		return
	if _menu == null or not is_instance_valid(_menu):
		_menu = PopupMenu.new()
		_menu.name = "SlotMenu"
		_menu.id_pressed.connect(func(item: int) -> void: menu_action(_menu_slot, item))
		add_child(_menu)
	_menu_slot = i
	_menu.clear()
	var missing := active.is_missing(i)
	_menu.add_item("Make fallback", Menu.FALLBACK)
	_menu.set_item_disabled(_menu.get_item_index(Menu.FALLBACK), missing or active.fallback == active.slots[i])
	_menu.add_item("Show in the library", Menu.SHOW)
	_menu.set_item_disabled(_menu.get_item_index(Menu.SHOW), missing)
	_menu.add_item("Empty the slot", Menu.EMPTY)
	_menu.position = Vector2i(at)
	_menu.reset_size()
	_menu.popup()


func menu_action(i: int, item: int) -> void:
	match item:
		Menu.FALLBACK:
			make_fallback(i)
		Menu.SHOW:
			show_in_library(i)
		Menu.EMPTY:
			empty_slot(i)


## A search keystroke: the view is rebuilt after the field's signal (not inside it) and the new field keeps the typing.
func search_changed(t: String) -> void:
	search = t
	if _search_queued:
		return
	_search_queued = true
	(func() -> void:
		_search_queued = false
		rebuild()
		var q := _content.find_child("Search", true, false) as LineEdit
		if q != null and q.is_inside_tree():
			q.grab_focus()
			q.caret_column = q.text.length()).call_deferred()


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
		if not pending.is_empty():
			cancel_replace()
		else:
			close()
	elif not typing and k.ctrl_pressed and k.keycode == KEY_Z:
		if k.shift_pressed:
			redo()
		else:
			undo()
	elif not typing and k.ctrl_pressed and k.keycode == KEY_Y:
		redo()
	else:
		return
	if vp != null:
		vp.set_input_as_handled()


# --- helpers the columns use ---

## A species' name on its tile: its display name, else its id.
func caption(id: StringName) -> String:
	var sp := active.species(id)
	if sp != null and sp.display_name != "":
		return sp.display_name
	return String(id).replace("_", " ").capitalize()


func species_picture(id: StringName) -> Texture2D:
	return picture.call(String(id)) if picture.is_valid() else null


## The hover card of an installed species (null for a missing one): its picture, name, height, water and flowers
## (GrassSpeciesCard), then its slot, or that it is not active.
func card_for(id: StringName) -> Control:
	var sp := active.species(id)
	if sp == null:
		return null
	var one := GrassSpeciesPack.new()
	one.species.append(sp)
	var c := GrassSpeciesCatalog.build_active([one], {String(id): 0})
	var t := GrassTypes.from_catalog(c)
	if _no_growth == null:
		_no_growth = GrassTerrainGrowth.new("")
	var f := GrassSpeciesPreview.facts(t, DecoKinds.from_catalog(c, t), _no_growth, 0)
	f.erase("grows_on")
	var lines := SpeciesCard.card_lines(f)
	var slot := active.slot_of(id)
	if slot < 0:
		lines.append("Not active")
	else:
		lines.append("Active in slot %d%s" % [slot, " (the fallback)" if active.fallback == id else ""])
	var tex: Texture2D = card_picture.call(String(id)) if card_picture.is_valid() else null
	return SpeciesCard.panel_of(tex, lines)


## Whether species `sp` passes the search and the filter chip.
func shows(sp: GrassSpecies) -> bool:
	if sp == null:
		return false
	var q := search.strip_edges().to_lower()
	if q != "" and not String(sp.id).to_lower().contains(q) and not sp.display_name.to_lower().contains(q):
		return false
	var l := GrassActiveSet.layer_of(sp)
	match filter:
		"ground":
			return l == "ground" or l == "wet"
		"under", "float":
			return l == filter
		"inactive":
			return active.slot_of(sp.id) < 0
	return true


## A tree row's key: a source by its path, a pack by its file (or its name, for a pack built in code).
static func source_key(s: Dictionary) -> String:
	return "source:" + String(s["path"])


static func pack_key(p: GrassSpeciesPack) -> String:
	return "pack:" + (p.resource_path if p.resource_path != "" else p.name)


func warnings() -> PackedStringArray:
	return inactive_names(active, uses)


func hint(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.modulate = DIM
	l.add_theme_font_size_override("font_size", 11)
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


## Installed species that `p_uses` name but no slot holds (they grow nothing): "id (where, where)", sorted. `p_uses`:
## label -> a parsed document; every dictionary under a "species" or "default_species" key is a mix of names.
static func inactive_names(p_set: GrassActiveSet, p_uses: Dictionary) -> PackedStringArray:
	var where := {}
	for label in p_uses:
		var names := {}
		_names_in(p_uses[label], names)
		for nm in names:
			if p_set.is_installed(StringName(nm)) and p_set.slot_of(StringName(nm)) < 0:
				if not where.has(nm):
					where[nm] = PackedStringArray()
				where[nm].append(String(label))
	var ids := where.keys()
	ids.sort()
	var out := PackedStringArray()
	for nm in ids:
		out.append("%s (%s)" % [nm, ", ".join(where[nm])])
	return out


static func _names_in(v: Variant, into: Dictionary) -> void:
	if v is Dictionary:
		for k in v:
			if String(k) in ["species", "default_species"] and v[k] is Dictionary:
				for nm in v[k]:
					into[String(nm)] = true
			else:
				_names_in(v[k], into)
	elif v is Array:
		for x in v:
			_names_in(x, into)


## What the plugin opens the dialog with: the installed packs, the slot table as a GrassActiveSet, where species are
## named (the growth table, the open map's ground rules, the config's default mix), and a save that writes the table
## and then calls `p_on_saved` (the plugin reloads the editor's grass).
static func context_for(p_kit: Object, p_blades: GrassBlades, p_picture: Callable, p_on_saved: Callable) -> Dictionary:
	var cfg := GrassBladesConfig.current()
	var srcs := cfg.installed_sources()
	var installed := []
	for s in srcs:
		for pack in s["packs"]:
			installed.append_array((pack as GrassSpeciesPack).species)
	var p := cfg.slots_path
	var ctx := {"kit": p_kit, "sources": srcs, "path": p, "picture": p_picture,
		"card_picture": func(id: String) -> Texture2D: return GrassSpeciesPreview.card_texture(id),
		"active": GrassActiveSet.new(installed, GrassSlotTable.load_file(p), GrassSlotTable.load_fallback(p))}
	var uses := {}
	if cfg.growth_path != "" and FileAccess.file_exists(cfg.growth_path):
		uses["the growth table"] = JSON.parse_string(FileAccess.get_file_as_string(cfg.growth_path))
	var rp := p_blades.rules_path() if p_blades != null else ""
	if rp != "" and FileAccess.file_exists(rp):
		uses["this map's ground rules"] = JSON.parse_string(FileAccess.get_file_as_string(rp))
	if not cfg.default_mix.is_empty():
		uses["the config's default mix"] = {"species": cfg.default_mix}
	ctx["uses"] = uses
	ctx["save"] = func(a: GrassActiveSet) -> Error:
		var e := GrassSlotTable.save_file(p, a.to_table(), a.fallback)
		if e == OK:
			GrassSpeciesCatalog.generation += 1
			if p_on_saved.is_valid():
				p_on_saved.call()
		return e
	return ctx
