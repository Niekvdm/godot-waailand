# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name GrassSpeciesLibrary
extends RefCounted
## The Species dialog's left column: every installed species as a tree of where it comes from (the config's packs,
## each pack addon and its packs, the starter grass). A row shows its layer counts, how many of its species are active,
## a handle to drag the whole pack onto the slots and "+ all"; it opens in place to its species' tiles. On top a search
## (id and name) and the layer chips; while either narrows the list, the rows with a match open by themselves. A slot
## dragged here is emptied.

const ROW := Color(1.0, 1.0, 1.0, 0.04)
const NONE := Color(0.0, 0.0, 0.0, 0.0)
const INDENT := 16
const FILTERS := [["All", "all"], ["Ground", "ground"], ["Underwater", "under"], ["Floating", "float"],
	["Not active", "inactive"]]


static func build(d: GrassSpeciesDialog) -> Control:
	var col := GrassSpeciesDropArea.new().setup(PackedStringArray(["waailand_slot"]), func(data: Dictionary) -> void:
		d.empty_slot(int(data["slot"])), GrassSpeciesDialog.box(NONE),
		GrassSpeciesDialog.box(Color(d.accent, 0.12), d.accent))
	col.name = "Library"
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 6)
	col.add_child(v)
	var n := 0
	var packs := 0
	for s in d.sources:
		for p in s["packs"]:
			packs += 1
			n += (p as GrassSpeciesPack).species.size()
	v.add_child(d.kit.section("Installed · %d species in %d packs" % [n, packs]))
	var q: LineEdit = d.kit.search_field("Search species")
	q.name = "Search"
	q.text = d.search
	q.text_changed.connect(d.search_changed)
	v.add_child(q)
	var chips := HBoxContainer.new()
	chips.name = "Filters"
	chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var group := ButtonGroup.new()
	for pair in FILTERS:
		var b: Button = d.kit.toggle_chip(pair[0], d.filter == pair[1], d.accent)
		b.name = "Filter" + String(pair[1]).capitalize()
		b.button_group = group
		b.mouse_filter = Control.MOUSE_FILTER_PASS
		var f: String = pair[1]
		b.pressed.connect(func() -> void:
			d.filter = f
			d.rebuild())
		chips.add_child(b)
	v.add_child(chips)
	var sc := ScrollContainer.new()
	sc.name = "LibraryScroll"
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var tree := VBoxContainer.new()
	tree.name = "Tree"
	tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tree.add_theme_constant_override("separation", 3)
	sc.add_child(tree)
	v.add_child(sc)
	var narrowed := d.search.strip_edges() != "" or d.filter != "all"
	for s in d.sources:
		var addon := String(s["kind"]) == "addon"
		var shown: Array = (s["packs"] as Array).filter(func(p): return not narrowed or _matches(d, p) > 0)
		if shown.is_empty():
			continue
		if not addon:
			_pack(d, tree, shown[0], 0, narrowed)
			continue
		var ids := []
		for p in s["packs"]:
			ids.append_array(_ids(p))
		var key := GrassSpeciesDialog.source_key(s)
		var open: bool = narrowed or d.opened.get(key, true)
		tree.add_child(_row(d, key, String(s["name"]), ids, open, 0, "Source_" + String(s["name"])))
		if open:
			for p in shown:
				_pack(d, tree, p, INDENT, narrowed)
	if tree.get_child_count() == 0:
		tree.add_child(d.hint("No installed species match."))
	return col


## A pack's row and, open, its tiles.
static func _pack(d: GrassSpeciesDialog, tree: VBoxContainer, p: GrassSpeciesPack, indent: int, narrowed: bool) -> void:
	var key := GrassSpeciesDialog.pack_key(p)
	var open: bool = narrowed or d.opened.get(key, false)
	tree.add_child(_row(d, key, p.name, _ids(p), open, indent, "Pack_" + p.name))
	if not open:
		return
	var flow := HFlowContainer.new()
	flow.name = ("Tiles_" + p.name).validate_node_name()
	flow.add_theme_constant_override("h_separation", 4)
	flow.add_theme_constant_override("v_separation", 4)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", indent + INDENT)
	pad.add_child(flow)
	for sp in p.species:
		if sp == null or sp.id == &"" or (narrowed and not d.shows(sp)):
			continue
		var id := sp.id
		var t := GrassSpeciesTile.make(id, d.species_picture(id), d.caption(id), -1, GrassActiveSet.layer_of(sp),
			GrassActiveSet.kinds_in(sp))
		t.mark(d.active.slot_of(id) >= 0, false, false, d.accent, Color.WHITE if d.highlight == id else Color(0, 0, 0, 0))
		t.activated.connect(func() -> void: d.drop_species(id))
		t.card = func() -> Control: return d.card_for(id)
		flow.add_child(t)
	tree.add_child(pad)


