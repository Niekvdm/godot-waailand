# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name GroundRulesSeasonsTab
extends RefCounted
## The Ground rules dialog's Seasons tab: every species the map grows on one year strip (each flower kind's bud, bloom
## and seed bars, the pinned days, the preview date), a mode chip per row, a row's controls in place (Calendar | Always in bloom | Pin a stage | Fixed date), and
## the map's date.

const PREFIX := 280.0          # picture + name + mode chip, before the strip
const PINNED := Color("8bc34a")


static func build(d: GroundRulesDialog) -> Control:
	var plan := GrassSeasonPlan.from_rules(d.rules)
	plan.bind(d.kinds, d.types)
	var v := VBoxContainer.new()
	v.name = "SeasonsTab"
	v.add_theme_constant_override("separation", 6)
	var top := HBoxContainer.new()
	var legend := d.hint("Bars: bud · bloom · seed and fading. White mark: pinned. Blue line: the preview date.")
	legend.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(legend)
	var all: HBoxContainer = d.kit.toggle_row("Show all species", d.show_all_species)
	all.name = "ShowAll"
	(all.get_node("Label") as Label).size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	(all.get_node("Toggle") as CheckBox).toggled.connect(func(on: bool) -> void:
		d.show_all_species = on
		d.rebuild())
	top.add_child(all)
	top.add_child(_map_date(d))
	v.add_child(top)
	var mh := HBoxContainer.new()
	var pad := Control.new()
	pad.custom_minimum_size.x = PREFIX
	mh.add_child(pad)
	var hdr := SeasonYearStrip.new()
	hdr.header = true
	hdr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mh.add_child(hdr)
	v.add_child(mh)
	var sc := ScrollContainer.new()
	sc.name = "SeasonsScroll"
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 3)
	var today := plan.day(GrassEditorPreview.day)
	for sp in _species(d):
		list.add_child(_row(d, plan, sp, today))
		if d.season_open == sp:
			list.add_child(_controls(d, plan, sp))
	sc.add_child(list)
	v.add_child(sc)
	return v


## The rows: the species the map grows (every species with Show all), in palette order.
static func _species(d: GroundRulesDialog) -> PackedStringArray:
	var used := d.rules.species_used()
	var out := PackedStringArray()
	for e in GrassPaintTool.palette(d.types):
		var sp := String(e["name"])
		if d.show_all_species or used.has(sp):
			out.append(sp)
	return out


static func _mode_text(s: Dictionary) -> String:
	match String(s.get("mode", "calendar")):
		"bloom":
			return "Always in bloom"
		"stage":
			var t := float(s.get("stage", GrassSeasonPlan.PRIME))
			var best: Array = GrassSeasonPlan.TICKS[0]
			for tk in GrassSeasonPlan.TICKS:
				if absf(float(tk[1]) - t) < absf(float(best[1]) - t):
					best = tk
			return "Pinned · %s" % best[0]
		"date":
			return "Fixed · %s" % GrassSeason.label(float(s.get("day", 0.0)))
	return "Calendar"


static func _row(d: GroundRulesDialog, plan: GrassSeasonPlan, sp: String, today: float) -> Control:
	var s := d.rules.season_of(sp)
	var m := String(s["mode"])
	var open := d.season_open == sp
	var row := GroundDropTarget.new().setup("", Callable(),
		GroundRulesDialog.box(Color(d.accent, 0.12) if open else Color(0, 0, 0, 0), d.accent if open else Color(0, 0, 0, 0)), null)
	row.name = "Season_" + sp
	row.pressed.connect(func() -> void:
		d.season_open = "" if d.season_open == sp else sp
		d.rebuild())
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", 8)
	var pic := d.species_picture(sp)
	var p: Control
	if pic != null:
		var tr := TextureRect.new()
		tr.texture = pic
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		p = tr
	else:
		var cr := ColorRect.new()
		cr.color = d.swatch(sp)
		p = cr
	p.custom_minimum_size = Vector2(26, 26)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(p)
	var nm := Label.new()
	nm.text = sp.capitalize()
	nm.custom_minimum_size.x = 90.0
	nm.add_theme_font_size_override("font_size", 13)
	h.add_child(nm)
	var chip := Label.new()
	chip.text = _mode_text(s)
	chip.custom_minimum_size.x = PREFIX - 26.0 - 90.0 - 24.0
	chip.add_theme_font_size_override("font_size", 10)
	if m != "calendar":
		chip.add_theme_color_override("font_color", PINNED)
	else:
		chip.modulate = GroundRulesDialog.DIM
	h.add_child(chip)
	var strip := SeasonYearStrip.new()
	strip.name = "Strip"
	strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for i in d.kinds.kinds.size():
		var k: Dictionary = d.kinds.kinds[i]
		if String(d.types.row(int(k["host"])).get("name", "")) != sp:
			continue
		var keys: Vector4 = k["bloom"]
		var cols: Array = d.kinds.colours(i, 1.0)
		strip.lanes.append({"keys": keys, "colour": cols[0] if not cols.is_empty() else Color.WHITE})
		strip.pins.append(plan.kind_day(keys, sp, today) if m != "calendar" and keys.x >= 0.0 else -1.0)
	if strip.lanes.is_empty():
		strip.note = "no flowers · blades only"
	strip.today = today
	h.add_child(strip)
	row.add_child(h)
	return row


