# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name GroundMixEditor
extends RefCounted
## A species mix in the Ground rules dialog: the stacked bar, a row per species (picture, name, weight on release, share,
## ✕) and the species strip (click one, or drag it onto the editor, to add it)
## (at most six). An empty mix inherits (a rule: Everything else's; Everything else: the defaults) and is shown dimmed;
## adding to it first copies what it inherited. A water kind's mix inherits nothing (empty, it floats nothing) and
## offers surface species only; a ground mix ground species only.


static func build(d: GroundRulesDialog, i: int, band: bool) -> GroundDropTarget:
	var r: Dictionary = d.rules.rules[i] if i >= 0 else d.rules.everything_else
	var mix: Dictionary = r["band"]["species"] if band else r["species"]
	var water := d.rules.is_water(i)
	var inherited := {} if water else (d.mix_of(-1) if i >= 0 else GrassTerrainGrowth.pack_default_mix())
	var layer := GrassTypes.LAYER_SURFACE if water else GrassTypes.LAYER_GROUND
	var add := func(sp: String) -> void:
		var base := mix if not mix.is_empty() else inherited
		var tot := 0.0
		for k in base:
			tot += float(base[k])
		var w := snappedf(tot / base.size(), 0.01) if not base.is_empty() else 1.0
		d.change(func() -> void:
			if mix.is_empty():
				for k in inherited:
					d.rules.set_weight(i, String(k), float(inherited[k]), band)
			d.rules.set_weight(i, sp, w, band))
	var target := GroundDropTarget.new().setup("ground_species", add, GroundRulesDialog.box(Color(0, 0, 0, 0)),
		GroundRulesDialog.box(Color(d.accent, 0.12), d.accent))
	target.name = "BandMix" if band else "Mix"
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 4)
	target.add_child(v)
	var bar := GroundRulesRulesTab.mix_bar(d, mix if not mix.is_empty() else inherited, 0.0)
	bar.custom_minimum_size.y = 12.0
	if mix.is_empty():
		bar.modulate.a = 0.4
		v.add_child(bar)
		v.add_child(d.hint("Floats nothing. Add a species to float it on this water." if water
			else ("Everything else's mix. Add a species to give this rule its own." if i >= 0
			else "The packs' default mix. Add a species to set this map's own.")))
	else:
		v.add_child(bar)
	var tot := 0.0
	for sp in mix:
		tot += float(mix[sp])
	for sp in mix:
		v.add_child(_row(d, i, band, String(sp), float(mix[sp]), tot))
	var strip := HFlowContainer.new()
	strip.name = "SpeciesStrip"
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var full := mix.size() >= GrassGroundRules.MIX_MAX
	for e in GrassPaintTool.palette(d.types):
		var sp := String(e["name"])
		if mix.has(sp) or int(e["layer"]) != layer:
			continue
		var t := GroundTile.make("ground_species", sp, d.species_picture(sp), sp.capitalize(), 28, Color(0, 0, 0, 0), false,
			e["colour"])
		t.disabled = full
		t.pressed.connect(func() -> void: add.call(sp))
		strip.add_child(t)
	v.add_child(strip)
	if full:
		v.add_child(d.hint("At most %d species." % GrassGroundRules.MIX_MAX))
	return target


static func _row(d: GroundRulesDialog, i: int, band: bool, sp: String, w: float, tot: float) -> Control:
	var row := HBoxContainer.new()
	row.name = "Species_" + sp
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
	p.custom_minimum_size = Vector2(24, 24)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(p)
	var nm := Label.new()
	nm.text = sp.capitalize()
	nm.custom_minimum_size.x = 80.0
	row.add_child(nm)
	var sl := HSlider.new()
	sl.name = "Weight"
	sl.min_value = 0.05
	sl.max_value = 1.0
	sl.step = 0.05
	sl.value = clampf(w, 0.05, 1.0)
	sl.scrollable = false
	sl.focus_mode = Control.FOCUS_NONE
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	d.kit.style_slider_accent(sl, d.accent)
	sl.drag_ended.connect(func(moved: bool) -> void:
		if moved:
			d.change(func() -> void: d.rules.set_weight(i, sp, sl.value, band)))
	row.add_child(sl)
	var share := Label.new()
	share.text = "%d %%" % roundi(100.0 * w / maxf(tot, 1e-6))
	share.custom_minimum_size.x = 40.0
	row.add_child(share)
	var rm := Button.new()
	rm.name = "Remove"
	rm.text = "✕"
	rm.tooltip_text = "Remove %s" % sp
	rm.focus_mode = Control.FOCUS_NONE
	rm.pressed.connect(func() -> void:
		d.change(func() -> void: d.rules.set_weight(i, sp, 0.0, band)))
	row.add_child(rm)
	return row
