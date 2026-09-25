# Copyright (c) 2026 Digitzone
# SPDX-License-Identifier: MIT
@tool
class_name GrassSlotTable
extends RefCounted
## The project's slot table: species id -> the slot the grass maps' species
## byte and the GPU tables use. A new species takes the lowest free slot; a slot is never reused, so old paint never
## turns into another species. One JSON file: {"format": 1, "slots": {id: slot}}.

const FORMAT := 1


## The table in a file; {} when there is none (a broken file is an error, and {}).
static func load_file(p_path: String) -> Dictionary:
	if p_path == "" or not FileAccess.file_exists(p_path):
		return {}
	var doc = JSON.parse_string(FileAccess.get_file_as_string(p_path))
	if typeof(doc) != TYPE_DICTIONARY or typeof(doc.get("slots")) != TYPE_DICTIONARY:
		push_error("GrassSlotTable: %s is not a slot table (want {\"format\": 1, \"slots\": {id: slot}})" % p_path)
		return {}
	var out := {}
	var pairs := []
	for id in doc["slots"]:
		pairs.append([String(id), int(doc["slots"][id])])
	pairs.sort_custom(func(a, b): return a[1] < b[1])
	for p in pairs:
		out[p[0]] = p[1]
	return out


## Writes the table, in slot order.
static func save_file(p_path: String, p_table: Dictionary) -> Error:
	var pairs := []
	for id in p_table:
		pairs.append([String(id), int(p_table[id])])
	pairs.sort_custom(func(a, b): return a[1] < b[1])
	var slots := {}
	for p in pairs:
		slots[p[0]] = p[1]
	var f := FileAccess.open(p_path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify({"format": FORMAT, "slots": slots}, "\t", false) + "\n")
	f.close()
	return OK


## Gives every id without a slot the lowest free one below `cap`, in order: {"table", "grew", "left_out"}.
static func assign(p_table: Dictionary, p_ids: Array, p_cap: int) -> Dictionary:
	var table := p_table.duplicate()
	var used := {}
	for id in table:
		used[int(table[id])] = true
	var grew := false
	var left_out := PackedStringArray()
	var next := 0
	for id in p_ids:
		var key := String(id)
		if table.has(key):
			continue
		while next < p_cap and used.has(next):
			next += 1
		if next >= p_cap:
			left_out.append(key)
			continue
		table[key] = next
		used[next] = true
		grew = true
	return {"table": table, "grew": grew, "left_out": left_out}