static func _controls(d: GroundRulesDialog, plan: GrassSeasonPlan, sp: String) -> Control:
	var box := PanelContainer.new()
	box.name = "SeasonControls"
	box.add_theme_stylebox_override("panel", GroundRulesDialog.box(Color(1, 1, 1, 0.04)))
	var v := VBoxContainer.new()
	box.add_child(v)
	var s := d.rules.season_of(sp)
	var m := String(s["mode"])
	var flowers := plan.has_flowers(sp)
	var seg := HBoxContainer.new()
	seg.name = "Modes"
	var group := ButtonGroup.new()
	for pair in [["Calendar", "calendar"], ["Always in bloom", "bloom"], ["Pin a stage", "stage"], ["Fixed date", "date"]]:
		var b: Button = d.kit.toggle_chip(pair[0], m == pair[1], d.accent)
		b.name = "Mode_" + String(pair[1])
		b.button_group = group
		var mode: String = pair[1]
		b.disabled = (mode == "bloom" or mode == "stage") and not flowers
		b.pressed.connect(func() -> void:
			var val := GrassSeasonPlan.PRIME if mode == "stage" else (GrassEditorPreview.day if mode == "date" else 0.0)
			d.change(func() -> void: d.rules.set_season(sp, mode, val)))
		seg.add_child(b)
	v.add_child(seg)
	if not flowers:
		v.add_child(d.hint("No flowers: the calendar, or a fixed date for its blades' look."))
	elif m == "stage":
		v.add_child(d.hint("Each of its flower kinds at this point of its own window; its blades follow the first."))
	if m == "stage":
		v.add_child(_stage(d, sp, float(s.get("stage", GrassSeasonPlan.PRIME))))
	elif m == "date":
		v.add_child(_date(d, sp, float(s.get("day", 0.0))))
	return box


static func _stage(d: GroundRulesDialog, sp: String, t: float) -> Control:
	var v := VBoxContainer.new()
	v.name = "Stage"
	var sl := HSlider.new()
	sl.name = "Slider"
	sl.min_value = 0.0
	sl.max_value = 1.0
	sl.step = 0.01
	sl.value = t
	sl.scrollable = false
	sl.focus_mode = Control.FOCUS_NONE
	d.kit.style_slider_accent(sl, d.accent)
	sl.drag_ended.connect(func(moved: bool) -> void:
		if moved:
			d.change(func() -> void: d.rules.set_season(sp, "stage", sl.value)))
	v.add_child(sl)
	var ticks := HBoxContainer.new()
	ticks.name = "Ticks"
	for tk in GrassSeasonPlan.TICKS:
		var b: Button = d.kit.toggle_chip(String(tk[0]), absf(float(tk[1]) - t) < 0.005, d.accent)
		var at := float(tk[1])
		b.pressed.connect(func() -> void:
			d.change(func() -> void: d.rules.set_season(sp, "stage", at)))
		ticks.add_child(b)
	v.add_child(ticks)
	return v


static func _date(d: GroundRulesDialog, sp: String, day: float) -> Control:
	var v := VBoxContainer.new()
	v.name = "Date"
	var months := HFlowContainer.new()
	for i in 12:
		var b: Button = d.kit.chip(GrassSeason.MONTHS[i], false, d.accent)
		var dm: float = GrassPreviewMenu.DAYS[i]
		b.tooltip_text = GrassSeason.label(dm)
		b.pressed.connect(func() -> void:
			d.change(func() -> void: d.rules.set_season(sp, "date", dm)))
		months.add_child(b)
	v.add_child(months)
	var row: VBoxContainer = d.kit.slider_row("Day", 0.0, 364.0, 1.0, day, "", d.accent)
	row.name = "DayRow"
	var val: Label = row.get_node("Head/Value")
	val.text = GrassSeason.label(day)
	var sl: HSlider = row.get_node("Slider")
	sl.name = "Slider"
	sl.scrollable = false
	sl.value_changed.connect(func(x: float) -> void: val.text = GrassSeason.label(x))
	sl.drag_ended.connect(func(moved: bool) -> void:
		if moved:
			d.change(func() -> void: d.rules.set_season(sp, "date", sl.value)))
	v.add_child(row)
	return v


static func _map_date(d: GroundRulesDialog) -> Control:
	var ob := OptionButton.new()
	ob.name = "MapDate"
	ob.focus_mode = Control.FOCUS_NONE
	ob.add_item("Map date: the game clock", 0)
	for i in 12:
		ob.add_item("Map date: fixed, %s" % GrassSeason.label(GrassPreviewMenu.DAYS[i]), i + 1)
	var md := d.rules.map_date
	var sel := 0
	if md >= 0.0:
		var at := GrassPreviewMenu.DAYS.find(md)
		if at >= 0:
			sel = at + 1
		else:
			ob.add_item("Map date: fixed, %s" % GrassSeason.label(md), 100)
			sel = ob.item_count - 1
	ob.select(sel)
	ob.item_selected.connect(func(idx: int) -> void:
		var id := ob.get_item_id(idx)
		var day := -1.0 if id == 0 else (md if id == 100 else float(GrassPreviewMenu.DAYS[id - 1]))
		d.change(func() -> void: d.rules.set_map_date(day)))
	return ob
