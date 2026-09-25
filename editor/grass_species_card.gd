# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
extends RefCounted
## A grass species' hover card (the Grass workspace's library): the larger picture and what
## GrassSpeciesPreview.facts() says about it.


## The hover card: the larger picture (when there is one) and the facts (GrassPaintProvider.library()).
static func make_card(p_card: Texture2D, p_facts: Dictionary) -> Control:
	var panel := PanelContainer.new()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	panel.add_child(box)
	if p_card != null:
		var pic := TextureRect.new()
		pic.texture = p_card
		pic.custom_minimum_size = Vector2(360, 240)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		box.add_child(pic)
	var lines := card_lines(p_facts)
	for i in lines.size():
		var l := Label.new()
		l.text = lines[i]
		l.add_theme_font_size_override("font_size", 14 if i == 0 else 11)
		box.add_child(l)
	return panel


## The card's text: the name (and "invented"), the height or what it hosts, the sea depth, the flowers and
## when they bloom, and the ground that grows it (the four biggest shares).
static func card_lines(f: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	out.append(String(f.get("name", "")).capitalize() + ("  (invented)" if f.get("invented", false) else ""))
	if f.get("host_only", false):
		out.append("No blades: it hosts its colonies")
	else:
		out.append("%.2f m tall" % float(f.get("height", 0.0)))
	var depth = f.get("depth")
	if depth is Vector2:
		out.append("%s-%s m under the sea" % [_num(depth.x), _num(depth.y)])
	for fl in f.get("flowers", []):
		out.append("%s: %s" % [String(fl["name"]).replace("_", " ").capitalize(), fl["bloom"]])
	var grows: Array = f.get("grows_on", [])
	if grows.is_empty():
		out.append("No ground grows it: paint only")
	else:
		var parts := PackedStringArray()
		for g in grows.slice(0, 4):
			var above: float = g["above_m"]
			parts.append("%s %d%%%s" % [g["ground"], roundi(100.0 * float(g["share"])),
				" above %d m" % roundi(above) if above >= 0.0 else ""])
		out.append("Grows on: " + ", ".join(parts))
	return out


static func _num(v: float) -> String:
	return str(snappedf(v, 0.1)).trim_suffix(".0")
