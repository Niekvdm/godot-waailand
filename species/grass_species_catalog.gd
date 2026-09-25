# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name GrassSpeciesCatalog
extends RefCounted
## The species the project grows: the config's packs in use (resolved_packs) as one list,
## each species on its slot (GrassSlotTable), the fallback species and the default mix. It hands GrassTypes and
## DecoKinds the documents their parsers already read, so the tables are built exactly as from a JSON catalog.

var species: Array[GrassSpecies] = []   # in use: pack order, then species order
var table := {}                         # the slot table, retired species included (what the editor saves)
var fallback: StringName = &""
var default_mix := {}                   # species id -> weight, normalised
var errors: PackedStringArray = []
var grew := false                       # the table gained a species


## The catalog of the project's GrassBladesConfig. In the editor a table that grew is saved; in the game it is not,
## and the new species get their slots for this run (the same on every machine).
static func from_config() -> GrassSpeciesCatalog:
	var cfg := GrassBladesConfig.current()
	var c := build(cfg.resolved_packs(), GrassSlotTable.load_file(cfg.slots_path), cfg.fallback_species, cfg.default_mix)
	if c.grew and cfg.slots_path != "":
		if Engine.is_editor_hint():
			GrassSlotTable.save_file(cfg.slots_path, c.table)
		else:
			push_warning("GrassSpeciesCatalog: species without a slot in %s (open the project in the editor to save "
				% cfg.slots_path + "them): they get their slots for this run only")
	for e in c.errors:
		push_error("[GrassSpeciesCatalog] " + e)
	return c


static func build(p_packs: Array, p_table: Dictionary, p_fallback: StringName = &"", p_mix: Dictionary = {}) -> GrassSpeciesCatalog:
	var c := GrassSpeciesCatalog.new()
	var owner := {}
	var ids := []
	for pack in p_packs:
		if pack == null:
			continue
		var pn := String((pack as GrassSpeciesPack).name)
		for sp in (pack as GrassSpeciesPack).species:
			if sp == null or sp.id == &"":
				c.errors.append("pack %s: a species without an id" % pn)
				continue
			if owner.has(sp.id):
				c.errors.append("species '%s' is in two packs: %s and %s" % [sp.id, owner[sp.id], pn])
				continue
			owner[sp.id] = pn
			c.species.append(sp)
			ids.append(String(sp.id))
	var a := GrassSlotTable.assign(p_table, ids, GrassTypes.SLOTS)
	c.table = a["table"]
	c.grew = a["grew"]
	if not (a["left_out"] as PackedStringArray).is_empty():
		c.errors.append("more than %d species: %s left out" % [GrassTypes.SLOTS, ", ".join(a["left_out"])])
		c.species = c.species.filter(func(s): return not (a["left_out"] as PackedStringArray).has(String(s.id)))
	c.fallback = c._pick_fallback(p_packs, p_fallback)
	c.default_mix = c._pick_mix(p_packs, p_mix)
	return c


func slot_of(p_id: StringName) -> int:
	return int(table.get(String(p_id), -1))


## The fallback's slot (1 when there are no species).
func fallback_slot() -> int:
	return slot_of(fallback) if fallback != &"" else 1


## {"types": [...]}: every species' row on its slot (GrassTypes._load_doc).
func types_doc() -> Dictionary:
	var rows := []
	for sp in species:
		rows.append(sp.to_row_json(slot_of(sp.id)))
	return {"types": rows}


## {"kinds": [...]}: every species' decorations, hosted by the species (DecoKinds._load_doc). A decoration without its
## own salt takes one from its name.
func kinds_doc() -> Dictionary:
	var kinds := []
	for sp in species:
		for d in sp.decorations:
			if d == null:
				continue
			var salt := d.salt if d.salt >= 0 else 100 + 16 * (String(d.name).hash() & 0xFFFF)
			kinds.append(d.to_kind_json(String(sp.id), salt))
	return {"kinds": kinds}


func _in_use(p_id: StringName) -> bool:
	return species.any(func(s): return s.id == p_id)


func _pick_fallback(p_packs: Array, p_override: StringName) -> StringName:
	var want := p_override
	if want == &"":
		for pack in p_packs:
			if pack != null and (pack as GrassSpeciesPack).fallback_species != &"":
				want = (pack as GrassSpeciesPack).fallback_species
				break
	if want != &"" and _in_use(want):
		return want
	if want != &"":
		errors.append("the fallback species '%s' is in no pack in use" % want)
	return species[0].id if not species.is_empty() else &""


func _pick_mix(p_packs: Array, p_override: Dictionary) -> Dictionary:
	var want := p_override
	if want.is_empty():
		for pack in p_packs:
			if pack != null and not (pack as GrassSpeciesPack).default_mix.is_empty():
				want = (pack as GrassSpeciesPack).default_mix
				break
	var mix := {}
	var total := 0.0
	for id in want:
		if not _in_use(StringName(id)):
			errors.append("the default mix names '%s', which is in no pack in use" % id)
			continue
		mix[String(id)] = float(want[id])
		total += float(want[id])
	if mix.is_empty() or total <= 0.0:
		return {String(fallback): 1.0} if fallback != &"" else {}
	# Heaviest first, ties by id: a mix's order is its pick order, and a resource file gives a Dictionary back sorted by
	# key (a mix of verge 0.6 and pasture 0.4 would come back pasture first and swap the default mix's species).
	var ids := mix.keys()
	ids.sort_custom(func(x, y): return mix[x] > mix[y] or (mix[x] == mix[y] and String(x) < String(y)))
	var out := {}
	for id in ids:
		out[id] = mix[id] / total
	return out
