# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name GroundRulesRulesTab
extends RefCounted
## The Ground rules dialog's Rules tab: the map's
## surfaces (drag one onto a rule, onto "a new rule", or back here to unassign it), the rules with Everything else
## last (a click selects one), and the selected rule (GroundRuleInspector).

const ROW := Color(1.0, 1.0, 1.0, 0.04)
const EDGE := Color(1.0, 1.0, 1.0, 0.16)
const NONE := Color(0.0, 0.0, 0.0, 0.0)
const THUMBS := 4              # a row's surface pictures; the rest are "+N"


static func build(d: GroundRulesDialog) -> Control:
	var cols := HBoxContainer.new()
	cols.name = "RulesTab"
	cols.add_theme_constant_override("separation", 10)
	cols.add_child(_surfaces(d))
	cols.add_child(_rules(d))
	var insp := _inspector(d)
	insp.custom_minimum_size.x = 330.0
	cols.add_child(insp)
	return cols


static func _inspector(d: GroundRulesDialog) -> Control:
	return GroundRuleInspector.build(d, d.selected)


static func _surfaces(d: GroundRulesDialog) -> Control:
	var col := GroundDropTarget.new().setup("ground_surface", func(id: String) -> void:
		d.change(func() -> void: d.rules.move_surface(id, -1)), GroundRulesDialog.box(NONE),
		GroundRulesDialog.box(Color(d.accent, 0.12), d.accent))
	col.name = "Surfaces"
	col.custom_minimum_size.x = 232.0
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(v)
	var names := d.surface_names()
	var free := d.rules.unassigned(names)
	v.add_child(d.kit.section("Surfaces of this map · %d" % names.size()))
	var chips := HBoxContainer.new()
	chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var group := ButtonGroup.new()
	for pair in [["All", "all"], ["Unassigned · %d" % free.size(), "unassigned"]]:
		var b: Button = d.kit.toggle_chip(pair[0], d.surface_filter == pair[1], d.accent)
		b.button_group = group
		b.mouse_filter = Control.MOUSE_FILTER_PASS
		var f: String = pair[1]
		b.pressed.connect(func() -> void:
			d.surface_filter = f
			d.rebuild())
		chips.add_child(b)
	v.add_child(chips)
	var sc := ScrollContainer.new()
	sc.name = "SurfacesScroll"
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.mouse_filter = Control.MOUSE_FILTER_PASS
	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for s in d.surfaces:
		var nm := String(s["name"])
		var i := d.rules.rule_of(nm)
		if d.surface_filter == "unassigned" and i >= 0:
			continue
		flow.add_child(GroundTile.make("ground_surface", nm, s.get("picture"), nm, 46, d.rule_colour(i), true))
	sc.add_child(flow)
	v.add_child(sc)
	var tip := d.hint("Drag onto a rule · back here to unassign")
	v.add_child(tip)
	return col


static func _rules(d: GroundRulesDialog) -> Control:
	var v := VBoxContainer.new()
	v.name = "Rules"
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var head := HBoxContainer.new()
	var lab: Label = d.kit.section("Rules · %d" % d.rules.rules.size())
	lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(lab)
	var add: Button = d.kit.chip("+ New rule", false, d.accent)
	add.name = "NewRule"
	add.pressed.connect(func() -> void:
		d.change(func() -> void: d.selected = d.rules.add_rule("New rule")))
	head.add_child(add)
	v.add_child(head)
	var sc := ScrollContainer.new()
	sc.name = "RulesScroll"
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	for i in d.rules.rules.size():
		list.add_child(_row(d, i))
	var zone := GroundDropTarget.new().setup("ground_surface", func(id: String) -> void:
		d.change(func() -> void: d.selected = d.rules.new_rule_from(id)),
		GroundRulesDialog.box(Color(d.accent, 0.05), Color(d.accent, 0.5)),
		GroundRulesDialog.box(Color(d.accent, 0.16), d.accent))
	zone.name = "NewRuleZone"
	zone.custom_minimum_size.y = 34.0
	var zl := Label.new()
	zl.text = "drop a surface here → a new rule"
	zl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	zl.add_theme_font_size_override("font_size", 11)
	zl.modulate = GroundRulesDialog.DIM
	zone.add_child(zl)
	list.add_child(zone)
	list.add_child(_row(d, -1))
	sc.add_child(list)
	v.add_child(sc)
	return v


