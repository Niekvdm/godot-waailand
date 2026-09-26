# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name GrassSpeciesCatalog
extends RefCounted
## The species the project grows: the slot table's (the ACTIVE set, GrassActiveSet: the Species dialog edits it)
## found among the installed packs, each on its slot, the fallback species and the default mix; for tools and tests
## without a table, every pack's species on the lowest slots (build). It hands GrassTypes and DecoKinds the documents
## their parsers already read, so the tables are built exactly as from a JSON catalog.

var species: Array[GrassSpecies] = []   # in use: pack order, then species order
var table := {}                         # the slot table, retired species included (what the editor saves)
var fallback: StringName = &""
var default_mix := {}                   # species id -> weight, normalised
var errors: PackedStringArray = []
var grew := false                       # the table gained a species (build only)
var missing := PackedStringArray()      # table ids no installed pack has (build_active)


## The catalog of the project's GrassBladesConfig: the slot table's species among the installed packs (build_active).
## No table file yet: the starter grass is the active set (the editor writes the file then; a game uses it for the
## run). No slots_path (tools, tests): every pack in use, its species on the lowest slots (build).
static func from_config() -> GrassSpeciesCatalog:
	var cfg := GrassBladesConfig.current()
	var c: GrassSpeciesCatalog
	if cfg.slots_path == "":
		c = build(cfg.resolved_packs(), {}, cfg.fallback_species, cfg.default_mix)
	elif not FileAccess.file_exists(cfg.slots_path):
		var st := cfg.starter_pack_path()
		var starter := load(st) as GrassSpeciesPack \
			if not cfg.disabled_packs.has(st) and ResourceLoader.exists(st) else null
		c = build([starter] if starter != null else [], {}, cfg.fallback_species, cfg.default_mix)
		if Engine.is_editor_hint():
			GrassSlotTable.save_file(cfg.slots_path, c.table, c.fallback)
	else:
		var fb := GrassSlotTable.load_fallback(cfg.slots_path)
		c = build_active(cfg.installed_packs(), GrassSlotTable.load_file(cfg.slots_path),
			fb if fb != &"" else cfg.fallback_species, cfg.default_mix)
	for e in c.errors:
		push_error("[GrassSpeciesCatalog] " + e)
	return c


## The active set of a slot table: each id of `p_table` found among `p_packs` (the installed packs) on its slot, in the
## packs' order; an id no pack has is missing (an error, `missing`); nothing is assigned. The fallback: `p_fallback`
## when active (else an error), else the first pack's fallback that is active, else the first active species. The
## default mix: `p_mix` (its inactive names errors), else the first pack's with an active name, its active names.
static func build_active(p_packs: Array, p_table: Dictionary, p_fallback: StringName = &"", p_mix: Dictionary = {}) \
		-> GrassSpeciesCatalog:
	var c := GrassSpeciesCatalog.new()
	var owner := {}
	var used_packs := []
	var slot_ids := {}
	for id in p_table:
		var i := int(p_table[id])
		if i < 0 or i >= GrassTypes.SLOTS:
			c.errors.append("species '%s': slot %d is outside 0..%d" % [id, i, GrassTypes.SLOTS - 1])
		elif slot_ids.has(i):
			c.errors.append("slot %d holds two species: %s and %s" % [i, slot_ids[i], id])
		else:
			slot_ids[i] = String(id)
	for pack in p_packs:
		if pack == null:
			continue
		var used := false
		for sp in (pack as GrassSpeciesPack).species:
			if sp == null or sp.id == &"" or owner.has(sp.id):
				continue
			owner[sp.id] = String((pack as GrassSpeciesPack).name)
			var key := String(sp.id)
			if p_table.has(key) and slot_ids.get(int(p_table[key]), "") == key:
				c.species.append(sp)
				used = true
		if used:
			used_packs.append(pack)
	for i in slot_ids:
		if not owner.has(StringName(slot_ids[i])):
			c.missing.append(slot_ids[i])
			c.errors.append("slot %d: species '%s' is not installed (its pack is gone)" % [i, slot_ids[i]])
	for id in p_table:
		if owner.has(StringName(id)):
			c.table[String(id)] = int(p_table[id])
	c.fallback = c._pick_active_fallback(used_packs, p_fallback)
	c.default_mix = c._pick_mix(used_packs, p_mix) if not p_mix.is_empty() else c._pack_mix(used_packs)
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


## Every installed species' layer (GrassTypes.LAYER_*) by id: the config's installed packs, the first of a duplicate.
static func installed_layers() -> Dictionary:
	var out := {}
	for pack in GrassBladesConfig.current().installed_packs():
		for sp in pack.species:
			if sp != null and sp.id != &"" and not out.has(String(sp.id)):
				out[String(sp.id)] = GrassTypes.LAYER_SURFACE if sp.layer == GrassSpecies.Layer.SURFACE \
					else GrassTypes.LAYER_GROUND
	return out


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


func _pick_active_fallback(p_packs: Array, p_override: StringName) -> StringName:
	if p_override != &"":
		if _in_use(p_override):
			return p_override
		errors.append("the fallback species '%s' is not active" % p_override)
	for pack in p_packs:
		var f: StringName = (pack as GrassSpeciesPack).fallback_species
		if f != &"" and _in_use(f):
			return f
	return species[0].id if not species.is_empty() else &""


## The first pack's default mix that names an active species, its active names only, heaviest first; else the
## fallback alone.
func _pack_mix(p_packs: Array) -> Dictionary:
	for pack in p_packs:
		var m: Dictionary = (pack as GrassSpeciesPack).default_mix
		var keep := {}
		for id in m:
			if _in_use(StringName(id)):
				keep[id] = m[id]
		if not keep.is_empty():
			return _pick_mix([], keep)
	return {String(fallback): 1.0} if fallback != &"" else {}


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
		if species.any(func(s): return s.id == StringName(id) and s.layer == GrassSpecies.Layer.SURFACE):
			errors.append("the default mix names '%s', a surface species (it floats on water, in a water mix)" % id)
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