## A tree row: open/close with the name, the layer counts, active of all, the handle and + all.
static func _row(d: GrassSpeciesDialog, key: String, title: String, ids: Array, open: bool, indent: int,
		nm: String) -> Control:
	var panel := PanelContainer.new()
	panel.name = nm.validate_node_name()
	panel.add_theme_stylebox_override("panel", GrassSpeciesDialog.box(ROW))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	panel.add_child(h)
	if indent > 0:
		var gap := Control.new()
		gap.custom_minimum_size.x = indent
		gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(gap)
	var toggle := Button.new()
	toggle.name = "Toggle"
	toggle.flat = true
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	toggle.text = ("▾ " if open else "▸ ") + title
	toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toggle.clip_text = true
	toggle.mouse_filter = Control.MOUSE_FILTER_PASS     # a slot dragged out and dropped on a row still empties
	toggle.pressed.connect(func() -> void:
		d.opened[key] = not open
		d.rebuild())
	h.add_child(toggle)
	var counts := {"ground": 0, "under": 0, "float": 0}
	var on := 0
	for id in ids:
		var l := GrassActiveSet.layer_of(d.active.species(id))
		counts["ground" if l == "wet" else l] += 1
		if d.active.slot_of(id) >= 0:
			on += 1
	h.add_child(_count(counts["ground"], Color(0, 0, 0, 0)))
	for l in ["under", "float"]:
		if counts[l] > 0:
			h.add_child(_count(counts[l], GrassSpeciesTile.FOLD[l]))
	var act := Label.new()
	act.name = "Active"
	act.text = "%d/%d active" % [on, ids.size()]
	act.modulate = GrassSpeciesDialog.DIM
	act.add_theme_font_size_override("font_size", 10)
	act.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(act)
	var grip := _Grip.new()
	grip.name = "Grip"
	grip.ids = ids
	grip.title = title
	h.add_child(grip)
	var all: Button = d.kit.chip("+ all", false, d.accent)
	all.name = "AddAll"
	all.tooltip_text = "Make every species of %s active (all or none)" % title
	all.disabled = on == ids.size()
	all.mouse_filter = Control.MOUSE_FILTER_PASS
	all.pressed.connect(func() -> void: d.drop_pack(ids, title))
	h.add_child(all)
	return panel


## A layer count: its number, after a coloured square (none: plain ground).
static func _count(n: int, c: Color) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 2)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if c.a > 0.0:
		var sq := ColorRect.new()
		sq.color = c
		sq.custom_minimum_size = Vector2(7, 7)
		sq.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sq.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(sq)
	var l := Label.new()
	l.text = str(n)
	l.add_theme_font_size_override("font_size", 10)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	return h


static func _ids(p: GrassSpeciesPack) -> Array:
	var out := []
	for sp in p.species:
		if sp != null and sp.id != &"":
			out.append(sp.id)
	return out


static func _matches(d: GrassSpeciesDialog, p: GrassSpeciesPack) -> int:
	return p.species.filter(func(sp): return d.shows(sp)).size()


## A row's handle: drags the pack ({kind "waailand_pack", ids, name}) onto the slots.
class _Grip:
	extends Label
	var ids: Array = []
	var title := ""

	func _init() -> void:
		text = "≡"
		tooltip_text = "Drag onto the slots: every species of it, all or none"
		mouse_filter = Control.MOUSE_FILTER_PASS
		mouse_default_cursor_shape = Control.CURSOR_DRAG
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _get_drag_data(_at: Vector2) -> Variant:
		if is_inside_tree():
			var l := Label.new()
			l.text = title
			set_drag_preview(l)
		return {"kind": "waailand_pack", "ids": ids, "name": title}
