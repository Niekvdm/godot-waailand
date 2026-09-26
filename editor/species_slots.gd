# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name GrassSpeciesSlots
extends RefCounted
## The Species dialog's right column: the 32 active slots, 8 by 4. Above them the active species per layer; on them a
## species or a pack is dropped (a filled slot asks first), from them a slot is dragged out to empty it, and a
## right-click opens the slot menu. Below them the replace question or the refusal, the names that are not active,
## and a hint.

const COLUMNS := 8
const GAP := 4
const HINT := "Drag species onto the slots, or a pack by its ≡ handle; double-click a species for the first free " \
	+ "slot. Drag a slot out to empty it; right-click it for the fallback. Grass painted on a slot grows its species."
const WARN_MAX := 6


static func build(d: GrassSpeciesDialog) -> Control:
	var v := VBoxContainer.new()
	v.name = "Slots"
	v.add_theme_constant_override("separation", 6)
	v.custom_minimum_size.x = COLUMNS * GrassSpeciesTile.SLOT_PX + (COLUMNS - 1) * GAP + 20
	v.add_child(d.kit.section("Active · %d of %d slots" % [d.active.used_slots(), GrassActiveSet.SLOTS]))
	var lc := d.active.layer_counts()
	var counts := Label.new()
	counts.name = "LayerCounts"
	counts.text = "Ground %d · Underwater %d · Floating %d" % [lc["ground"], lc["under"], lc["float"]]
	counts.modulate = GrassSpeciesDialog.DIM
	counts.add_theme_font_size_override("font_size", 11)
	v.add_child(counts)
	var area := GrassSpeciesDropArea.new().setup(PackedStringArray(["waailand_species", "waailand_pack"]),
		func(data: Dictionary) -> void: d.drop_on(-1, data), GrassSpeciesDialog.box(Color(0, 0, 0, 0.18)),
		GrassSpeciesDialog.box(Color(d.accent, 0.12), d.accent))
	area.name = "Grid"
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", GAP)
	grid.add_theme_constant_override("v_separation", GAP)
	area.add_child(grid)
	for i in GrassActiveSet.SLOTS:
		grid.add_child(_slot(d, i))
	v.add_child(area)
	if not d.pending.is_empty():
		v.add_child(_confirm(d))
	elif d.error != "":
		var e := Label.new()
		e.name = "Error"
		e.text = d.error
		e.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		e.add_theme_color_override("font_color", GrassSpeciesDialog.ERROR)
		e.add_theme_font_size_override("font_size", 11)
		v.add_child(e)
	var warn := d.warnings()
	if not warn.is_empty():
		var w := Label.new()
		w.name = "Warnings"
		var more := " and %d more" % (warn.size() - WARN_MAX) if warn.size() > WARN_MAX else ""
		w.text = "Named but not active, so they grow nothing: %s%s." % [", ".join(warn.slice(0, WARN_MAX)), more]
		w.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		w.add_theme_color_override("font_color", GrassSpeciesDialog.AMBER)
		w.add_theme_font_size_override("font_size", 11)
		v.add_child(w)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(spacer)
	var h := d.hint(HINT)
	h.name = "Hint"
	v.add_child(h)
	return v


## Slot i: its species (the fallback framed, a missing one dashed red with its id), or empty and dashed.
static func _slot(d: GrassSpeciesDialog, i: int) -> GrassSpeciesTile:
	var id := d.active.slots[i]
	var sp := d.active.species(id)
	var missing := d.active.is_missing(i)
	var t := GrassSpeciesTile.make(id, d.species_picture(id) if sp != null else null,
		(String(id) if missing else d.caption(id)) if id != &"" else "", i, GrassActiveSet.layer_of(sp),
		GrassActiveSet.kinds_in(sp))
	t.mark(false, id != &"" and d.active.fallback == id, missing, d.accent,
		GrassSpeciesDialog.ERROR if d.red_slot == i else Color(0, 0, 0, 0))
	if missing:
		t.tooltip_text = "%s is not installed (its pack is gone): empty the slot, or install the pack again" % id
	t.on_drop = func(data: Dictionary) -> void: d.drop_on(i, data)
	t.menu_requested.connect(func(at: Vector2) -> void: d.open_slot_menu(i, at))
	if sp != null:
		t.card = func() -> Control: return d.card_for(id)
	return t


## The replace question: what the slot's painted grass will grow, and Replace or Cancel.
static func _confirm(d: GrassSpeciesDialog) -> Control:
	var panel := PanelContainer.new()
	panel.name = "Confirm"
	panel.add_theme_stylebox_override("panel", GrassSpeciesDialog.box(Color(1, 1, 1, 0.06), GrassSpeciesDialog.AMBER))
	var v := VBoxContainer.new()
	panel.add_child(v)
	var l := Label.new()
	l.text = d.replace_text()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 11)
	v.add_child(l)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_END
	for pair in [["Replace", d.confirm_replace], ["Cancel", d.cancel_replace]]:
		var b := Button.new()
		b.name = pair[0]
		b.text = pair[0]
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(pair[1])
		h.add_child(b)
	v.add_child(h)
	return panel