## A rule's row (-1: Everything else): its dot, name, surface thumbnails, band, mix bar and state. A drop moves a surface
## into it; a click selects it.
static func _row(d: GroundRulesDialog, i: int) -> Control:
	var r: Dictionary = d.rules.rules[i] if i >= 0 else d.rules.everything_else
	var sel := d.selected == i
	var normal := GroundRulesDialog.box(Color(d.accent, 0.14) if sel else ROW, d.accent if sel else (EDGE if i < 0 else NONE))
	var row := GroundDropTarget.new().setup("ground_surface" if i >= 0 else "", func(id: String) -> void:
		d.change(func() -> void: d.rules.move_surface(id, i)), normal, GroundRulesDialog.box(Color(d.accent, 0.2), d.accent))
	row.name = ("Rule%d" % i) if i >= 0 else "EverythingElse"
	row.pressed.connect(func() -> void:
		d.selected = i
		d.rebuild())
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", 7)
	h.add_child(_dot(d.rule_colour(i) if i >= 0 else Color(0.62, 0.62, 0.62)))
	var nm := Label.new()
	nm.text = String(r["name"]) if i >= 0 else "Everything else"
	nm.add_theme_font_size_override("font_size", 13)
	nm.custom_minimum_size.x = 110.0
	nm.clip_text = true
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.tooltip_text = nm.text
	h.add_child(nm)
	if i >= 0:
		var surf: Array = r["surfaces"]
		for j in mini(surf.size(), THUMBS):
			h.add_child(_thumb(d, String(surf[j])))
		if surf.size() > THUMBS:
			h.add_child(d.note("+%d" % (surf.size() - THUMBS)))
	else:
		h.add_child(d.note("%d surfaces" % d.rules.unassigned(d.surface_names()).size()))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(gap)
	if i >= 0 and not (r.get("band", {}) as Dictionary).is_empty():
		h.add_child(d.note("band %d m" % int(r["band"]["above_m"])))
	h.add_child(mix_bar(d, d.mix_of(i), 70.0))
	h.add_child(_state(d, r))
	row.add_child(h)
	return row


static func _state(d: GroundRulesDialog, r: Dictionary) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", 10)
	if float(r.get("density", 1.0)) <= 0.0:
		l.text = "grows nothing"
		l.modulate = GroundRulesDialog.DIM
	elif not d.rules.default_grass or not bool(r.get("default_grass", true)):
		l.text = "painted only"
		l.modulate = GroundRulesDialog.DIM
	else:
		l.text = "×%.2f" % float(r["density"])
	return l


static func _dot(c: Color) -> Control:
	var p := Panel.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.custom_minimum_size = Vector2(9, 9)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(5)
	p.add_theme_stylebox_override("panel", sb)
	return p


## A surface's small picture in a rule row (display only); greyed when the map does not have it.
static func _thumb(d: GroundRulesDialog, nm: String) -> Control:
	var pic := d.surface_picture(nm)
	var c: Control
	if pic != null:
		var tr := TextureRect.new()
		tr.texture = pic
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.material = GroundTile.opaque_material()
		c = tr
	else:
		var cr := ColorRect.new()
		cr.color = Color(0.3, 0.35, 0.3)
		c = cr
	c.custom_minimum_size = Vector2(26, 26)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.tooltip_text = nm
	if not d.has_surface(nm):
		c.modulate.a = 0.35
		c.tooltip_text = "%s: not on this map" % nm
	return c


## A mix as a stacked bar: each species a segment in its colour, as wide as its share (`width` 0: fill).
static func mix_bar(d: GroundRulesDialog, mix: Dictionary, width: float) -> Control:
	var h := HBoxContainer.new()
	h.name = "MixBar"
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", 0)
	h.custom_minimum_size = Vector2(width, 8)
	h.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if width <= 0.0:
		h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for sp in mix:
		var seg := ColorRect.new()
		seg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		seg.color = d.swatch(String(sp))
		seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		seg.size_flags_stretch_ratio = maxf(float(mix[sp]), 0.001)
		seg.custom_minimum_size.y = 8.0
		h.add_child(seg)
	return h
