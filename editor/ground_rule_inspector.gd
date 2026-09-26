# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name GroundRuleInspector
extends RefCounted
## The Rules tab's right column: the selected rule, with its name (Enter or leaving
## the box renames it), its surfaces (drag out; drop in on +), Default grass, Density, the species mix (GroundMixEditor)
## and its elevation band. Everything else (-1) has no name, surfaces or band; a water kind has its name, Density and
## its floating mix.


static func build(d: GroundRulesDialog, i: int) -> Control:
	var sc := ScrollContainer.new()
	sc.name = "InspectorScroll"
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var v := VBoxContainer.new()
	v.name = "Inspector"
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)
	sc.add_child(v)
	if i >= d.rules.rules.size():
		i = -1
	var r: Dictionary = d.rules.rules[i] if i >= 0 else d.rules.everything_else
	if d.rules.is_water(i):
		v.add_child(d.kit.section("Water kind"))
		v.add_child(_name_row(d, i, r))
		v.add_child(d.hint("Its water sources carry this name (their water_kind); what it floats grows on them."))
		v.add_child(_density(d, i, r))
		v.add_child(d.kit.section("Floating mix"))
		v.add_child(GroundMixEditor.build(d, i, false))
		return sc
	v.add_child(d.kit.section("Rule" if i >= 0 else "Everything else"))
	if i >= 0:
		v.add_child(_name_row(d, i, r))
		v.add_child(_surfaces(d, i, r))
	else:
		v.add_child(d.hint("Every surface in no rule: %s" % ", ".join(d.rules.unassigned(d.surface_names()))))
	var own: HBoxContainer = d.kit.toggle_row("Default grass", bool(r.get("default_grass", true)))
	own.name = "DefaultGrass"
	var cb: CheckBox = own.get_node("Toggle")
	cb.disabled = not d.rules.default_grass
	cb.toggled.connect(func(on: bool) -> void:
		d.change(func() -> void: d.rules.set_field(i, "default_grass", on)))
	v.add_child(own)
	if not d.rules.default_grass:
		v.add_child(d.hint("The map's default grass is off (the switch at the top): only painted grass grows."))
	elif not bool(r.get("default_grass", true)):
		v.add_child(d.hint("Only painted species and forced spots grow here."))
	v.add_child(_density(d, i, r))
	v.add_child(d.kit.section("Species mix"))
	v.add_child(GroundMixEditor.build(d, i, false))
	if i >= 0:
		v.add_child(d.kit.section("Elevation band"))
		v.add_child(_band(d, i, r))
	return sc


## The rule's density slider, written on release.
static func _density(d: GroundRulesDialog, i: int, r: Dictionary) -> Control:
	var dens: VBoxContainer = d.kit.slider_row("Density (×)", 0.0, 1.0, 0.05, float(r.get("density", 1.0)), "", d.accent)
	dens.name = "Density"
	var sl: HSlider = dens.get_node("Slider")
	sl.scrollable = false
	sl.drag_ended.connect(func(moved: bool) -> void:
		if moved:
			d.change(func() -> void: d.rules.set_field(i, "density", sl.value)))
	return dens


static func _name_row(d: GroundRulesDialog, i: int, r: Dictionary) -> Control:
	var head := HBoxContainer.new()
	var dot := GroundRulesRulesTab._dot(d.rule_colour(i))
	head.add_child(dot)
	var nm := LineEdit.new()
	nm.name = "Name"
	nm.text = String(r["name"])
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.tooltip_text = "Enter to rename"
	var commit := func(t: String) -> void:
		var s := t.strip_edges()
		if s != "" and s != String(d.rules.rules[i]["name"]):
			d.change(func() -> void: d.rules.set_field(i, "name", s))
	nm.text_submitted.connect(commit)
	nm.focus_exited.connect(func() -> void: commit.call(nm.text))
	head.add_child(nm)
	var del := Button.new()
	del.name = "Delete"
	del.text = "Delete"
	del.tooltip_text = "Delete the rule: its surfaces go to Everything else"
	del.focus_mode = Control.FOCUS_NONE
	del.pressed.connect(func() -> void:
		d.change(func() -> void:
			d.rules.delete_rule(i)
			d.selected = -1))
	head.add_child(del)
	return head


static func _surfaces(d: GroundRulesDialog, i: int, r: Dictionary) -> Control:
	var tiles := HFlowContainer.new()
	tiles.name = "RuleSurfaces"
	for s in r["surfaces"]:
		var nm := String(s)
		var t := GroundTile.make("ground_surface", nm, d.surface_picture(nm), nm, 46, Color(0, 0, 0, 0), true)
		if not d.has_surface(nm):
			t.modulate.a = 0.4
			t.tooltip_text = "%s: not on this map" % nm
		tiles.add_child(t)
	var plus := GroundDropTarget.new().setup("ground_surface", func(id: String) -> void:
		d.change(func() -> void: d.rules.move_surface(id, i)),
		GroundRulesDialog.box(Color(d.accent, 0.05), Color(d.accent, 0.5)), GroundRulesDialog.box(Color(d.accent, 0.16), d.accent))
	plus.name = "AddSurface"
	plus.custom_minimum_size = Vector2(46, 46)
	plus.tooltip_text = "Drop a surface here"
	var l := Label.new()
	l.text = "+"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	plus.add_child(l)
	tiles.add_child(plus)
	return tiles


static func _band(d: GroundRulesDialog, i: int, r: Dictionary) -> Control:
	var b: Dictionary = r.get("band", {})
	if b.is_empty():
		var add := Button.new()
		add.name = "AddBand"
		add.text = "+ a different mix above … m"
		add.flat = true
		add.focus_mode = Control.FOCUS_NONE
		add.pressed.connect(func() -> void:
			d.change(func() -> void: d.rules.set_band(i, 500.0)))
		return add
	var v := VBoxContainer.new()
	var h := HBoxContainer.new()
	var above: VBoxContainer = d.kit.slider_row("Above", 0.0, 1000.0, 10.0, float(b["above_m"]), "m", d.accent)
	above.name = "BandAbove"
	above.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var asl: HSlider = above.get_node("Slider")
	asl.scrollable = false
	asl.drag_ended.connect(func(moved: bool) -> void:
		if moved:
			d.change(func() -> void: d.rules.set_band(i, asl.value)))
	h.add_child(above)
	var rm := Button.new()
	rm.name = "RemoveBand"
	rm.text = "✕"
	rm.tooltip_text = "Remove the band"
	rm.focus_mode = Control.FOCUS_NONE
	rm.pressed.connect(func() -> void:
		d.change(func() -> void: d.rules.set_band(i, -1.0)))
	h.add_child(rm)
	v.add_child(h)
	v.add_child(GroundMixEditor.build(d, i, true))
	return v
