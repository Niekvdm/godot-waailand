# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name GrassActiveSet
extends RefCounted
## The active species, as the Species dialog edits them: the slot table's 32 slots (GrassTypes.SLOTS), each an
## installed species' id or empty, and the fallback. Installed species cost nothing; an active one takes its slot and
## brings its flowers (at most DecoKinds.MAX_KINDS kinds in all). Every change checks both budgets and, when it
## refuses, says what it needs and what is free ("" when it is done). A slot whose species no pack has any more is
## missing: it keeps its slot (and its paint) until it is emptied.

## The slots (GrassTypes.SLOTS).
const SLOTS := 32
## The flower kinds all active species may bring together (DecoKinds.MAX_KINDS).
const KINDS := 32

## SLOTS entries, each an id or &"" (empty).
var slots: Array[StringName] = []
## The fallback: an active species, or &"" (the config's or the first pack's then).
var fallback: StringName = &""
## The budgets the last refused change would have passed: "species", "kinds" or both ("species,kinds"); "" when it
## was done or refused for another reason. The dialog turns their meters red.
var over := ""
var _installed := {}             # id -> GrassSpecies


## `p_installed`: every installed species (GrassSpecies); `p_table`: the slot table (id -> slot); `p_fallback`: its
## fallback.
func _init(p_installed: Array = [], p_table: Dictionary = {}, p_fallback: StringName = &"") -> void:
	for sp in p_installed:
		if sp != null and not _installed.has(sp.id):
			_installed[sp.id] = sp
	slots.resize(SLOTS)
	slots.fill(&"")
	for id in p_table:
		var i := int(p_table[id])
		if i >= 0 and i < SLOTS:
			slots[i] = StringName(id)
	fallback = p_fallback if slot_of(p_fallback) >= 0 else &""


## A species' layer: "float" (a SURFACE species), "under" (a ground species with a depth range: on the bed under
## water), "wet" (a ground species that stands in shallow water) or "ground".
static func layer_of(sp: GrassSpecies) -> String:
	if sp == null:
		return "ground"
	if sp.layer == GrassSpecies.Layer.SURFACE:
		return "float"
	if sp.depth_m != Vector2.ZERO:
		return "under"
	if sp.wet_depth_m > 0.0:
		return "wet"
	return "ground"


## The flower kinds a species brings: its decorations.
static func kinds_in(sp: GrassSpecies) -> int:
	return sp.decorations.filter(func(d): return d != null).size() if sp != null else 0


## The installed species `id` (null: not installed).
func species(id: StringName) -> GrassSpecies:
	return _installed.get(id)


## Whether some installed pack has `id`.
func is_installed(id: StringName) -> bool:
	return _installed.has(id)


## The slot `id` is active in; -1: not active.
func slot_of(id: StringName) -> int:
	return slots.find(id) if id != &"" else -1


## The active ids in slot order (missing ones included).
func active() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in slots:
		if id != &"":
			out.append(id)
	return out


## The slots in use (missing species included).
func used_slots() -> int:
	return active().size()


## The empty slots.
func free_slots() -> int:
	return SLOTS - used_slots()


## The flower kinds species `id` brings (0 when it is not installed).
func kinds_of(id: StringName) -> int:
	return kinds_in(species(id))


## The flower kinds the active species bring together.
func used_kinds() -> int:
	var n := 0
	for id in active():
		n += kinds_of(id)
	return n


## Whether slot i holds a species that is not installed.
func is_missing(i: int) -> bool:
	return slots[i] != &"" and not is_installed(slots[i])


## Active species per layer: {"ground" (wet included), "under", "float"}.
func layer_counts() -> Dictionary:
	var out := {"ground": 0, "under": 0, "float": 0}
	for id in active():
		var l := layer_of(species(id))
		out["ground" if l == "wet" else l] += 1
	return out


## Makes `id` active in slot `i` (-1: the first free one). "" when done, else why not.
func place(id: StringName, i := -1) -> String:
	over = ""
	var why := _can_take(id)
	if why != "":
		return why
	if i < 0:
		i = slots.find(&"")
		if i < 0:
			over = "species"
			return "No free slot: all %d are active." % SLOTS
	elif slots[i] != &"":
		return "Slot %d holds %s: replace it instead." % [i, slots[i]]
	var k := kinds_of(id)
	if used_kinds() + k > KINDS:
		over = "kinds"
		return "%s brings %s; %d of %d are free." % [id, _n(k, "flower kind"), KINDS - used_kinds(), KINDS]
	slots[i] = id
	return ""


## Puts `id` in the filled slot `i` in place of its species. "" when done, else why not.
func replace(i: int, id: StringName) -> String:
	over = ""
	if slots[i] == &"":
		return "Slot %d is empty: place it there." % i
	var why := _can_take(id)
	if why != "":
		return why
	var k := kinds_of(id)
	var free := KINDS - used_kinds() + kinds_of(slots[i])
	if k > free:
		over = "kinds"
		return "%s brings %s; %d of %d are free with %s gone." % [id, _n(k, "flower kind"), free, KINDS, slots[i]]
	if fallback == slots[i]:
		fallback = &""
	slots[i] = id
	return ""


## Makes every inactive species of `ids` active, in order, in the free slots: all of them or none. `label` names them
## in the refusal (a pack's name).
func fill(ids: Array, label: String) -> String:
	over = ""
	var todo: Array[StringName] = []
	for id in ids:
		var sid := StringName(id)
		if not is_installed(sid):
			return "%s is not installed." % sid
		if slot_of(sid) < 0 and not todo.has(sid):
			todo.append(sid)
	var k := 0
	for id in todo:
		k += kinds_of(id)
	if todo.size() > free_slots() or used_kinds() + k > KINDS:
		over = ",".join(PackedStringArray((["species"] if todo.size() > free_slots() else [])
			+ (["kinds"] if used_kinds() + k > KINDS else [])))
		return "%s doesn't fit. It needs %s and %s; %s and %s are free." % [label, _n(todo.size(), "slot"),
			_n(k, "flower kind"), _n(free_slots(), "slot"), _n(KINDS - used_kinds(), "kind")]
	for id in todo:
		slots[slots.find(&"")] = id
	return ""


## Empties slot i (its paint grows the fallback from now on).
func empty(i: int) -> void:
	if slots[i] == fallback:
		fallback = &""
	slots[i] = &""


## Makes an active species the fallback. "" when done, else why not.
func set_fallback(id: StringName) -> String:
	if slot_of(id) < 0:
		return "%s is not active." % id
	fallback = id
	return ""


## The slot table: id -> slot (missing species kept).
func to_table() -> Dictionary:
	var out := {}
	for i in SLOTS:
		if slots[i] != &"":
			out[String(slots[i])] = i
	return out


## The state (the dialog's undo steps).
func snapshot() -> Dictionary:
	return {"slots": slots.duplicate(), "fallback": fallback}


## Back to a snapshot().
func restore(s: Dictionary) -> void:
	slots.assign(s["slots"])
	fallback = s["fallback"]


static func _n(n: int, word: String) -> String:
	return "%d %s%s" % [n, word, "" if n == 1 else "s"]


func _can_take(id: StringName) -> String:
	if not is_installed(id):
		return "%s is not installed." % id
	var at := slot_of(id)
	if at >= 0:
		return "%s is already active in slot %d." % [id, at]
	return ""
